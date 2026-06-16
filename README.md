# DeepLink

**DeepSeek API 用量监控 + Hermes Agent 移动端** — SwiftUI iOS 客户端

## 功能

- **余额监控** — 实时查看 DeepSeek API 余额、月度用量、成本统计
- **Hermes Agent 聊天** — 通过 SSE 流式与本地 Hermes Agent 对话（LAN 直连）
- **Widget + Live Activity** — 桌面试件实时显示余额，灵动岛推送通知
- **Web 登录注入** — WKWebView 自动提取 DeepSeek 用户 Token，Keychain 安全存储
- **安全加密** — API Token 全部存入 Keychain，不落本地文件

## 快速开始

```bash
# 1. 生成 Xcode 项目
xcodegen generate

# 2. 安装到设备
./build_and_install.sh

# 3. 或者直接构建
xcodebuild -project DeepLink.xcodeproj -scheme DeepLink -destination 'generic/platform=iOS' build
```

## 系统要求

- iOS 18.0+
- Xcode 16+
- [Hermes Agent](https://hermes-agent.nousresearch.com) (本地聊天功能需要)

## 架构

```
AppShell (ZStack + Custom Tab Bar)
├─ TokenTab    — DeepSeek 余额用量面板
├─ AgentTab    — Hermes Agent 对话
├─ CenterTab   — 控制中心
├─ TeamTab     — 团队空间
└─ SettingsTab — 配置管理

Shared
├─ CredentialStore  — Keychain 封装
├─ UsageRepository  — 数据刷新管线
├─ DashboardStore   — 状态管理 @Observable
└─ LiveActivityManager — 灵动岛同步
```

## 项目生成

使用 [XcodeGen](https://github.com/Yonaskolb/XcodeGen) 管理项目文件，**不要直接编辑 `project.pbxproj`**。

```bash
# 修改 project.yml 或添加文件后
xcodegen generate

# 验证项目结构
./scripts/validate_project.sh
```

## 测试

```bash
xcodebuild -project DeepLink.xcodeproj -scheme DeepLink -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## LICENSE

MIT
