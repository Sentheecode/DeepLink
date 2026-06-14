from __future__ import annotations

import json
from typing import Any

import httpx


class HermesAdapter:
    """Adapter for Hermes API agent."""

    def __init__(self, device_id: str, url: str, api_key: str = "") -> None:
        self._id = f"{device_id}-hermes"
        self._device_id = device_id
        self._url = url
        self._api_key = api_key
        self._version: str | None = None
        self._capabilities: list[str] = []
        self._skills: list[dict[str, str]] = []

    @property
    def id(self) -> str:
        return self._id

    @property
    def kind(self) -> str:
        return "hermes"

    def describe(self) -> dict[str, Any]:
        return {
            "id": self._id,
            "name": "Hermes",
            "kind": self.kind,
            "endpoint": self._url,
            "version": self._version,
            "status": "online" if self._version else "offline",
            "capabilities": self._capabilities,
            "skills": self._skills,
        }

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self._api_key}"} if self._api_key else {}

    async def _request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        headers = self._headers()
        async with httpx.AsyncClient(timeout=180) as client:
            resp = await client.request(method, f"{self._url}{path}", headers=headers, json=body)
            resp.raise_for_status()
            if not resp.content:
                return {"ok": True}
            return resp.json()

    async def health(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self._url}/health", headers=self._headers())
                return resp.status_code == 200
        except Exception:
            return False

    async def discover(self) -> dict[str, Any]:
        info: dict[str, Any] = {
            "id": self._id,
            "name": "Hermes",
            "kind": self.kind,
            "endpoint": self._url,
            "version": None,
            "status": "offline",
            "capabilities": [],
            "skills": [],
        }
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                resp = await client.get(f"{self._url}/health", headers=self._headers())
                if resp.status_code == 200:
                    data = resp.json()
                    info["version"] = data.get("version") if isinstance(data, dict) else None
                    info["status"] = "online"
                    self._version = info["version"]
        except Exception:
            return info

        try:
            caps = await self._request("GET", "/v1/capabilities")
            if isinstance(caps, list):
                info["capabilities"] = caps
            elif isinstance(caps, dict):
                features = caps.get("features", {})
                if isinstance(features, dict):
                    info["capabilities"] = sorted(k for k, enabled in features.items() if enabled is True)
            self._capabilities = info["capabilities"]
        except Exception:
            pass

        try:
            skills = await self._request("GET", "/v1/skills")
            if isinstance(skills, dict):
                raw = skills.get("skills", skills.get("data", []))
                if isinstance(raw, list):
                    info["skills"] = [{"name": s.get("name", ""), "description": s.get("description", "")} for s in raw if isinstance(s, dict)]
            self._skills = info["skills"]
        except Exception:
            pass

        return info

    async def execute(self, method: str, params: dict[str, Any]) -> Any:
        if method == "list_sessions":
            return await self._request("GET", "/api/sessions")
        if method == "create_session":
            body = {"title": params["title"]} if params.get("title") else None
            return await self._request("POST", "/api/sessions", body)
        if method == "delete_session":
            return await self._request("DELETE", f"/api/sessions/{params['session_id']}")
        if method == "list_messages":
            path = f"/api/sessions/{params['session_id']}/messages?limit={params.get('limit', 50)}"
            if params.get("before"):
                path += f"&before={params['before']}"
            return await self._request("GET", path)
        if method == "chat":
            return await self._chat(params)
        raise ValueError(f"method '{method}' is not supported by hermes adapter")

    async def _chat(self, params: dict[str, Any]) -> dict[str, Any]:
        path = f"/api/sessions/{params['session_id']}/chat/stream"
        headers = self._headers()
        async with httpx.AsyncClient(timeout=180) as client:
            resp = await client.post(
                f"{self._url}{path}",
                headers=headers,
                json={"message": params["message"]},
            )
            resp.raise_for_status()
            raw = resp.text
            events = []
            for line in raw.splitlines():
                if line.startswith("data: "):
                    try:
                        events.append(json.loads(line[6:]))
                    except json.JSONDecodeError:
                        continue
            if not events:
                try:
                    payload = resp.json()
                    content = payload.get("content") or payload.get("reply") or raw
                except json.JSONDecodeError:
                    content = raw
                events = [{"type": "text", "content": content}]
            return {"events": events}
