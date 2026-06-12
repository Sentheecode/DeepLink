# Team + Center + Agent Hub Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the app shell so the `Team` tab and `Center` tab become a cohesive product hub, with `Center` supporting voice/photo/memo modes, persistent default mode switching, and a future-ready agent layer for both single-user multi-agent and multi-user collaboration.

**Architecture:** Keep `Team` as a standalone tab and treat `Center` as a mode-driven workspace. The `Center` tab should own the three operational modes (`voice`, `photo`, `memo`) with a clearer switcher and a persisted default mode. The agent layer should stay abstracted behind channel/device/broker boundaries so the UI can later support multiple agent runtimes without rewriting the shell.

**Tech Stack:** SwiftUI, Observation (`@Observable`), `AppStorage`, existing `HermesAPI` / agent channel layer, local persistence with `UserDefaults` / Keychain, optional future WebSocket or broker transport.

---

### Task 1: Reframe the app shell around Team and Center

**Files:**
- Modify: `DeepSeekBalance/AppShell.swift`
- Modify: `DeepSeekBalance/Features/Agent/AgentModule.swift`

- [ ] **Step 1: Add a shell-level routing model**

```swift
enum AppSection: Int, CaseIterable {
    case token = 0
    case agent = 1
    case center = 2
    case team = 3
    case settings = 4
}
```

- [ ] **Step 2: Replace any ad hoc center-state handling with a stable persisted default**

```swift
@AppStorage("centerTabMode") private var centerTabMode: CenterTabMode = .voice
@AppStorage("centerTabModeDefault") private var centerTabModeDefaultRawValue: String = CenterTabMode.voice.rawValue
```

- [ ] **Step 3: Keep `TeamTab` as a dedicated tab and ensure `Center` remains a separate tab**

```swift
TabView(selection: $selectedTab) {
    TokenTab().tag(AppSection.token.rawValue)
    AgentTab().tag(AppSection.agent.rawValue)
    CenterPage(mode: centerTabMode).tag(AppSection.center.rawValue)
    TeamTab().tag(AppSection.team.rawValue)
    SettingsTab().tag(AppSection.settings.rawValue)
}
```

- [ ] **Step 4: Preserve current balance, widget, and live activity behavior**

```swift
// Do not change TokenTab refresh, WidgetKit reloads, or LiveActivityManager behavior in this task.
```

- [ ] **Step 5: Run validation**

Run:

```bash
./scripts/validate_project.sh
xcodebuild -project DeepSeekBalance.xcodeproj -scheme DeepSeekBalance -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Expected: `Project validation passed.` and `** BUILD SUCCEEDED **`

### Task 2: Redesign Center mode switching UX

**Files:**
- Modify: `DeepSeekBalance/AppShell.swift`
- Create: `DeepSeekBalance/Features/Center/CenterHubView.swift`
- Create: `DeepSeekBalance/Features/Center/CenterModeSwitcher.swift`
- Create: `DeepSeekBalance/Features/Center/CenterModeContentView.swift`

- [ ] **Step 1: Add a visual mode switcher with three modes**

```swift
enum CenterTabMode: String, CaseIterable {
    case voice = "voice"
    case camera = "camera"
    case keyboard = "keyboard"
}
```

- [ ] **Step 2: Build the main Center hub around a stable content container**

```swift
struct CenterHubView: View {
    @AppStorage("centerTabMode") private var centerTabMode: CenterTabMode = .voice
    @AppStorage("centerTabModeDefault") private var defaultModeRawValue: String = CenterTabMode.voice.rawValue

    var body: some View {
        VStack(spacing: 16) {
            CenterModeSwitcher(currentMode: $centerTabMode, defaultModeRawValue: $defaultModeRawValue)
            CenterModeContentView(mode: centerTabMode)
        }
    }
}
```

- [ ] **Step 3: Make long-press change the default mode**

```swift
// Long-press current mode -> present mode picker -> tap selection -> save as new default mode.
```

- [ ] **Step 4: Keep the visual language consistent across modes**

```swift
// Voice: waveform / listening state / response stream.
// Camera: capture / recognition / location toggle.
// Keyboard: note-taking / assign-to-agent affordance.
```

- [ ] **Step 5: Run validation**

Run:

```bash
./scripts/validate_project.sh
xcodebuild -project DeepSeekBalance.xcodeproj -scheme DeepSeekBalance -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Expected: build succeeds and the Center tab still opens.

### Task 3: Define Center mode behaviors

**Files:**
- Create: `DeepSeekBalance/Features/Center/VoiceModeView.swift`
- Create: `DeepSeekBalance/Features/Center/PhotoModeView.swift`
- Create: `DeepSeekBalance/Features/Center/MemoModeView.swift`

- [ ] **Step 1: Voice mode should support three sub-flows**

```swift
enum VoiceModeDestination: String, CaseIterable {
    case dailyQna
    case agentQna
    case memoryQna
}
```

- [ ] **Step 2: Photo mode should support capture plus optional location**

```swift
struct PhotoModeState {
    var includeLocation: Bool
    var capturedImageID: String?
}
```

- [ ] **Step 3: Keyboard mode should be memo-first with agent assignment**

```swift
struct MemoDraft {
    var text: String
    var assignedAgentID: String?
}
```

- [ ] **Step 4: Add the assignment hook for long-press selection**

```swift
// Long-press a memo item -> show agent picker -> assign to selected agent.
```

- [ ] **Step 5: Keep agent assignment disabled until the agent layer is ready**

```swift
// Render a disabled "Assign to agent" action when no agent registry data is available.
```

### Task 4: Expand Team into a dual-mode workspace

**Files:**
- Modify: `DeepSeekBalance/Features/Agent/AgentModule.swift`
- Create: `DeepSeekBalance/Features/Team/TeamHubView.swift`
- Create: `DeepSeekBalance/Features/Team/TeamModeSelector.swift`
- Create: `DeepSeekBalance/Features/Team/TeamModels.swift`

- [ ] **Step 1: Define the two Team modes explicitly**

```swift
enum TeamMode: String, Codable, CaseIterable {
    case multiUser
    case multiAgent
}
```

- [ ] **Step 2: Add a team hub that can switch modes without changing the tab entry**

```swift
struct TeamHubView: View {
    @AppStorage("teamMode") private var teamModeRawValue: String = TeamMode.multiAgent.rawValue
    var body: some View { TeamModeSelector(...) }
}
```

- [ ] **Step 3: Keep multi-user mode as a future-ready placeholder**

```swift
// Multi-user mode should show a room / members / permissions scaffold but no full social backend yet.
```

- [ ] **Step 4: Make multi-agent mode the first functional path**

```swift
// Multi-agent mode should show agents, responsibilities, and handoff-ready task cards.
```

- [ ] **Step 5: Reuse existing agent channels for agent-to-agent messaging**

```swift
// Multi-agent team uses the same underlying channel abstraction as the agent module.
```

### Task 5: Add the future agent bridge document and hooks

**Files:**
- Modify: `docs/agent-broker-architecture.md`
- Modify: `docs/agent-module-task3-for-claude.md`
- Create: `docs/team-center-hub-spec.md`

- [ ] **Step 1: Merge the Team and Center requirements into one readable spec**

```markdown
The spec must explain:
- Team tab is independent
- Center is mode-based
- Voice/Photo/Memo are one tab with a default mode
- Agent layer must support future multi-agent and multi-user use cases
```

- [ ] **Step 2: Document the current implementation boundary**

```markdown
Current MVP:
- local Hermes channel still works
- Center modes are UI scaffolds
- Team tab is scaffolded for both modes
- broker/networking is abstracted but not fully implemented
```

- [ ] **Step 3: Document the future bridge**

```markdown
Future bridge:
- GitHub login
- device registry
- broker relay
- optional Tailscale-backed node reachability
```

### Task 6: Validation and review

**Files:**
- None

- [ ] **Step 1: Run the project validation script**

Run:

```bash
./scripts/validate_project.sh
```

Expected: `Project validation passed.`

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild -project DeepSeekBalance.xcodeproj -scheme DeepSeekBalance -configuration Debug -destination 'generic/platform=iOS Simulator' build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Review for scope drift**

```markdown
Do not merge in full broker networking, OAuth, or Tailscale UI yet.
Keep the center/team work focused on shell, mode switch UX, and scaffolding.
```

