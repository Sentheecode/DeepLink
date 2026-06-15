"""
DeepLink Channel - WSS entry point.

Manages a single WebSocket connection to the Broker,
delegates RPC to the appropriate AgentAdapter via AgentRegistry.
"""
from __future__ import annotations

import asyncio
import json
import os
import sys
import uuid
from pathlib import Path
from typing import Any

import httpx

from channel.protocol import (
    AUTHENTICATE, COMMAND, PING, PONG,
    make_auth, make_authenticated, make_command, make_ping, make_pong,
)
from channel.registry import create_default_registry, AgentRegistry


def load_env_file(path: Path) -> None:
    """Load simple KEY=VALUE settings without replacing explicit process values."""
    if not path.is_file():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


load_env_file(Path.home() / ".deeplink-channel" / "channel.env")

BROKER_URL = os.environ["BROKER_URL"].rstrip("/")
BROKER_TOKEN = os.environ["BROKER_TOKEN"]
DEVICE_ID = os.environ.get("DEVICE_ID", "hermes-main")
DEVICE_NAME = os.environ.get("DEVICE_NAME", DEVICE_ID)

WSS_URL = BROKER_URL.replace("https://", "wss://").replace("http://", "ws://") + "/v1/channel/connect"
MAX_CONCURRENT = 4
PING_INTERVAL = 20


def headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _trim_skills(skills: list[dict[str, str]], max_total: int = 50) -> list[dict[str, str]]:
    """Limit skills payload to avoid 413 Request Entity Too Large."""
    trimmed = []
    for s in skills:
        desc = (s.get("description") or "")[:80]  # truncate descriptions
        trimmed.append({"name": s.get("name", ""), "description": desc})
        if len(trimmed) >= max_total:
            break
    return trimmed


async def register_agents_via_http(registry: AgentRegistry) -> None:
    """Fallback: register agents via HTTP POST during transition period."""
    async with httpx.AsyncClient(timeout=20) as client:
        for adapter in registry.all:
            info = await adapter.discover()
            payload = {
                "id": info["id"],
                "name": info["name"],
                "kind": info["kind"],
                "endpoint": info["endpoint"],
                "version": info["version"],
                "status": info["status"],
                "capabilities": info["capabilities"][:30],
                "skills": _trim_skills(info["skills"]),
            }
            try:
                resp = await client.post(
                    f"{BROKER_URL}/v1/agents/register",
                    headers=headers(BROKER_TOKEN),
                    json=payload,
                )
                resp.raise_for_status()
                print(f"  registered agent: {info['name']} ({len(payload['skills'])} skills)", flush=True)
            except httpx.HTTPStatusError as e:
                print(f"  agent registration failed for {info['name']}: {e.response.status_code}", flush=True)


async def register_device_via_http(registry: AgentRegistry) -> None:
    """Register the device before using the legacy long-poll fallback."""
    capabilities = sorted({adapter.kind for adapter in registry.all})
    async with httpx.AsyncClient(timeout=20) as client:
        response = await client.post(
            f"{BROKER_URL}/v1/nodes/register",
            headers=headers(BROKER_TOKEN),
            json={
                "device_id": DEVICE_ID,
                "name": DEVICE_NAME,
                "capabilities": capabilities,
            },
        )
        response.raise_for_status()


async def register_fallback_channel(registry: AgentRegistry) -> None:
    await register_device_via_http(registry)
    await register_agents_via_http(registry)


async def heartbeat_forever(registry: AgentRegistry) -> None:
    """Keep presence independent from long-poll and command execution."""
    while True:
        try:
            async with httpx.AsyncClient(timeout=15) as client:
                device_response = await client.post(
                    f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/heartbeat",
                    headers=headers(BROKER_TOKEN),
                )
                if device_response.status_code == 404:
                    await register_fallback_channel(registry)
                else:
                    device_response.raise_for_status()
                    for adapter in registry.all:
                        response = await client.post(
                            f"{BROKER_URL}/v1/agents/{adapter.id}/heartbeat",
                            headers=headers(BROKER_TOKEN),
                        )
                        if response.status_code == 404:
                            await register_agents_via_http(registry)
                            break
                        response.raise_for_status()
        except Exception as error:
            print(f"heartbeat error: {error}", flush=True)
        await asyncio.sleep(PING_INTERVAL)


async def handle_command(registry: AgentRegistry, cmd: dict[str, Any]) -> dict[str, Any]:
    """Execute a command on the appropriate agent."""
    agent_id = cmd.get("agent_id", "")
    method = cmd.get("method", "")
    params = cmd.get("params", {})
    command_id = cmd.get("command_id", str(uuid.uuid4()))

    try:
        adapter = registry.get(agent_id)
        data = await adapter.execute(method, params)
        return {"command_id": command_id, "ok": True, "data": data}
    except Exception as e:
        return {"command_id": command_id, "ok": False, "error": str(e)}


async def run_forever() -> None:
    """Main loop: WSS connection with auto-reconnect."""
    registry = create_default_registry()
    reconnect_delays = [1, 2, 4, 8, 15]
    heartbeat_task = asyncio.create_task(heartbeat_forever(registry))

    # First, register via HTTP (transition period)
    try:
        await register_fallback_channel(registry)
        agent_list = registry.list()
        print(f"registered {len(agent_list)} agent(s): {[a['name'] for a in agent_list]}", flush=True)
    except Exception as e:
        print(f"HTTP registration failed: {e}", flush=True)

    attempt = 0
    try:
        while True:
            try:
                delay = reconnect_delays[min(attempt, len(reconnect_delays) - 1)]
                if attempt > 0:
                    print(f"reconnecting in {delay}s (attempt {attempt})", flush=True)
                    await asyncio.sleep(delay)

                async with httpx.AsyncClient(timeout=40) as client:
                    # Use HTTP long-poll as fallback (WSS will replace this)
                    resp = await client.get(
                        f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/commands/next",
                        headers=headers(BROKER_TOKEN),
                        params={"timeout": 25},
                    )
                    if resp.status_code == 204:
                        attempt = 0
                        continue
                    resp.raise_for_status()
                    command = resp.json()

                    sem = asyncio.Semaphore(MAX_CONCURRENT)
                    async def exec_with_sem(cmd: dict[str, Any]) -> None:
                        async with sem:
                            result = await handle_command(registry, cmd)
                            async with httpx.AsyncClient(timeout=40) as result_client:
                                response = await result_client.post(
                                    f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/commands/{cmd['id']}/result",
                                    headers=headers(BROKER_TOKEN),
                                    json={"ok": result["ok"], "data": result.get("data"), "error": result.get("error")},
                                )
                                response.raise_for_status()

                    asyncio.create_task(exec_with_sem(command))
                    attempt = 0

            except httpx.HTTPStatusError as e:
                if e.response.status_code == 404:
                    print("device not registered, re-registering...", flush=True)
                    await register_fallback_channel(registry)
                else:
                    print(f"HTTP error: {e}", flush=True)
                attempt += 1
                await asyncio.sleep(3)
            except Exception as e:
                print(f"channel error: {e}", flush=True)
                attempt += 1
                await asyncio.sleep(3)
    finally:
        heartbeat_task.cancel()


async def check() -> None:
    """Health check: discover and register agents, verify connectivity."""
    registry = create_default_registry()
    await register_fallback_channel(registry)
    agent_list = registry.list()
    print(f"channel check passed: {DEVICE_NAME} ({DEVICE_ID}) | {len(agent_list)} agent(s)", flush=True)
    for a in agent_list:
        caps = len(a.get("capabilities", []))
        skills = len(a.get("skills", []))
        print(f"  {a['name']}: v{a.get('version', '?')} | {caps} caps, {skills} skills", flush=True)


if __name__ == "__main__":
    asyncio.run(check() if "--check" in sys.argv else run_forever())
