# 任务 3：Agent Broker / Device Channel 骨架

## 目标

在现有 `DeepSeekBalance` App 的 `Agent` 模块基础上，补出一个可替换的 channel / device / broker 骨架，为后续接入 GitHub 登录、Tailscale 可达设备、以及远程消息中枢做准备。

这次只做“架子和边界”，不实现完整云端 broker。

## 你要完成的内容

1. 保留当前 Hermes 直连能力
   - 当前 `HermesChannel` 继续能工作
   - 会话列表、消息流、发送消息不回退

2. 新增设备抽象
   - `AgentDevice`
   - `AgentConnectionProfile`
   - `AgentConnectionKind`
   - 设备列表可以先返回空或本地缓存

3. 新增 device registry
   - `AgentDeviceRegistry`
   - `LocalAgentDeviceRegistry`
   - 负责保存用户选中的设备 ID

4. 新增 broker client 协议
   - `AgentBrokerClient`
   - `LocalBrokerClient`
   - 先把它当作一个可以包装现有 channel 的适配层

5. 给 Agent 模块留出设备选择入口
   - `AgentStore` 需要知道“当前选中的设备/连接”
   - UI 先可以用一个简单的选择器或占位区展示当前连接

6. 写一份架构说明
   - 说明 GitHub 登录、设备发现、消息路由三层关系
   - 说明 Tailscale 只作为节点可达性手段，不直接进入 iPhone UI 逻辑

## 重要约束

- 不要把 Tailscale UI 塞进 App
- 不要要求用户额外安装一个新的 iPhone 伴随 App
- 不要删除现有 Hermes 直连逻辑
- 不要在这次直接实现完整公网 broker
- 不要让 `AppShell` 重新膨胀

## 推荐实现方式

- 保持 `HermesChannel` 作为第一个可用 channel
- 新增 `AgentBrokerClient` 作为未来远程 broker 的统一入口
- `AgentStore` 通过 channel / registry 获取设备和消息，不直接依赖具体网络
- 设备选择状态保存在本地，后续可同步到后端

## 完成标准

- 项目能编译
- Agent 模块还能正常打开会话列表和消息详情
- 代码里出现明确的 device / broker / channel 边界
- 后续 Claude Code 可以在这份骨架上继续补 GitHub 登录、设备发现和远程路由

