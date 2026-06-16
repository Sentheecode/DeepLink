# DeepLink

An iPhone-native control surface for API usage, agent channels, device orchestration, and lightweight human-in-the-loop workflows.

Language: [中文](#中文) | [English](#english)

---

## 中文

### 简介

DeepLink 最初来自一个很具体的痛点：我只是想随时知道 DeepSeek API 还剩多少额度，不想每次打开浏览器、登录后台、再去找余额和用量数据。第一版因此把 DeepSeek 余额、月度用量、桌面组件、锁屏组件和灵动岛状态放到了 iPhone 上。

后来问题变得更大：我有多台设备，也有多个 Agent。它们可能运行在不同电脑上，暴露不同端口，用不同网络连接。每次绑定、切换、查看状态、打开会话都很麻烦。DeepLink 因此开始演进为一个移动端 Agent 控制面：通过自己的 Channel 和 Broker，把设备、Agent、会话和日常任务统一管理起来。

DeepLink 不是单纯的余额查询 App。余额监控是入口，真正的方向是把个人 AI 基础设施变成一个可以随身控制、随时指派、持续协作的系统。

### 核心定位

- **API 用量监控**：DeepSeek 余额、月度用量、成本、桌面组件、锁屏组件、Live Activity 和灵动岛。
- **Agent 控制台**：连接本地或云端 Agent，查看设备状态、Agent 档案、会话列表和聊天记录。
- **个人工作流入口**：用语音、拍照、备忘录捕捉任务，并把任务指派给 Agent 或简单工作流。

### 为什么做这个

- API 余额在单独的平台后台里。
- Agent 跑在不同电脑、不同端口、不同运行时上。
- 局域网能连，离开家后就不稳定。
- 每次配对设备都要复制地址、端口、Key 或脚本。
- 临时想到的任务要先记下来，再手动发给某个 Agent。
- 多个 Agent 之间还没有清晰的协作与交接方式。

DeepLink 想把这些分散入口收束到一个手机体验里：资源状态、设备状态、Agent 会话、快速捕捉、任务指派和工作流编排。

### 功能概览

#### DeepSeek 用量监控

- 通过受限域名的 Web 登录流程获取 DeepSeek Token。
- Token 存入 iOS Keychain，不落明文文件。
- 展示余额、用户摘要、月度用量和模型成本。
- 缓存最后一次成功刷新结果，减少冷启动空白。
- 支持桌面组件、锁屏组件、Live Activity 与灵动岛同步。
- 支持账单打印风格的用量展示动效。

#### 组件与系统级入口

DeepLink 的第一入口不只是 App 本身，而是 iOS 系统表面。桌面组件、锁屏组件、Live Activity 和灵动岛解决的是最早的核心痛点：不打开 App，也能知道额度状态。

#### Agent Channel

DeepLink 支持两类连接模式：

- **Local Mode**：在局域网内直连 Hermes 兼容 API Server。
- **Broker Mode**：手机和电脑端 Channel 都连接到云端 Broker，由 Broker 做中继和路由。

Channel 层被设计成可替换结构，当前支持 Hermes，后续可以继续接入 Claude Code、Codex、OpenClaw 或其他自定义 Agent。

#### Agent 工作台

- 查看在线设备和 Agent。
- 按设备区分 Agent 来源。
- 查看 Agent 类型、版本、能力和 Skills。
- 打开会话列表和会话详情。
- 支持 ChatGPT 风格的对话布局。
- 支持本地 LAN 与云端 Broker 两种上下文。
- 为项目、资源、知识库和插件预留独立入口。

#### Center：快速捕捉与指派

中间按钮是高频入口，强调“单击即进入模式”：

- **语音**：录音、识别、保存，可回放。
- **拍照**：拍摄、OCR、保存照片与识别文本。
- **键盘**：快速写备忘录。

Center 的历史记录会把语音、图片和文字按时间倒序合并展示，并支持语音回放、照片详情、OCR 文本和备忘录指派。

#### Team 与工作流

Team 模块面向两个方向：

- **个人多 Agent 团队**：一个用户，多台设备，多个 Agent。
- **多人协作团队**：多个用户共享设备、Agent 和任务。

当前工作流能力还是轻量版本：拖拽排序、运行/停止、设备感知的 Agent 标签，以及一个模拟的数据采集、数据审计、数据分析流程。

### 架构概览

```text
DeepLink iOS App
├─ Token Module
│  ├─ DeepSeekAPI
│  ├─ DeepSeekProvider
│  ├─ UsageRepository
│  ├─ DashboardStore
│  └─ TokenTab
│
├─ Agent Module
│  ├─ AgentChannel protocol
│  ├─ HermesChannel
│  ├─ BrokerAgentChannel
│  ├─ RemoteBrokerClient
│  ├─ AgentStore
│  ├─ AgentTab
│  └─ AgentConversationView
│
├─ Center Module
│  ├─ Voice capture and history
│  ├─ Camera capture and OCR
│  ├─ Memo capture and assignment
│  └─ Unified history timeline
│
├─ Team Module
│  ├─ Device tree
│  ├─ Agent profiles
│  ├─ Assignment targets
│  └─ Workflow board
│
├─ Shared Infrastructure
│  ├─ KeychainCredentialStore
│  ├─ UserDefaults app-group cache
│  ├─ TokenWebView
│  └─ LiveActivityManager
│
└─ Widget Extension
   ├─ Home Screen widgets
   ├─ Lock Screen widgets
   └─ Live Activity / Dynamic Island
```

### 数据链路

DeepSeek 刷新链路：

```text
TokenTab
  -> DashboardStore.refresh()
    -> UsageRepository.refresh()
      -> DeepSeekProvider.fetchSummary()
      -> DeepSeekProvider.fetchUsage()
    -> commit cache
    -> reload widgets
    -> sync Live Activity
```

Agent 会话链路：

```text
AgentTab
  -> AgentStore
    -> PreferredAgentChannel
      ├─ HermesChannel
      └─ BrokerAgentChannel
    -> list sessions
    -> list messages
    -> send / stream chat events
```

Broker Channel 链路：

```text
iPhone App
  -> Cloud Broker
    -> Registered Device Channel
      -> Local Agent Runtime
        -> Hermes / future agents
```

在 Broker 模式下，手机和电脑不需要彼此直连。它们都主动连接到同一个控制面，由 Broker 负责设备注册、在线状态、命令路由和结果回传。

### 安全设计

- DeepSeek Token 存储在 iOS Keychain。
- Broker Token 存储在 iOS Keychain。
- Hermes Key 存储在 iOS Keychain。
- DeepSeek Web 登录只允许从官方域名提取候选 Token。
- Widget 和 Live Activity 只缓存展示所需的摘要数据。
- 面向真实用户时，Broker 应部署在 HTTPS 后面。

### 目录结构

```text
.
├─ DeepLink/                 # iOS app source
├─ DeepLinkWidget/           # WidgetKit and Live Activity extension
├─ Shared/                   # Shared models and infrastructure
├─ DeepLinkTests/            # Unit tests
├─ broker/                   # Broker / control-plane code in this checkout
├─ docs/                     # Architecture notes and implementation docs
├─ scripts/                  # Validation scripts
├─ project.yml               # XcodeGen project definition
└─ build_and_install.sh      # Device build/install helper
```

> 当前部署中的 Broker 也可能位于同级独立仓库，具体以部署流程为准。

### 环境要求

- iOS 18.0+
- Xcode 16+
- XcodeGen
- DeepSeek Platform account
- 可选：Hermes-compatible Agent API Server
- 可选：cloud broker service

### 快速开始

生成 Xcode 项目：

```bash
xcodegen generate
```

校验项目结构：

```bash
./scripts/validate_project.sh
```

构建 App：

```bash
xcodebuild -project DeepLink.xcodeproj \
  -scheme DeepLink \
  -destination 'generic/platform=iOS' \
  build
```

安装到真机：

```bash
./build_and_install.sh
```

运行测试：

```bash
xcodebuild -project DeepLink.xcodeproj \
  -scheme DeepLink \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

### XcodeGen 约定

项目文件由 `project.yml` 生成，不要直接编辑 `project.pbxproj`。修改 `project.yml` 或新增需要进入 Xcode target 的文件后，执行：

```bash
xcodegen generate
```

### 当前状态

已具备：

- DeepSeek 登录、Token 提取与 Keychain 存储。
- 余额、用量和成本刷新链路。
- Widget 与 Live Activity 数据同步。
- 本地 Hermes 兼容会话。
- Broker 登录、设备列表和 Agent 发现架子。
- 语音、照片、备忘录统一历史记录。
- 轻量任务指派和模拟工作流。

推进中：

- Broker 部署加固。
- 远程 Channel 稳定性。
- WSS 传输。
- 多 Agent 工作流执行。
- 项目、资源、知识库和插件模块。
- 面向商用的账户、权限、审计和设置体验。

### Roadmap

- **Reliable Channel**：WSS、重连策略、在线状态、设备与 Agent 心跳。
- **Agent Registry**：Agent logo、版本、能力、Skills 与运行健康状态。
- **Workflow Engine**：人工审查节点、运行历史、重试、回滚和多 Agent 编排。
- **Knowledge Layer**：Obsidian、Notion、文件和项目上下文。
- **Commercial Readiness**：账户、团队权限、计费、审计日志和可观测性。
- **System Integration**：App Intents、Shortcuts、更丰富的组件和 Live Activities。

### 产品愿景

个人 AI 基础设施不应该是一堆终端窗口、后台网页、IP 地址、端口、Token 和散落的 Agent。手机可以成为控制面，组件可以成为状态灯，Broker 可以成为设备和 Agent 的会合点，语音、照片和备忘录可以成为任务入口。

---

## English

### Overview

DeepLink began with a very specific frustration: checking DeepSeek API balance should not require opening a browser, logging in, and digging through a dashboard. The first version brought DeepSeek balance, monthly usage, Home Screen widgets, Lock Screen widgets, and Dynamic Island status directly to iPhone.

As the project evolved, the real problem became broader: one person may run multiple agents across multiple devices, ports, runtimes, and networks. Pairing them, switching between them, checking their status, and opening the right session quickly becomes tedious. DeepLink is therefore evolving into a mobile control plane for personal agents: a way to connect devices and agents through a dedicated Channel and Broker, then manage sessions and daily tasks from one place.

DeepLink is not just a balance checker. Usage monitoring is the wedge. The larger direction is a personal AI infrastructure console that is always available from your phone.

### Core Positioning

- **API Usage Monitor**: DeepSeek balance, monthly usage, cost, Home Screen widgets, Lock Screen widgets, Live Activity, and Dynamic Island status.
- **Agent Console**: local and cloud-connected agents, device status, agent profiles, session lists, and conversations.
- **Personal Workflow Hub**: voice notes, camera/OCR notes, memos, task assignment, and early workflow orchestration.

### Why This Exists

- API usage lives in a separate provider dashboard.
- Agents run on different machines, ports, and runtimes.
- LAN connections work at home but become fragile elsewhere.
- Pairing often requires copying addresses, ports, keys, or shell scripts.
- Captured ideas still need to be manually routed to the right agent.
- Multi-agent collaboration still lacks a clear handoff surface.

DeepLink tries to collapse these scattered surfaces into one mobile experience: resource state, device state, agent sessions, capture tools, task assignment, and workflow orchestration.

### Features

#### DeepSeek Usage Monitoring

- Secure DeepSeek web login flow with domain-restricted token capture.
- Keychain-backed token storage.
- Balance, user summary, monthly usage, and model cost display.
- Last-known successful snapshot cache for faster relaunch.
- Home Screen widgets, Lock Screen widgets, Live Activity, and Dynamic Island sync.
- Receipt-style usage presentation animation.

#### Widgets and System Surfaces

DeepLink is designed to live beyond the app icon. Widgets, Lock Screen surfaces, Live Activity, and Dynamic Island make usage status visible without opening the app.

#### Agent Channel

DeepLink currently supports two connection modes:

- **Local Mode**: direct LAN connection to a Hermes-compatible API server.
- **Broker Mode**: both the phone and desktop-side channel connect outward to a cloud broker for relay and routing.

The channel layer is intentionally transport-oriented. Hermes is the first runtime, but the architecture leaves room for Claude Code, Codex, OpenClaw, and custom agents.

#### Agent Workspace

- Online devices and agents.
- Device-aware agent grouping.
- Agent kind, version, capabilities, and skills.
- Session list and conversation detail.
- Chat-style conversation UI.
- Local LAN and cloud broker contexts.
- Dedicated future surfaces for projects, resources, knowledge bases, and plugins.

#### Center: Fast Capture and Assignment

The center button is optimized for one-tap capture:

- **Voice**: record, transcribe, save, and replay.
- **Camera**: capture, OCR, and save image/text pairs.
- **Keyboard**: create quick memos.

The unified history timeline merges voice, image, and text records by time, while preserving type-specific actions such as playback, photo preview, OCR detail, and agent assignment.

#### Team and Workflow

The Team module is designed for two future directions:

- **Personal multi-agent team**: one user, multiple devices, multiple agents.
- **Collaborative team**: multiple users sharing devices, agents, and tasks.

Current workflow support is intentionally lightweight: drag-to-reorder steps, run/stop control, device-aware agent labels, and a simulated data collection, audit, and analysis pipeline.

### Architecture

```text
DeepLink iOS App
├─ Token Module
│  ├─ DeepSeekAPI
│  ├─ DeepSeekProvider
│  ├─ UsageRepository
│  ├─ DashboardStore
│  └─ TokenTab
│
├─ Agent Module
│  ├─ AgentChannel protocol
│  ├─ HermesChannel
│  ├─ BrokerAgentChannel
│  ├─ RemoteBrokerClient
│  ├─ AgentStore
│  ├─ AgentTab
│  └─ AgentConversationView
│
├─ Center Module
│  ├─ Voice capture and history
│  ├─ Camera capture and OCR
│  ├─ Memo capture and assignment
│  └─ Unified history timeline
│
├─ Team Module
│  ├─ Device tree
│  ├─ Agent profiles
│  ├─ Assignment targets
│  └─ Workflow board
│
├─ Shared Infrastructure
│  ├─ KeychainCredentialStore
│  ├─ UserDefaults app-group cache
│  ├─ TokenWebView
│  └─ LiveActivityManager
│
└─ Widget Extension
   ├─ Home Screen widgets
   ├─ Lock Screen widgets
   └─ Live Activity / Dynamic Island
```

### Data Flow

DeepSeek refresh flow:

```text
TokenTab
  -> DashboardStore.refresh()
    -> UsageRepository.refresh()
      -> DeepSeekProvider.fetchSummary()
      -> DeepSeekProvider.fetchUsage()
    -> commit cache
    -> reload widgets
    -> sync Live Activity
```

Agent session flow:

```text
AgentTab
  -> AgentStore
    -> PreferredAgentChannel
      ├─ HermesChannel
      └─ BrokerAgentChannel
    -> list sessions
    -> list messages
    -> send / stream chat events
```

Broker channel flow:

```text
iPhone App
  -> Cloud Broker
    -> Registered Device Channel
      -> Local Agent Runtime
        -> Hermes / future agents
```

In broker mode, the phone and desktop do not need to discover each other directly. Both connect outward to the same control plane, while the broker handles registration, online state, command routing, and result delivery.

### Security Model

- DeepSeek tokens are stored in iOS Keychain.
- Broker tokens are stored in iOS Keychain.
- Hermes keys are stored in iOS Keychain.
- DeepSeek web token extraction is restricted to official domains.
- Widgets and Live Activity only cache display-safe summary data.
- Production broker deployments should sit behind HTTPS.

### Repository Layout

```text
.
├─ DeepLink/                 # iOS app source
├─ DeepLinkWidget/           # WidgetKit and Live Activity extension
├─ Shared/                   # Shared models and infrastructure
├─ DeepLinkTests/            # Unit tests
├─ broker/                   # Broker / control-plane code in this checkout
├─ docs/                     # Architecture notes and implementation docs
├─ scripts/                  # Validation scripts
├─ project.yml               # XcodeGen project definition
└─ build_and_install.sh      # Device build/install helper
```

> The active broker deployment may also live in a sibling repository depending on the deployment flow.

### Requirements

- iOS 18.0+
- Xcode 16+
- XcodeGen
- DeepSeek Platform account
- Optional: Hermes-compatible Agent API Server
- Optional: cloud broker service

### Quick Start

Generate the Xcode project:

```bash
xcodegen generate
```

Validate project structure:

```bash
./scripts/validate_project.sh
```

Build the app:

```bash
xcodebuild -project DeepLink.xcodeproj \
  -scheme DeepLink \
  -destination 'generic/platform=iOS' \
  build
```

Install to a connected device:

```bash
./build_and_install.sh
```

Run tests:

```bash
xcodebuild -project DeepLink.xcodeproj \
  -scheme DeepLink \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

### XcodeGen Convention

The Xcode project is generated from `project.yml`. Do not edit `project.pbxproj` manually. After changing `project.yml` or adding files that must be included in the target, run:

```bash
xcodegen generate
```

### Current Status

Available:

- DeepSeek login, token extraction, and Keychain storage.
- Balance, usage, and cost refresh pipeline.
- Widget and Live Activity data sync.
- Local Hermes-compatible sessions.
- Broker login, device list, and agent discovery skeleton.
- Unified voice, photo, and memo history.
- Lightweight task assignment and simulated workflow.

In progress:

- Broker deployment hardening.
- Remote channel reliability.
- WSS transport.
- Multi-agent workflow execution.
- Project, resource, knowledge base, and plugin modules.
- Commercial-ready account, permission, audit, and settings experience.

### Roadmap

- **Reliable Channel**: WSS, reconnect strategy, online state, device and agent heartbeats.
- **Agent Registry**: agent logo, version, capabilities, skills, and runtime health.
- **Workflow Engine**: human review checkpoints, run history, retry, rollback, and multi-agent orchestration.
- **Knowledge Layer**: Obsidian, Notion, files, and project context.
- **Commercial Readiness**: accounts, team permissions, billing, audit logs, and observability.
- **System Integration**: App Intents, Shortcuts, richer widgets, and richer Live Activities.

### Vision

Personal AI infrastructure should not feel like a pile of terminals, dashboards, IP addresses, ports, tokens, and disconnected agents. The phone can become the control surface, widgets can become status lights, the broker can become the meeting point, and voice/photo/memo capture can become the task entry layer.

## License

MIT
