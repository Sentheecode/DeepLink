# 任务 2：Agent 模块集成设计

## 背景

现有 `DeepSeekBalance` App 已经完成余额查询、Token 登录、Widget、Live Activity 和打印账单动画。现在需要在同一个 App 内新增第二个业务模块，用来接入 agent / Hermes 能力。

这个模块必须和余额模块并存，但不能把业务逻辑混在一起。

## 设计目标

1. 让 App 具有两个清晰独立的模块
2. 余额模块继续稳定工作，不被新模块打断
3. Agent 模块拥有自己的路由、状态、存储和网络边界
4. 未来可继续扩展其他模型，不需要重写整个 App 壳层

## 必须保留的现有能力

- Token 登录
- Keychain 存储
- 余额查询
- Widget
- Live Activity
- 打印账单动画

## 需要新增的能力

- Agent 模块入口
- 会话列表
- 消息详情
- 基础消息同步
- agent 状态展示

## 必须重构的地方

### 1. 主入口拆分

现有 `ContentView` 已经承担太多职责：

- 余额 UI
- 设置 UI
- 刷新控制
- 打印账单动画
- Token 登录入口

需要把它拆成：

- `AppShell`
- `BalanceFeature`
- `AgentFeature`

### 2. 状态拆分

余额模块继续使用现有状态链：

- `DashboardStore`
- `UsageRepository`
- `DeepSeekProvider`

Agent 模块新增：

- `AgentStore`
- `AgentRepository` 或 `SessionRepository`
- `AgentService`

### 3. 网络拆分

余额模块的 API 不应该继续承担 agent 能力。

建议新增独立服务：

- `HermesAPI`
- `AgentAPI`
- `SessionSyncService`

### 4. 持久化拆分

余额侧维持现状：

- Keychain
- App Group UserDefaults

Agent 侧建议使用：

- SwiftData
- 或单独的本地缓存层

### 5. 路由拆分

不建议继续在 `ContentView` 里把所有页面塞完。

建议使用：

- `TabView`
- 或根 `NavigationStack`
- 或首页卡片入口

## 推荐架构

```text
AppShell
├─ BalanceFeature
│  ├─ DashboardStore
│  ├─ UsageRepository
│  ├─ LiveActivity
│  └─ Widget
└─ AgentFeature
   ├─ AgentStore
   ├─ AgentAPI
   ├─ ConversationStore
   └─ MessageList / Detail
```

## 数据流建议

### 余额模块

1. 读取缓存
2. 后台刷新
3. 刷新成功后再提交 Widget 和 Live Activity

### Agent 模块

1. 读取本地会话缓存
2. 后台拉取会话/消息增量
3. 更新本地存储
4. 刷新 UI

## 这次实现的 MVP

只做最小可用版本：

- App 里出现 Agent 模块入口
- Agent 模块能进入
- Agent 模块有空状态、列表页、详情页占位
- 模块边界已拆开
- 业务逻辑保持可扩展

暂不做：

- 文件系统
- 多平台同步
- 流式回复
- 复杂搜索
- 多会话合并
- 通知推送

## 验收标准

- 余额模块编译和运行不受影响
- Agent 模块是独立 feature，不污染余额逻辑
- `ContentView` 不再继续膨胀
- App 壳层可以同时承载两个模块
- Claude Code 能在这个骨架上继续写完具体功能

