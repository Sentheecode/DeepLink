# Team + Center + Agent Handoff Spec

## Current Product Shape

This app now has five top-level tabs:

1. `Token` - balance / usage monitoring
2. `Agent` - Hermes-backed chat and future broker/channel support
3. `Center` - one tab with three interchangeable working modes: voice, photo, keyboard
4. `Team` - a standalone tab that can evolve into either multi-user collaboration or single-user multi-agent orchestration
5. `Settings` - credentials and connection settings

The current codebase already has:

- a working `CenterHubView`
- a working `TeamHubView`
- a persistent default `Center` mode
- long-press mode switching for `Center`
- a `Team` mode switch between multi-user and multi-agent
- a cleaned app shell that routes to the new hub views

## What Must Stay True

- `Center` must remain one tab, not three tabs.
- `Team` must remain a separate tab.
- The user should not need to install an extra companion mobile app.
- Keep the current `Token` and `LiveActivity` behavior intact.
- Keep the current Hermes chat path working while adding future agent/network abstractions.

## Center Requirements

### UX

- `Center` is a single tab.
- It contains three modes:
  - Voice
  - Photo
  - Keyboard
- The current default mode must be persisted.
- Long-pressing the mode switcher should open a picker that can change the default mode.

### Voice Mode

- Daily Q&A
- Agent project Q&A
- Memory Q&A

### Photo Mode

- Capture
- Recognition
- Optional location tag

### Keyboard Mode

- Memo input
- Long-press assignment to an agent

## Team Requirements

`Team` is a standalone tab with two product directions that should both remain supported:

1. Multi-user collaboration
2. Single-user multi-agent collaboration

The initial implementation should:

- show a mode selector
- show a scaffold for both directions
- make multi-agent mode the first practical path
- keep multi-user mode as a future-ready path

## Agent Requirements

The agent layer should stay channel-oriented.

It should keep the current Hermes compatibility layer and leave room for:

- device registry
- broker relay
- GitHub login identity
- optional Tailscale-backed node reachability

## Recommended Architecture Direction

### Center

Treat `Center` as a mode-driven workspace:

- one stable hub view
- one persisted mode state
- one switcher for default mode selection
- one content container per mode

### Team

Treat `Team` as an orchestration hub:

- mode selector at the top
- multi-user scaffold
- multi-agent board with task/role/handoff ideas
- later, room membership / permissions / presence / routing can be added without changing the tab shape

### Agent

Keep the agent layer abstracted behind a transport boundary so later work can choose:

- local Hermes
- LAN device
- broker relay
- future public endpoint

## Current Implementation Boundary

This is the current MVP boundary:

- `Center` UI is real and usable, but the deeper voice/photo/memo flows are still scaffolds
- `Team` UI is real and usable, but the multi-user and multi-agent systems are still scaffolds
- `Agent` still uses the current Hermes-compatible path
- networking/broker/device-graph logic should be added behind abstractions, not directly in views

## Next Steps For Claude Code

1. Keep the shell stable.
2. Flesh out `Center` mode behaviors without turning them into separate tabs.
3. Flesh out `Team` multi-agent behavior first.
4. Add abstractions for future agent transport and device reachability.
5. Keep the app install/configuration burden low.

## Important Constraints

- Do not reintroduce old shell-only placeholder pages.
- Do not split `Center` into separate tabs.
- Do not merge `Team` into `Center`.
- Do not require a cloud dependency for the current MVP.
- Do not break the existing token / widget / live activity flow.

## Suggested Handoff Summary

If you are continuing this in Claude Code, start from the current `CenterHubView` and `TeamHubView`, then implement the deeper behavior in this order:

1. Center voice / photo / keyboard real workflows
2. Team multi-agent board behavior
3. Agent transport abstraction
4. Future broker / GitHub / device registry hooks

