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
from typing import Any

import httpx

from channel.protocol import (
    AUTHENTICATE, COMMAND, PING, PONG,
    make_auth, make_authenticated, make_command, make_ping, make_pong,
)
from channel.registry import create_default_registry, AgentRegistry

BROKER_URL = os.environ["BROKER_URL"].rstrip("/")
BROKER_TOKEN = os.environ["BROKER_TOKEN"]
DEVICE_ID = os.environ.get("DEVICE_ID", "hermes-main")
DEVICE_NAME = os.environ.get("DEVICE_NAME", DEVICE_ID)

WSS_URL = BROKER_URL.replace("https://", "wss://").replace("http://", "ws://") + "/v1/channel/connect"
MAX_CONCURRENT = 4
PING_INTERVAL = 20


def headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def register_agents_via_http(registry: AgentRegistry) -> None:
    """Fallback: register agents via HTTP POST during transition period."""
    async with httpx.AsyncClient(timeout=20) as client:
        for adapter in registry.all:
            info = await adapter.discover()
            resp = await client.post(
                f"{BROKER_URL}/v1/agents/register",
                headers=headers(BROKER_TOKEN),
                json={
                    "id": info["id"],
                    "name": info["name"],
                    "kind": info["kind"],
                    "endpoint": info["endpoint"],
                    "version": info["version"],
                    "status": info["status"],
                    "capabilities": info["capabilities"],
                    "skills": info["skills"],
                },
            )
            resp.raise_for_status()


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
    reconnect_delays = [1, 2, 4, 8, 15, 30]

    # First, register via HTTP (transition period)
    try:
        await register_agents_via_http(registry)
        agent_list = registry.list()
        print(f"registered {len(agent_list)} agent(s): {[a['name'] for a in agent_list]}", flush=True)
    except Exception as e:
        print(f"HTTP registration failed: {e}", flush=True)

    attempt = 0
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
                        await client.post(
                            f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/commands/{cmd['id']}/result",
                            headers=headers(BROKER_TOKEN),
                            json={"ok": result["ok"], "data": result.get("data"), "error": result.get("error")},
                        )

                asyncio.create_task(exec_with_sem(command))
                attempt = 0

        except httpx.HTTPStatusError as e:
            if e.response.status_code == 404:
                print("device not registered, re-registering...", flush=True)
                await register_agents_via_http(registry)
            else:
                print(f"HTTP error: {e}", flush=True)
            attempt += 1
            await asyncio.sleep(3)
        except Exception as e:
            print(f"channel error: {e}", flush=True)
            attempt += 1
            await asyncio.sleep(3)


async def check() -> None:
    """Health check: discover and register agents, verify connectivity."""
    registry = create_default_registry()
    await register_agents_via_http(registry)
    agent_list = registry.list()
    print(f"channel check passed: {DEVICE_NAME} ({DEVICE_ID}) | {len(agent_list)} agent(s)", flush=True)
    for a in agent_list:
        caps = len(a.get("capabilities", []))
        skills = len(a.get("skills", []))
        print(f"  {a['name']}: v{a.get('version', '?')} | {caps} caps, {skills} skills", flush=True)


if __name__ == "__main__":
    asyncio.run(check() if "--check" in sys.argv else run_forever())
