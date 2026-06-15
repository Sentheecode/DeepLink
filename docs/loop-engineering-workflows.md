# Loop Engineering Workflows

DeepLink 的工作流不再只表示固定的步骤链，而是表示一个有停止条件的 Agent 闭环。

## 核心循环

1. 定义目标和可验证的成功条件。
2. 执行 Agent 完成当前步骤并产生可留存结果。
3. 审查 Agent 根据成功条件验证结果。
4. 若验证失败，将反馈带入下一轮，而不是重新从空白开始。
5. 达到成功条件、最大循环次数或人工停止条件后结束。

## 当前数据模型

- `AgentWorkflow.goal`: 循环要达成的目标。
- `AgentWorkflow.successCriteria`: 审查时使用的成功条件。
- `AgentWorkflow.maxIterations`: 成本和失控保护。
- `AgentWorkflow.state`: 草稿、循环中、等待审查、已达成或已停止。
- `AgentWorkflowStep.agentID`: 执行 Agent。
- `AgentWorkflowStep.reviewerAgentID`: 独立审查 Agent。
- `AgentWorkflowStep.requiresHumanApproval`: 高风险步骤的人工检查点。

## 后续执行引擎

服务端执行引擎应持久化每一轮输入、输出、审查结果、成本和失败原因。每次进入下一轮前，只传递本轮必要上下文和上一轮反馈，避免上下文无限增长。执行引擎必须支持暂停、恢复、取消、最大成本和最大迭代次数。

参考：

- Addy Osmani, Loop Engineering: https://addyosmani.com/blog/loop-engineering/
- Anthropic, Building Effective AI Agents: https://www.anthropic.com/research/building-effective-agents
- OpenAI, Agent Improvement Loop: https://developers.openai.com/cookbook/examples/agents_sdk/agent_improvement_loop
