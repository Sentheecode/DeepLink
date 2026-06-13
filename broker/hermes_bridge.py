"""
DeepLink Channel Bridge
- Registers device + agents to broker
- Auto-discovers Hermes agent capabilities
- Routes RPC commands to the correct agent
"""
import asyncio
import json
import os
import sys
from typing import Any

import httpx


BROKER_URL = os.environ["BROKER_URL"].rstrip("/")
BROKER_TOKEN = os.environ["BROKER_TOKEN"]
DEVICE_ID = os.environ.get("DEVICE_ID", "hermes-main")
DEVICE_NAME = os.environ.get("DEVICE_NAME", DEVICE_ID)
HERMES_URL = os.environ.get("HERMES_URL", "http://127.0.0.1:8642").rstrip("/")
HERMES_KEY = os.environ.get("HERMES_KEY", "")

AGENT_ID = f"{DEVICE_ID}-hermes"


def headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


async def hermes_request(method: str, path: str, body: dict[str, Any] | None = None) -> Any:
    request_headers = headers(HERMES_KEY) if HERMES_KEY else {}
    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.request(method, f"{HERMES_URL}{path}", headers=request_headers, json=body)
        response.raise_for_status()
        if not response.content:
            return {"ok": True}
        return response.json()


async def discover_agent() -> dict[str, Any]:
    """Fetch Hermes agent metadata from health/capabilities endpoints."""
    info: dict[str, Any] = {
        "id": AGENT_ID,
        "name": "Hermes",
        "kind": "hermes",
        "endpoint": HERMES_URL,
        "version": None,
        "status": "online",
        "capabilities": [],
        "skills": [],
    }
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            resp = await client.get(f"{HERMES_URL}/health", headers=headers(HERMES_KEY) if HERMES_KEY else {})
            if resp.status_code == 200:
                data = resp.json()
                if isinstance(data, dict):
                    info["version"] = data.get("version")
    except Exception:
        info["status"] = "offline"

    try:
        caps = await hermes_request("GET", "/v1/capabilities")
        if isinstance(caps, list):
            info["capabilities"] = caps
        elif isinstance(caps, dict):
            info["capabilities"] = caps.get("capabilities", [])
    except Exception:
        pass

    try:
        skills = await hermes_request("GET", "/v1/skills")
        if isinstance(skills, dict):
            skill_list = skills.get("skills", skills.get("data", []))
            if isinstance(skill_list, list):
                info["skills"] = [{"name": s.get("name", ""), "description": s.get("description", "")} for s in skill_list if isinstance(s, dict)]
    except Exception:
        pass

    return info


async def register_node(client: httpx.AsyncClient) -> None:
    response = await client.post(
        f"{BROKER_URL}/v1/nodes/register",
        headers=headers(BROKER_TOKEN),
        json={"device_id": DEVICE_ID, "name": DEVICE_NAME, "endpoint": HERMES_URL, "capabilities": ["hermes"]},
    )
    response.raise_for_status()


async def register_agents(client: httpx.AsyncClient, agent_info: dict[str, Any]) -> None:
    response = await client.post(
        f"{BROKER_URL}/v1/agents/register",
        headers=headers(BROKER_TOKEN),
        json={
            "id": agent_info["id"],
            "name": agent_info["name"],
            "kind": agent_info["kind"],
            "endpoint": agent_info["endpoint"],
            "version": agent_info["version"],
            "status": agent_info["status"],
            "capabilities": agent_info["capabilities"],
            "skills": agent_info["skills"],
        },
    )
    response.raise_for_status()


async def execute(command: dict[str, Any]) -> Any:
    method = command["method"]
    params = command.get("params", {})

    if method == "list_sessions":
        return await hermes_request("GET", "/api/sessions")
    if method == "create_session":
        body = {"title": params["title"]} if params.get("title") else None
        return await hermes_request("POST", "/api/sessions", body)
    if method == "delete_session":
        return await hermes_request("DELETE", f"/api/sessions/{params['session_id']}")
    if method == "list_messages":
        path = f"/api/sessions/{params['session_id']}/messages?limit={params.get('limit', 50)}"
        if params.get("before"):
            path += f"&before={params['before']}"
        return await hermes_request("GET", path)
    if method == "chat":
        path = f"/api/sessions/{params['session_id']}/chat/stream"
        request_headers = headers(HERMES_KEY) if HERMES_KEY else {}
        async with httpx.AsyncClient(timeout=180) as client:
            response = await client.post(
                f"{HERMES_URL}{path}",
                headers=request_headers,
                json={"message": params["message"]},
            )
            response.raise_for_status()
            raw = response.text
            events = []
            for line in raw.splitlines():
                if line.startswith("data: "):
                    try:
                        events.append(json.loads(line[6:]))
                    except json.JSONDecodeError:
                        continue
            if not events:
                try:
                    payload = response.json()
                    content = payload.get("content") or payload.get("reply") or raw
                except json.JSONDecodeError:
                    content = raw
                events = [{"type": "text", "content": content}]
            return {"events": events}
    raise ValueError(f"unsupported method: {method}")


async def run_forever() -> None:
    registered = False
    agent_info: dict[str, Any] | None = None
    async with httpx.AsyncClient(timeout=40) as client:
        while True:
            try:
                if not registered:
                    await register_node(client)
                    agent_info = await discover_agent()
                    await register_agents(client, agent_info)
                    registered = True
                    status = agent_info.get("status", "online")
                    caps_count = len(agent_info.get("capabilities", []))
                    skills_count = len(agent_info.get("skills", []))
                    print(f"channel registered: {DEVICE_NAME} ({DEVICE_ID}) | Hermes {agent_info.get('version', '?')} | {caps_count} caps, {skills_count} skills", flush=True)

                response = await client.get(
                    f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/commands/next",
                    headers=headers(BROKER_TOKEN),
                    params={"timeout": 25},
                )
                if response.status_code == 204:
                    continue
                response.raise_for_status()
                command = response.json()
                try:
                    data = await execute(command)
                    result = {"ok": True, "data": data}
                except Exception as exc:
                    result = {"ok": False, "error": str(exc)}
                result_response = await client.post(
                    f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/commands/{command['id']}/result",
                    headers=headers(BROKER_TOKEN),
                    json=result,
                )
                result_response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                if exc.response.status_code == 404:
                    registered = False
                print(f"bridge HTTP error: {exc.response.status_code} {exc.response.text}", flush=True)
                await asyncio.sleep(3)
            except Exception as exc:
                print(f"bridge error: {exc}", flush=True)
                await asyncio.sleep(3)


async def check() -> None:
    async with httpx.AsyncClient(timeout=20) as client:
        await register_node(client)
        info = await discover_agent()
        await register_agents(client, info)
    caps = len(info.get("capabilities", []))
    skills = len(info.get("skills", []))
    print(f"channel check passed: {DEVICE_NAME} ({DEVICE_ID}) | Hermes {info.get('version', '?')} | {caps} caps, {skills} skills", flush=True)


if __name__ == "__main__":
    asyncio.run(check() if "--check" in sys.argv else run_forever())
