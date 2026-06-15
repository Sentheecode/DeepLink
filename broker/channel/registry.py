from __future__ import annotations

import os
from typing import Any

from channel.adapters.base import AgentAdapter, AgentNotFoundError
from channel.adapters.hermes import HermesAdapter
from channel.adapters.claude_code import ClaudeCodeAdapter


class AgentRegistry:
    """Manages all local Agent adapters."""

    def __init__(self) -> None:
        self._adapters: dict[str, AgentAdapter] = {}

    def register(self, adapter: AgentAdapter) -> None:
        self._adapters[adapter.id] = adapter

    def get(self, agent_id: str) -> AgentAdapter:
        adapter = self._adapters.get(agent_id)
        if adapter is None:
            raise AgentNotFoundError(agent_id)
        return adapter

    def list(self) -> list[dict[str, Any]]:
        return [a.describe() for a in self._adapters.values()]

    @property
    def all(self) -> list[AgentAdapter]:
        return list(self._adapters.values())


def create_default_registry() -> AgentRegistry:
    """Create registry from environment variables."""
    registry = AgentRegistry()
    enabled = os.environ.get("ENABLED_AGENTS", "hermes").replace(" ", "").split(",")

    if "hermes" in enabled:
        hermes_url = os.environ.get("HERMES_URL", "http://127.0.0.1:8642").rstrip("/")
        hermes_key = os.environ.get("HERMES_KEY", "")
        device_id = os.environ.get("DEVICE_ID", "hermes-main")
        registry.register(HermesAdapter(device_id, hermes_url, hermes_key))

    if "claude-code" in enabled:
        claude_path = os.environ.get("CLAUDE_CODE_PATH", "/usr/local/bin/claude")
        claude_bridge = os.environ.get("CLAUDE_CODE_BRIDGE_URL", "http://127.0.0.1:8643")
        device_id = os.environ.get("DEVICE_ID", "hermes-main")
        registry.register(ClaudeCodeAdapter(device_id, claude_path, claude_bridge))

    return registry
