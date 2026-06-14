from typing import Any, Protocol


class AgentAdapter(Protocol):
    """Interface for all Agent adapters."""

    @property
    def id(self) -> str: ...

    @property
    def kind(self) -> str: ...

    def describe(self) -> dict[str, Any]:
        """Return agent metadata for registration."""
        ...

    async def discover(self) -> dict[str, Any]:
        """Fetch agent capabilities, skills, version from the local service."""
        ...

    async def execute(self, method: str, params: dict[str, Any]) -> Any:
        """Execute an RPC method on this agent."""
        ...

    async def health(self) -> bool:
        """Check if the agent is reachable."""
        ...


class AgentNotFoundError(KeyError):
    def __init__(self, agent_id: str) -> None:
        super().__init__(f"agent not found: {agent_id}")
