from __future__ import annotations

from typing import Any
from dataclasses import dataclass, field


# ── WSS Message Types ──

@dataclass
class WSSMessage:
    type: str
    data: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {"type": self.type, **self.data}


# ── Authentication ──

AUTHENTICATE = "authenticate"
AUTHENTICATED = "authenticated"
COMMAND = "command"
RESULT = "result"
PING = "ping"
PONG = "pong"
ERROR = "error"


def make_auth(device_id: str, token: str, agents: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "type": AUTHENTICATE,
        "device_id": device_id,
        "token": token,
        "agents": agents,
    }


def make_authenticated(device_id: str) -> dict[str, Any]:
    return {"type": AUTHENTICATED, "device_id": device_id}


def make_command(command_id: str, agent_id: str, method: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "type": COMMAND,
        "command_id": command_id,
        "agent_id": agent_id,
        "method": method,
        "params": params or {},
    }


def make_result(command_id: str, ok: bool, data: Any = None, error: str | None = None) -> dict[str, Any]:
    msg: dict[str, Any] = {"type": RESULT, "command_id": command_id, "ok": ok}
    if data is not None:
        msg["data"] = data
    if error is not None:
        msg["error"] = error
    return msg


def make_ping(timestamp: str) -> dict[str, Any]:
    return {"type": PING, "timestamp": timestamp}


def make_pong(timestamp: str) -> dict[str, Any]:
    return {"type": PONG, "timestamp": timestamp}
