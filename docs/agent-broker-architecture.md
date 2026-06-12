# Agent Broker Architecture

## Goal

Build a broker-oriented agent layer where the iPhone app, local Hermes node, and future network backends all communicate through a shared channel abstraction.

## Principles

- Keep the iPhone app simple: login, device selection, session list, chat UI.
- Keep Hermes on the computer as a worker/node that can connect outward.
- Make network transport swappable: local direct, Tailscale-assisted, or broker relay.
- Avoid requiring end users to install extra companion apps beyond the primary iPhone app and Hermes node.

## Layers

### Identity

- GitHub login authenticates the user in the product.
- The product backend maps a user to allowed devices and sessions.

### Device Discovery

- A device registry returns nodes available to the user.
- Devices are identified by `AgentDevice`.
- A selected device is persisted locally so the app can restore it on launch.

### Transport

- `AgentChannel` represents one logical agent connection.
- `AgentBrokerClient` represents a transport that can route sessions and messages through a broker.
- `HermesChannel` remains the first transport adapter for the existing app.

### Runtime Flow

1. App loads the saved channel and device selection.
2. App fetches available devices from the registry or broker.
3. User selects a device if needed.
4. App lists sessions from the selected channel.
5. App streams chat messages from the selected channel.

## Immediate Scope

- Add the broker/device abstraction.
- Keep the current Hermes-based behavior working.
- Do not build the full cloud broker yet.
- Do not add Tailscale UI to the iPhone app yet.

## Next Implementation Steps for Claude Code

1. Move `HermesChannel` behind a transport protocol boundary.
2. Add a device picker model to `AgentStore`.
3. Persist the selected device identifier.
4. Replace the fixed `localhost` assumption with selected device metadata.
5. Add a placeholder broker client for future remote routing.

