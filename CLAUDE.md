# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Deploy

```bash
# Generate Xcode project from YAML (always run after editing project.yml or adding files)
xcodegen generate

# Build + install to connected device
./build_and_install.sh

# Build main app
xcodebuild -project DeepLink.xcodeproj -scheme DeepSeekBalance -destination 'generic/platform=iOS' build

# Run tests
xcodebuild -project DeepLink.xcodeproj -scheme DeepSeekBalance -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test

# Validate project structure
./scripts/validate_project.sh

# Device pairing / install / launch
xcrun devicectl list devices
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"
xcrun devicectl device process launch --device "$DEVICE_ID" com.deepseek.balance
```

## Project Generation (XcodeGen)

The Xcode project is **generated** from `project.yml` — never edit `project.pbxproj` directly.

```bash
xcodegen generate   # after modifying project.yml or adding files
```

Key settings in `project.yml`:
- **DeepSeekBalance** — app target, includes `*.swift` from root + `Features/**/*.swift`
- **DeepSeekBalanceWidgetExtension** — widget + Live Activity
- **DeepSeekBalanceTests** — 9 tests (Keychain + Repository)
- sign team `534H8W5WL8`, App Group `group.com.deepseek.balance`

## Architecture

### Navigation Shell (AppShell.swift)

```
ZStack(content + custom tab bar)
├─ Content (switch selectedTab)
│  ├─ TokenTab      — DeepSeek 余额 + 用量（通过 DashboardStore）
│  ├─ AgentTab      — Hermes Agent 会话列表
│  ├─ CenterTab     — 占位
│  ├─ TeamTab       — 占位
│  └─ SettingsTab   — DeepSeek Token + Hermes 配置
└─ Custom Tab Bar (5 buttons, glassmorphism, raised center button with pulse animation)
```

`.safeAreaInset(edge: .bottom, 70pt)` on content keeps it above the custom tab bar.

### Layers

```
Token Module
  ├─ DeepSeekAPI.swift            — HTTP client for platform.deepseek.com/api/v0/
  ├─ DeepSeekProvider.swift        — Actor: fetchSummary/fetchBalance/fetchUsage with token mgmt
  ├─ UsageRepository.swift         — Refresh pipeline: fetch → cache → Widget → LiveActivity
  ├─ DashboardStore.swift          — @Observable state manager (isLoading, snapshot, error)
  ├─ TokenTab (in AppShell)        — Balance card + usage details + model switcher
  └─ PrintReceiptViews.swift       — Print bill animation overlay

Agent Module
  ├─ HermesAPI.swift               — Actor: HTTP + SSE client for Hermes API Server (port 8642)
  ├─ AgentTab (in AppShell)        — Session list + create/delete
  ├─ AgentConversationView         — Message list + SSE streaming chat input
  └─ AgentStore (in AppShell)      — Session list management

Shared Infrastructure
  ├─ CredentialStore.swift          — Keychain-based token storage (DeepSeek + Hermes)
  ├─ Models.swift                   — Codable models
  ├─ DashboardSnapshot.swift        — Provider-agnostic snapshots
  ├─ UserDefaults+Shared.swift      — App Group cache (WidgetData, usage cache)
  ├─ TokenWebView.swift             — WKWebView login (domain-restricted)
  └─ LiveActivityManager.swift      — ActivityKit management with generation counter

Widget Extension
  ├─ DeepSeekBalanceWidget.swift    — 4 widget sizes
  ├─ MonitorLiveActivity.swift      — Live Activity + Dynamic Island
  └─ Info.plist                      — Manual plist with NSExtension
```

### Data Flows

**Token refresh (uses DashboardStore pipeline):**
```
TokenTab.refresh()
  → DashboardStore.refresh(month:year:)
    → UsageRepository.refresh()
      → DeepSeekProvider.fetchSummary()  # single API call → BalanceSnapshot + UserSummary
      → DeepSeekProvider.fetchUsage()     # amount + cost (optional)
    → commit()  # WidgetData cache + LiveActivity sync (if not cancelled)
  → returns UserSummary? for views
```

**Agent chat (SSE streaming):**
```
AgentConversationView.sendMessage()
  → HermesAPI.chatStream(sessionId, message)
  → AsyncThrowingStream<HermesStreamEvent>
  → SSE events: thinking → tool_call → tool_result → text → done
  → appended to messages array in real-time
```

### Key Design Decisions

- **Manual JSON parsing for HermesAPI** — uses `JSONSerialization` instead of Codable to handle varying API response formats (both `data`/`sessions` arrays, `id`/`session_id` fields)
- **Cache to UserDefaults** — `WidgetData`, `UsageAmountData`, `UsageCostEntry` cached for instant display on tab switch
- **Generation counter** — `LiveActivityManager.generation` prevents race conditions between sync/end
- **RefreshResult pattern** — Repository returns pure data; Store commits side effects after confirming task not cancelled
- **Domain-restricted login** — TokenWebView only reads `userToken` from `platform.deepseek.com` or subdomains

### Auth

| Service | Token | Storage |
|---------|-------|---------|
| DeepSeek | `userToken` from web cookies | Keychain (`KeychainCredentialStore`) |
| Hermes | Bearer token (`API_SERVER_KEY`) | Keychain (via `.hermesKey` ProviderID) |

Legacy UserDefaults token auto-migrated to Keychain on first launch.

### Hermes Agent

Connects to Hermes API Server running on a local Mac (LAN):
- **Default address**: `http://localhost:8642` (change to Mac's LAN IP on device)
- **URL validation**: `validateURL()` checks format before connecting
- **Auth**: Bearer token (optional — empty key skips auth header)
- **Chat**: SSE streaming for real-time agent responses (thinking, tool calls, results)
- **Endpoints**: sessions CRUD, messages history, streaming chat
- **Response format**: `{"object":"list","data":[{"id":"...","title":"...",...}]}`

## Adding New Files

1. Create the file in the filesystem
2. If under `DeepLink/Features/`, `project.yml` auto-includes via `**/*.swift` glob
3. Otherwise, update `project.yml` sources list
4. Run `xcodegen generate`
5. Never edit `project.pbxproj` manually

## Known Issues

- pbxproj is **always regenerated** by XcodeGen — manual edits will be lost
- Chat input bar layout: uses `.safeAreaInset(edge: .bottom)` on ScrollView to pin input bar above custom tab bar
- SourceKit errors in editor are usually false positives (cross-file type resolution in different modules)
- Hermes Key stored in Keychain via `KeychainCredentialStore` with `.hermesKey` ProviderID
