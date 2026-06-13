import Foundation

protocol AgentChannel: Sendable {
    func loadSavedConfig() async
    var isConfigured: Bool { get }
    func listSessions() async throws -> [HermesSession]
    func createSession(title: String?) async throws -> HermesSession
    func deleteSession(id: String) async throws
    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage]
    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error>
    func health() async throws -> Bool
    func configure(baseURL: String, apiKey: String) async
}

// MARK: - Hermes API 客户端

actor HermesAPI {
    static let shared = HermesAPI()

    private var baseURL = "http://localhost:8642"
    private var apiKey = ""

    func configure(baseURL: String, apiKey: String) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.apiKey = apiKey
        Self.configuredKey = apiKey
        UserDefaults.standard.set(self.baseURL, forKey: "hermesURL")
        UserDefaults.standard.set(apiKey, forKey: "hermesAPIKey")
        if !apiKey.isEmpty {
            try? KeychainCredentialStore().saveToken(apiKey, for: .hermesKey)
        } else {
            try? KeychainCredentialStore().deleteToken(for: .hermesKey)
        }
    }

    private nonisolated(unsafe) static var configuredKey = ""

    nonisolated var isConfigured: Bool {
        let savedURL = UserDefaults.standard.string(forKey: "hermesURL") ?? ""
        return !savedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func loadSavedConfig() {
        if let url = UserDefaults.standard.string(forKey: "hermesURL"), !url.isEmpty {
            baseURL = url.hasSuffix("/") ? String(url.dropLast()) : url
        }
        if let key = try? KeychainCredentialStore().getToken(for: .hermesKey), !key.isEmpty {
            apiKey = key
            Self.configuredKey = key
        }
    }

    // MARK: - Sessions

    func listSessions() async throws -> [HermesSession] {
        let data = try await get("/api/sessions")
        guard !data.isEmpty else { return [] }

        // 用 JSONSerialization 手动解析，兼容 sessions / data 两种返回格式
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw HermesError.apiError(code: 0, message: "JSON 格式错误: \(raw.prefix(100))")
        }

        guard let items = (json["data"] as? [[String: Any]]) ?? (json["sessions"] as? [[String: Any]]) else {
            throw HermesError.apiError(code: 0, message: "缺少 sessions/data 字段")
        }

        return items.compactMap { item in
            guard let id = (item["id"] as? String) ?? (item["session_id"] as? String) else { return nil }
            return HermesSession(
                id: id,
                title: item["title"] as? String,
                source: item["source"] as? String,
                userId: item["user_id"] as? String,
                model: item["model"] as? String,
                startedAt: item["started_at"] as? String
            )
        }
    }

    func createSession(title: String?) async throws -> HermesSession {
        var body: [String: String] = [:]
        if let title = title { body["title"] = title }
        let data = try await post("/api/sessions", body: body.isEmpty ? nil : body)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String ?? json["session_id"] as? String else {
            throw HermesError.apiError(code: 0, message: "创建会话失败: 无法解析响应")
        }

        return HermesSession(
            id: id,
            title: json["title"] as? String,
            source: json["source"] as? String,
            userId: json["user_id"] as? String,
            model: json["model"] as? String,
            startedAt: json["started_at"] as? String
        )
    }

    func deleteSession(id: String) async throws {
        _ = try await delete("/api/sessions/\(id)")
    }

    // MARK: - Messages

    func listMessages(sessionId: String, before: String? = nil, limit: Int = 50) async throws -> [HermesMessage] {
        var path = "/api/sessions/\(sessionId)/messages?limit=\(limit)"
        if let before = before { path += "&before=\(before)" }
        let data = try await get(path)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HermesError.apiError(code: 0, message: "消息 JSON 解析失败")
        }

        guard let items = (json["data"] as? [[String: Any]]) ?? (json["messages"] as? [[String: Any]]) else {
            return []
        }

        return items.compactMap(HermesMessage.parse)
    }

    // MARK: - Chat (流式)

    func chatStream(sessionId: String, message: String) -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = URL(string: "\(baseURL)/api/sessions/\(sessionId)/chat/stream") else {
                        continuation.finish(throwing: HermesError.apiError(code: 0, message: "无效的 URL"))
                        return
                    }
                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    if !apiKey.isEmpty {
                        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 600
                    req.httpBody = try JSONEncoder().encode(["message": message])

                    let (bytes, response) = try await URLSession.shared.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw HermesError.apiError(code: 0, message: "不是 HTTP 响应")
                    }
                    guard http.statusCode == 200 else {
                        let bodyData = try await bytes.reduce(into: Data()) { $0.append($1) }
                        let body = String(data: bodyData, encoding: .utf8) ?? "空"
                        throw HermesError.apiError(code: http.statusCode, message: "HTTP \(http.statusCode): \(body.prefix(300))")
                    }

                    var currentEvent = ""
                    var eventCount = 0
                    var rawBuffer = ""

                    for try await line in bytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        rawBuffer += trimmed + "\n"

                        if trimmed.hasPrefix("event: ") {
                            currentEvent = String(trimmed.dropFirst(7))
                        } else if trimmed.hasPrefix("data: ") {
                            eventCount += 1
                            let jsonStr = String(trimmed.dropFirst(6))
                            guard let jsonData = jsonStr.data(using: .utf8),
                                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                                continue
                            }

                            // Map Hermes SSE event types to our simplified format
                            var mappedType = currentEvent
                            var mappedContent: String?
                            var mappedName: String?

                            switch currentEvent {
                            case "assistant.delta":
                                mappedType = "text"
                                mappedContent = json["delta"] as? String
                            case "tool.progress":
                                // _thinking 文本已在 assistant.delta 送达，跳过避免重复
                                if json["tool_name"] as? String == "_thinking" {
                                    continue
                                }
                                mappedType = "thinking"
                                mappedContent = json["delta"] as? String
                                mappedName = json["tool_name"] as? String
                            case "assistant.completed", "run.completed":
                                // 内容已通过 assistant.delta 流式送达，跳过避免重复
                                continue
                            case "done":
                                mappedType = "done"
                            case "error":
                                mappedType = "error"
                                mappedContent = json["error"] as? String ?? json["message"] as? String
                            case "run.started", "message.started":
                                continue // Skip these metadata events
                            default:
                                mappedContent = json["content"] as? String ?? json["delta"] as? String
                            }

                            if let content = mappedContent, !content.isEmpty {
                                continuation.yield(HermesStreamEvent(
                                    type: mappedType, content: content,
                                    name: mappedName, arguments: nil, summary: nil
                                ))
                            } else if mappedType == "done" {
                                // Still yield done events even without content
                                continuation.yield(HermesStreamEvent(
                                    type: "done", content: nil,
                                    name: nil, arguments: nil, summary: nil
                                ))
                            }
                        }
                    }

                    if eventCount == 0 {
                        // No SSE events found — try plain JSON response
                        if let json = try? JSONSerialization.jsonObject(with: rawBuffer.data(using: .utf8) ?? Data()) as? [String: Any],
                           let content = json["content"] as? String ?? json["reply"] as? String {
                            continuation.yield(HermesStreamEvent(type: "text", content: content, name: nil, arguments: nil, summary: nil))
                        } else if !rawBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            continuation.yield(HermesStreamEvent(type: "text", content: String(rawBuffer.prefix(800)), name: nil, arguments: nil, summary: nil))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in }
        }
    }

    // MARK: - Health

    func health() async throws -> Bool {
        do {
            guard let url = URL(string: "\(baseURL)/api/sessions") else {
                throw HermesError.apiError(code: 0, message: "无效的 URL")
            }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            req.timeoutInterval = 5
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw HermesError.invalidResponse }
            if http.statusCode == 200 { return true }
            let body = String(data: data, encoding: .utf8) ?? "空"
            throw HermesError.apiError(code: http.statusCode, message: "HTTP \(http.statusCode): \(body.prefix(100))")
        } catch let e as HermesError { throw e }
        catch { throw HermesError.apiError(code: 0, message: "连接失败: \(error.localizedDescription)") }
    }

    // MARK: - HTTP

    func validateURL() throws {
        guard URL(string: baseURL) != nil else {
            throw HermesError.apiError(code: 0, message: "无效的服务器地址，请检查格式")
        }
    }

    private func request(_ path: String, method: String, body: Data? = nil) async throws -> Data {
        try validateURL()
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw HermesError.apiError(code: 0, message: "无效的 URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        if let body = body { req.httpBody = body; req.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        req.timeoutInterval = 8
        let (data, resp) = try await URLSession.shared.data(for: req)
        try checkResponse(resp, data: data)
        return data
    }

    private func get(_ path: String) async throws -> Data { try await request(path, method: "GET") }
    private func post(_ path: String, body: Encodable?) async throws -> Data {
        let data = body.map { try? JSONEncoder().encode(AnyEncodable($0)) } ?? nil
        return try await request(path, method: "POST", body: data)
    }
    private func delete(_ path: String) async throws -> Data { try await request(path, method: "DELETE") }

    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw HermesError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let err = body["error"] as? [String: Any],
               let msg = err["message"] as? String {
                throw HermesError.apiError(code: http.statusCode, message: msg)
            }
            throw HermesError.httpError(http.statusCode)
        }
    }
}

// MARK: - Models

struct HermesSession: Codable, Identifiable {
    let id: String
    let title: String?
    let source: String?
    let userId: String?
    let model: String?
    let startedAt: String?

    var displayTitle: String { title ?? "会话 (\(id.prefix(8))...)" }

    enum CodingKeys: String, CodingKey {
        case id, title, source, model
        case userId = "user_id"
        case startedAt = "started_at"
    }
}

struct HermesMessage: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let createdAt: String?

    static func parse(_ item: [String: Any]) -> HermesMessage? {
        let id: String
        if let stringID = item["id"] as? String {
            id = stringID
        } else if let numericID = item["id"] as? NSNumber {
            id = numericID.stringValue
        } else {
            return nil
        }
        guard let role = item["role"] as? String else { return nil }
        return HermesMessage(
            id: id,
            role: role,
            content: item["content"] as? String ?? "",
            createdAt: item["created_at"] as? String
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
    }
}

struct HermesSessionListResponse: Codable {
    let object: String?
    let data: [HermesSession]
}

struct HermesMessageListResponse: Codable {
    let object: String?
    let data: [HermesMessage]?
}

struct HermesStreamEvent: Codable {
    let type: String
    let content: String?
    let name: String?
    let arguments: String?
    let summary: String?

    var streamEvent: String = ""

    var displayIcon: String {
        switch type {
        case "thinking": return "brain"
        case "tool_call": return "wrench"
        case "tool_result": return "terminal"
        case "text": return "text.alignleft"
        case "error": return "exclamationmark.triangle"
        case "done": return "checkmark"
        default: return "circle"
        }
    }
}

// MARK: - Errors

enum HermesError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(code: Int, message: String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "无效响应"
        case .httpError(let c): return "HTTP \(c)"
        case .apiError(_, let m): return m
        case .notConfigured: return "请先配置 Hermes 连接"
        }
    }
}

// MARK: - AnyEncodable helper

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
