# Hermes Agent API 接口文档

iOS App 通过 Hermes 内置的 API Server 平台与代理对话。代理具备完整工具能力（终端、文件、代码执行、搜索等），所有执行过程通过 SSE 流式反馈给 App。

## 架构

```
iOS App → HTTP/SSE → Hermes API Server (localhost:8642) → LLM Provider (DeepSeek etc.)
                                                    ↓
                                             系统工具（终端/文件/代码等）
```

Hermes API Server 是 Hermes Gateway 的一个内置平台适配器，基于 `aiohttp`，**不需要额外编写后端代码**。

---

## 1. 启用 API Server

### 在 .env 中添加：

```bash
# ~/.hermes/.env

API_SERVER_ENABLED=true
API_SERVER_KEY=your-secret-key-here    # Bearer Token 认证用
API_SERVER_HOST=0.0.0.0               # 局域网访问用 0.0.0.0，本地测试用 127.0.0.1
API_SERVER_PORT=8642                   # 默认 8642
API_SERVER_CORS_ORIGINS=*             # 浏览器 CORS（App 不需要）
```

### 启动：

```bash
# 直接前台运行
API_SERVER_ENABLED=true hermes gateway run

# 或作为后台服务
hermes gateway install  # systemd/launchd 服务
hermes gateway start
```

启动后服务运行在 `http://<host>:8642`。

---

## 2. 认证

所有接口需在请求头中携带：

```
Authorization: Bearer your-secret-key-here
```

`API_SERVER_KEY` 在 `.env` 中配置。

未认证返回 `401`:
```json
{"error": {"message": "Unauthorized", "code": "unauthorized"}}
```

---

## 3. API 端点

### 3.1 核心聊天（推荐方案）

#### 3.1.1 创建会话

```
POST /api/sessions
```

请求体：
```json
{
  "title": "可选会话标题"
}
```

响应：
```json
{
  "session_id": "api-abc123def456",
  "title": "可选会话标题",
  "created_at": "2026-06-08T10:00:00Z"
}
```

#### 3.1.2 发送消息（流式）

```
POST /api/sessions/{session_id}/chat/stream
```

请求体：
```json
{
  "message": "帮我查一下当前系统的磁盘使用情况"
}
```

认证：`Authorization: Bearer <API_SERVER_KEY>`

**响应：SSE（text/event-stream）**

事件格式（每个 `data:` 是一行 JSON）：

```
event: message
data: {"type": "text", "content": "正在查询磁盘信息..."}

event: message
data: {"type": "text", "content": "执行命令: df -h"}

event: tool_call
data: {"type": "tool_call", "name": "terminal", "arguments": "df -h"}

event: tool_result
data: {"type": "tool_result", "name": "terminal", "summary": "Filesystem ..."}

event: message
data: {"type": "text", "content": "当前磁盘使用情况如下：\n已用 45%，剩余 256GB..."}

event: done
data: {"type": "done"}
```

**事件类型说明：**

| event 字段 | type 值 | 说明 |
|---|---|---|
| `message` | `text` | AI 回复文本（可能分多次发送） |
| `message` | `thinking` | AI 思考过程 |
| `tool_call` | `tool_call` | 代理正在调用某个工具 |
| `tool_result` | `tool_result` | 工具执行结果摘要 |
| `error` | `error` | 错误信息 |
| `done` | `done` | 本轮回复结束 |

#### 3.1.3 获取会话消息历史

```
GET /api/sessions/{session_id}/messages
```

查询参数：
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| before | string | 否 | 游标分页（消息 ID） |
| limit | int | 否 | 每页条数（默认 50） |

响应：
```json
{
  "messages": [
    {
      "id": "msg_001",
      "role": "user",
      "content": "帮我查磁盘",
      "created_at": "2026-06-08T10:00:00Z"
    },
    {
      "id": "msg_002",
      "role": "assistant",
      "content": "当前磁盘使用情况如下：\n已用 45%...",
      "created_at": "2026-06-08T10:00:05Z"
    }
  ]
}
```

#### 3.1.4 会话列表

```
GET /api/sessions
```

响应：
```json
{
  "sessions": [
    {
      "session_id": "api-abc123",
      "title": "会话标题",
      "message_count": 12,
      "created_at": "2026-06-08T10:00:00Z",
      "updated_at": "2026-06-08T10:30:00Z"
    }
  ]
}
```

#### 3.1.5 删除会话

```
DELETE /api/sessions/{session_id}
```

响应：
```json
{"ok": true}
```

---

### 3.2 异步运行模式（适合长时间任务）

如果任务可能持续几分钟（比如写代码、部署），使用 Runs API：

```
POST /v1/runs
```

请求体：
```json
{
  "input": "帮我写一个 Python Web 服务"
}
```

响应（202）：
```json
{
  "run_id": "run-xxx",
  "status": "queued"
}
```

```
GET /v1/runs/{run_id}/events      → SSE 流式获取执行事件
POST /v1/runs/{run_id}/stop       → 中断运行（POST body 空即可）
GET  /v1/runs/{run_id}            → 查询当前状态
```

### 3.3 OpenAI 兼容模式（可选）

如果 App 已经有 OpenAI SDK 集成，也可以用标准格式：

```
POST /v1/chat/completions
```

请求体（标准 OpenAI 格式）：
```json
{
  "model": "hermes-agent",
  "messages": [{"role": "user", "content": "你好"}],
  "stream": true
}
```

加 `X-Hermes-Session-Id` 请求头实现会话连续性：
```
X-Hermes-Session-Id: my-custom-session-id
```

---

## 4. 工具执行反馈

Hermes 的独特价值在于它能执行工具。当代理调用工具时，API Server 会把工具调用和执行结果通过 SSE 推送给 App。

典型工具执行流程（SSE 事件序列）：

```
→ 用户: "帮我查下磁盘然后建个文件夹"
↓
data: {"type": "thinking", "content": "用户需要我查磁盘并建文件夹"}
data: {"type": "tool_call", "name": "terminal", "arguments": "df -h"}
data: {"type": "tool_result", "name": "terminal", "summary": "Filesystem      Size  Used Avail ..."}
data: {"type": "text", "content": "当前磁盘使用率 45%"}
data: {"type": "tool_call", "name": "terminal", "arguments": "mkdir -p /tmp/test"}
data: {"type": "tool_result", "name": "terminal", "summary": "（执行成功）"}
data: {"type": "text", "content": "文件夹已创建在 /tmp/test"}
data: {"type": "done"}
```

App 端可以据此在 UI 上显示：
- 💭 思考中...
- 🔧 正在执行命令：`df -h`
- 📋 命令输出摘要
- ✅ 完成

---

## 5. 速率限制

- 无默认速率限制（取决于服务器资源和 LLM Provider 的 API 限额）
- 单次请求最大消息体：10 MB
- 消息内容单段最大：64 KB
- 单次对话最大迭代次数：90 轮工具调用（可配置）

---

## 6. 错误格式

所有错误返回统一格式：

```json
{
  "error": {
    "code": "unauthorized",
    "message": "Invalid API key"
  }
}
```

常见错误码：
| 状态码 | code | 说明 |
|--------|------|------|
| 401 | unauthorized | API Key 无效 |
| 404 | not_found | 会话不存在 |
| 413 | body_too_large | 请求体超 10MB |
| 500 | internal_error | 服务端异常 |

---

## 7. 部署建议

### 本地开发
```
API_SERVER_ENABLED=true API_SERVER_KEY=test-key API_SERVER_HOST=127.0.0.1 hermes gateway run
```
App 连接 `http://127.0.0.1:8642`

### 服务器部署
可以在 Mac mini / VPS 上长期运行：
```bash
# 写入 .env
echo "API_SERVER_ENABLED=true" >> ~/.hermes/.env
echo "API_SERVER_KEY=your-production-key" >> ~/.hermes/.env

# 作为服务安装
hermes gateway install
hermes gateway start
```

然后 App 通过 HTTPS + 公网 IP/域名连接。

---

## 8. 各端点对照表（对应原需求）

| 原需求 | 实际端点 | 备注 |
|--------|----------|------|
| 会话列表 | `GET /api/sessions` | ✅ |
| 创建会话 | `POST /api/sessions` | ✅ |
| 消息列表 | `GET /api/sessions/{id}/messages` | ✅ |
| 发送消息(同步) | `POST /api/sessions/{id}/chat` | ✅ 非流式 |
| 发送消息(流式) | `POST /api/sessions/{id}/chat/stream` | ✅ SSE 流式 |
| 删除会话 | `DELETE /api/sessions/{id}` | ✅ |
| Agent 状态 | `GET /health` | ✅ |
| 流式输出 | SSE 支持 | ✅ |
| 错误格式 | 统一 error 对象 | ✅ |
