# Claude Code 任务 1：搭建 Agent 模块骨架

## 目标

在现有 `DeepSeekBalance` App 内新增一个独立的 `Agent` 模块骨架，为后续接入 Hermes / agent 能力做准备。

这次只做骨架和路由，不实现完整业务逻辑。

## 你要完成的内容

1. 新增 App 壳层
   - 建立一个清晰的根入口
   - 把现有余额模块和新的 Agent 模块放到同一个壳层里

2. 新增 Agent 模块目录
   - `Features/Agent/Views`
   - `Features/Agent/Store`
   - `Features/Agent/Services`
   - `Features/Agent/Models`

3. 新增基础页面
   - Agent 首页
   - 会话列表占位页
   - 会话详情占位页
   - 空状态视图

4. 新增基础状态对象
   - `AgentStore`
   - 用 `@Observable` 或当前项目一致的状态管理方式
   - 只放最小状态：loading、error、会话列表占位数据

5. 新增基础模型
   - `Conversation`
   - `Message`
   - `Attachment`
   - `AgentSession`

6. 新增基础服务协议
   - `AgentAPI`
   - `ConversationRepository`
   - `MessageRepository`

7. 打通路由
   - 在 App 壳层里让用户可以进入 Agent 模块
   - 保持余额模块现有行为不变

## 重要约束

- 不要重写余额模块
- 不要改动现有 Widget / Live Activity 的业务逻辑
- 不要把 Agent 逻辑塞进 `ContentView`
- 不要让新模块依赖余额模块内部实现
- 如果需要共享能力，只能放到 `Shared` 或 `Core` 层

## 推荐实现方式

- 保持现有余额模块为一个独立 feature
- 新增 Agent feature
- 从 AppShell 统一导航
- 如果需要，先用假数据 / 占位数据把页面跑起来

## 完成标准

- 项目能编译
- App 中能进入 Agent 模块
- Agent 模块有独立页面结构
- 余额模块功能不回退
- 代码结构足够清晰，后续可以继续补消息同步和 Hermes 接入

