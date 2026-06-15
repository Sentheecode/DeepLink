from __future__ import annotations

import asyncio
from typing import Any

import httpx


class ClaudeCodeAdapter:
    """Adapter for Claude Code agent.

    Connects to the local Claude Code Bridge HTTP server if available,
    falls back to direct CLI execution.
    """

    def __init__(self, device_id: str, cli_path: str = "/usr/local/bin/claude", bridge_url: str = "") -> None:
        self._id = f"{device_id}-claude-code"
        self._device_id = device_id
        self._cli_path = cli_path
        self._bridge_url = bridge_url.rstrip("/") if bridge_url else ""
        self._version: str | None = None
        self._available = False

    @property
    def id(self) -> str:
        return self._id

    @property
    def kind(self) -> str:
        return "claude-code"

    def describe(self) -> dict[str, Any]:
        return {
            "id": self._id,
            "name": "Claude Code",
            "kind": self.kind,
            "endpoint": self._bridge_url or None,
            "version": self._version,
            "status": "online" if self._available else "offline",
            "capabilities": ["chat"] if self._available else [],
            "skills": [],
        }

    async def discover(self) -> dict[str, Any]:
        info: dict[str, Any] = {
            "id": self._id,
            "name": "Claude Code",
            "kind": self.kind,
            "endpoint": self._bridge_url or None,
            "version": None,
            "status": "offline",
            "capabilities": [],
            "skills": [],
        }

        # Try bridge first
        if self._bridge_url:
            try:
                async with httpx.AsyncClient(timeout=3) as client:
                    resp = await client.get(f"{self._bridge_url}/health")
                    if resp.status_code == 200:
                        data = resp.json()
                        self._version = data.get("version", "?")
                        self._available = True
                        info["version"] = self._version
                        info["status"] = "online"
                        info["capabilities"] = ["chat"]
                        return info
            except Exception:
                pass

        # Fallback: check CLI directly
        try:
            proc = await asyncio.create_subprocess_exec(
                self._cli_path, "--version",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
            if proc.returncode == 0:
                self._version = stdout.decode().strip()
                self._available = True
                info["version"] = self._version
                info["status"] = "online"
                info["capabilities"] = ["chat"]
        except (FileNotFoundError, asyncio.TimeoutError, OSError):
            self._available = False

        return info

    async def health(self) -> bool:
        return self._available

    async def execute(self, method: str, params: dict[str, Any]) -> Any:
        if not self._available:
            raise RuntimeError("Claude Code is not available on this machine")

        if method == "chat":
            return await self._chat(params)

        raise ValueError(f"method '{method}' is not supported by claude-code adapter")

    async def _chat(self, params: dict[str, Any]) -> dict[str, Any]:
        message = params.get("message", "")
        if not message:
            raise ValueError("message is required")

        # Try bridge first
        if self._bridge_url:
            try:
                async with httpx.AsyncClient(timeout=300) as client:
                    resp = await client.post(f"{self._bridge_url}/chat", json={"message": message})
                    if resp.status_code == 200:
                        return resp.json()
            except Exception:
                pass

        # Fallback: direct CLI
        proc = await asyncio.create_subprocess_exec(
            self._cli_path, "-p", message,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        try:
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=300)
        except asyncio.TimeoutError:
            proc.kill()
            raise RuntimeError("Claude Code command timed out")

        if proc.returncode != 0:
            error_msg = stderr.decode().strip() if stderr else f"exit code {proc.returncode}"
            return {"events": [{"type": "text", "content": f"Error: {error_msg}"}]}

        content = stdout.decode().strip()
        return {"events": [{"type": "text", "content": content}]}
