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


async def register(client: httpx.AsyncClient) -> None:
    response = await client.post(
        f"{BROKER_URL}/v1/nodes/register",
        headers=headers(BROKER_TOKEN),
        json={"device_id": DEVICE_ID, "name": DEVICE_NAME, "endpoint": HERMES_URL, "capabilities": ["hermes"]},
    )
    response.raise_for_status()


async def heartbeat(client: httpx.AsyncClient) -> None:
    response = await client.post(
        f"{BROKER_URL}/v1/nodes/{DEVICE_ID}/heartbeat",
        headers=headers(BROKER_TOKEN),
    )
    response.raise_for_status()


async def check() -> None:
    async with httpx.AsyncClient(timeout=20) as client:
        await register(client)
        await heartbeat(client)
    print(f"channel check passed: {DEVICE_NAME} ({DEVICE_ID})", flush=True)


async def run() -> None:
    registered = False
    async with httpx.AsyncClient(timeout=40) as client:
        while True:
            try:
                if not registered:
                    await register(client)
                    registered = True
                    print(f"channel registered: {DEVICE_NAME} ({DEVICE_ID})", flush=True)
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
                print(
                    f"bridge HTTP error: {exc.response.status_code} {exc.response.text}",
                    flush=True,
                )
                await asyncio.sleep(3)
            except Exception as exc:
                print(f"bridge error: {exc}", flush=True)
                await asyncio.sleep(3)


if __name__ == "__main__":
    asyncio.run(check() if "--check" in sys.argv else run())
