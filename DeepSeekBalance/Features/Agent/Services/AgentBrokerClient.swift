import Foundation

protocol AgentBrokerClient: Sendable {
    func connect() async throws
    func disconnect() async
    func fetchDevices() async throws -> [AgentDevice]
    func selectDevice(id: String) async throws
    func deleteDevice(id: String) async throws
    func updateDevice(id: String, name: String?, endpoint: String?) async throws
    func listSessions() async throws -> [HermesSession]
    func createSession(title: String?) async throws -> HermesSession
    func deleteSession(id: String) async throws
    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage]
    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error>
}

struct LocalBrokerClient: AgentBrokerClient {
    let channel: any AgentChannel

    func connect() async throws {}
    func disconnect() async {}
    func fetchDevices() async throws -> [AgentDevice] { [] }
    func selectDevice(id: String) async throws {}
    func deleteDevice(id: String) async throws {}
    func updateDevice(id: String, name: String?, endpoint: String?) async throws {}
    func listSessions() async throws -> [HermesSession] { try await channel.listSessions() }
    func createSession(title: String?) async throws -> HermesSession { try await channel.createSession(title: title) }
    func deleteSession(id: String) async throws { try await channel.deleteSession(id: id) }
    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage] {
        try await channel.listMessages(sessionId: sessionId, before: before, limit: limit)
    }
    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error> {
        await channel.chatStream(sessionId: sessionId, message: message)
    }
}

// MARK: - Remote Broker

enum AgentConnectionMode: String, CaseIterable {
    case local
    case broker
}

enum BrokerDefaults {
    static let baseURLKey = "agent.brokerURL"
    static let deviceIDKey = "agent.brokerDeviceID"
    static let connectionModeKey = "agent.connectionMode"
    static var defaultBaseURL: String {
        Bundle.main.object(forInfoDictionaryKey: "BrokerBaseURL") as? String ?? ""
    }
}

struct BrokerAccount {
    let id: String
    let displayName: String
    let deviceCount: Int
    let rpcCount: Int
}

actor RemoteBrokerClient: AgentBrokerClient {
    private var baseURL = BrokerDefaults.defaultBaseURL
    private var token = ""
    private var selectedDeviceID = ""

    func loadSavedConfig() {
        baseURL = UserDefaults.standard.string(forKey: BrokerDefaults.baseURLKey) ?? BrokerDefaults.defaultBaseURL
        selectedDeviceID = UserDefaults.standard.string(forKey: BrokerDefaults.deviceIDKey) ?? ""
        token = (try? KeychainCredentialStore().getToken(for: .brokerKey)) ?? ""
    }

    func configure(baseURL: String, token: String, deviceID: String) throws {
        let normalized = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: normalized), url.scheme == "http" || url.scheme == "https" else {
            throw BrokerError.invalidConfiguration
        }
        self.baseURL = normalized.hasSuffix("/") ? String(normalized.dropLast()) : normalized
        self.token = token
        self.selectedDeviceID = deviceID
        UserDefaults.standard.set(self.baseURL, forKey: BrokerDefaults.baseURLKey)
        UserDefaults.standard.set(deviceID, forKey: BrokerDefaults.deviceIDKey)
        try KeychainCredentialStore().saveToken(token, for: .brokerKey)
    }

    func connect() async throws {
        _ = try await request(path: "/health", authenticated: false)
    }

    func register(username: String, email: String, password: String) async throws {
        guard !baseURL.isEmpty else { throw BrokerError.invalidConfiguration }
        _ = try await request(
            path: "/v1/auth/register",
            method: "POST",
            body: ["username": username, "email": email, "password": password],
            authenticated: false
        )
        try await login(username: username, password: password)
    }

    func login(username: String, password: String) async throws {
        guard !baseURL.isEmpty else { throw BrokerError.invalidConfiguration }
        let json = try await request(
            path: "/v1/auth/login",
            method: "POST",
            body: ["username": username, "password": password],
            authenticated: false
        )
        guard let accessToken = json["access_token"] as? String else {
            throw BrokerError.invalidResponse
        }
        try configure(baseURL: baseURL, token: accessToken, deviceID: "")
        UserDefaults.standard.set(AgentConnectionMode.broker.rawValue, forKey: BrokerDefaults.connectionModeKey)
    }

    func disconnect() async {}

    func fetchDevices() async throws -> [AgentDevice] {
        let json = try await request(path: "/v1/devices")
        guard let items = json["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let name = item["name"] as? String else { return nil }
            return AgentDevice(
                id: id,
                name: name,
                kind: .brokerRelay,
                endpoint: item["endpoint"] as? String,
                isOnline: item["isOnline"] as? Bool ?? false,
                lastSeenAt: Self.parseDate(item["lastSeenAt"] as? String)
            )
        }
    }

    func selectDevice(id: String) async throws {
        selectedDeviceID = id
        UserDefaults.standard.set(id, forKey: BrokerDefaults.deviceIDKey)
    }

    func listSessions() async throws -> [HermesSession] {
        let data = try await rpc(method: "list_sessions")
        return Self.parseSessions(data)
    }

    func createSession(title: String?) async throws -> HermesSession {
        var params: [String: Any] = [:]
        if let title, !title.isEmpty { params["title"] = title }
        let data = try await rpc(method: "create_session", params: params)
        guard let item = data as? [String: Any], let session = Self.parseSession(item) else {
            throw BrokerError.invalidResponse
        }
        return session
    }

    func deleteSession(id: String) async throws {
        _ = try await rpc(method: "delete_session", params: ["session_id": id])
    }

    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage] {
        var params: [String: Any] = ["session_id": sessionId, "limit": limit]
        if let before { params["before"] = before }
        let data = try await rpc(method: "list_messages", params: params)
        guard let object = data as? [String: Any],
              let items = (object["data"] as? [[String: Any]]) ?? (object["messages"] as? [[String: Any]]) else {
            return []
        }
        return items.compactMap { item in
            guard let id = item["id"] as? String, let role = item["role"] as? String else { return nil }
            return HermesMessage(
                id: id,
                role: role,
                content: item["content"] as? String ?? "",
                createdAt: item["created_at"] as? String
            )
        }
    }

    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await rpc(method: "chat", params: ["session_id": sessionId, "message": message])
                    guard let object = data as? [String: Any],
                          let events = object["events"] as? [[String: Any]] else {
                        throw BrokerError.invalidResponse
                    }
                    for event in events {
                        continuation.yield(
                            HermesStreamEvent(
                                type: event["type"] as? String ?? "text",
                                content: event["content"] as? String,
                                name: event["name"] as? String,
                                arguments: event["arguments"] as? String,
                                summary: event["summary"] as? String
                            )
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func health() async throws -> Bool {
        _ = try await request(path: "/health", authenticated: false)
        return true
    }

    func createEnrollmentURL() async throws -> URL {
        let json = try await request(path: "/v1/enrollments", method: "POST")
        guard let value = json["url"] as? String, let url = URL(string: value) else {
            throw BrokerError.invalidResponse
        }
        return url
    }

    func fetchAccount() async throws -> BrokerAccount {
        let json = try await request(path: "/v1/me")
        guard let id = json["id"] as? String,
              let displayName = json["display_name"] as? String else {
            throw BrokerError.invalidResponse
        }
        return BrokerAccount(
            id: id,
            displayName: displayName,
            deviceCount: json["device_count"] as? Int ?? 0,
            rpcCount: json["rpc_count"] as? Int ?? 0
        )
    }

    func deleteDevice(id: String) async throws {
        _ = try await request(path: "/v1/devices/\(id)", method: "DELETE")
        if selectedDeviceID == id {
            selectedDeviceID = ""
            UserDefaults.standard.removeObject(forKey: BrokerDefaults.deviceIDKey)
        }
    }

    func updateDevice(id: String, name: String? = nil, endpoint: String? = nil) async throws {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let endpoint { body["endpoint"] = endpoint }
        guard !body.isEmpty else { return }
        _ = try await request(path: "/v1/devices/\(id)", method: "PUT", body: body)
    }

    func signOut() throws {
        token = ""
        selectedDeviceID = ""
        try KeychainCredentialStore().deleteToken(for: .brokerKey)
        UserDefaults.standard.removeObject(forKey: BrokerDefaults.deviceIDKey)
        UserDefaults.standard.set(AgentConnectionMode.broker.rawValue, forKey: BrokerDefaults.connectionModeKey)
    }

    private func rpc(method: String, params: [String: Any] = [:]) async throws -> Any {
        guard !selectedDeviceID.isEmpty else { throw BrokerError.deviceNotSelected }
        let json = try await request(
            path: "/v1/rpc/\(selectedDeviceID)",
            method: "POST",
            body: ["method": method, "params": params]
        )
        guard json["ok"] as? Bool == true, let data = json["data"] else {
            throw BrokerError.invalidResponse
        }
        return data
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        authenticated: Bool = true
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)\(path)") else { throw BrokerError.invalidConfiguration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 100
        if authenticated {
            guard !token.isEmpty else { throw BrokerError.invalidConfiguration }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BrokerError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let detail = json?["detail"] as? String ?? "HTTP \(http.statusCode)"
            throw BrokerError.server(detail)
        }
        if data.isEmpty { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrokerError.invalidResponse
        }
        return json
    }

    private static func parseSessions(_ data: Any) -> [HermesSession] {
        guard let object = data as? [String: Any],
              let items = (object["data"] as? [[String: Any]]) ?? (object["sessions"] as? [[String: Any]]) else {
            return []
        }
        return items.compactMap(parseSession)
    }

    private static func parseSession(_ item: [String: Any]) -> HermesSession? {
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

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

final class BrokerAgentChannel: AgentChannel, @unchecked Sendable {
    private let client = RemoteBrokerClient()

    var isConfigured: Bool {
        let url = UserDefaults.standard.string(forKey: BrokerDefaults.baseURLKey) ?? BrokerDefaults.defaultBaseURL
        let deviceID = UserDefaults.standard.string(forKey: BrokerDefaults.deviceIDKey) ?? ""
        let token = (try? KeychainCredentialStore().getToken(for: .brokerKey)) ?? ""
        return !url.isEmpty && !deviceID.isEmpty && !token.isEmpty
    }

    func loadSavedConfig() async { await client.loadSavedConfig() }
    func listSessions() async throws -> [HermesSession] { try await client.listSessions() }
    func createSession(title: String?) async throws -> HermesSession { try await client.createSession(title: title) }
    func deleteSession(id: String) async throws { try await client.deleteSession(id: id) }
    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage] {
        try await client.listMessages(sessionId: sessionId, before: before, limit: limit)
    }
    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error> {
        await client.chatStream(sessionId: sessionId, message: message)
    }
    func health() async throws -> Bool { try await client.health() }
    func configure(baseURL: String, apiKey: String) async {
        let deviceID = UserDefaults.standard.string(forKey: BrokerDefaults.deviceIDKey) ?? ""
        try? await client.configure(baseURL: baseURL, token: apiKey, deviceID: deviceID)
    }
}

final class PreferredAgentChannel: AgentChannel, @unchecked Sendable {
    private let local = HermesChannel()
    private let broker = BrokerAgentChannel()

    private var selected: any AgentChannel {
        let rawValue = UserDefaults.standard.string(forKey: BrokerDefaults.connectionModeKey) ?? AgentConnectionMode.local.rawValue
        return rawValue == AgentConnectionMode.broker.rawValue ? broker : local
    }

    var isConfigured: Bool { selected.isConfigured }
    func loadSavedConfig() async { await selected.loadSavedConfig() }
    func listSessions() async throws -> [HermesSession] { try await selected.listSessions() }
    func createSession(title: String?) async throws -> HermesSession { try await selected.createSession(title: title) }
    func deleteSession(id: String) async throws { try await selected.deleteSession(id: id) }
    func listMessages(sessionId: String, before: String?, limit: Int) async throws -> [HermesMessage] {
        try await selected.listMessages(sessionId: sessionId, before: before, limit: limit)
    }
    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error> {
        await selected.chatStream(sessionId: sessionId, message: message)
    }
    func health() async throws -> Bool { try await selected.health() }
    func configure(baseURL: String, apiKey: String) async { await selected.configure(baseURL: baseURL, apiKey: apiKey) }
}

enum BrokerError: LocalizedError {
    case invalidConfiguration
    case invalidPairingCode
    case invalidResponse
    case deviceNotSelected
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Broker 地址或密钥未配置"
        case .invalidPairingCode: return "这不是有效的 Broker 配对二维码"
        case .invalidResponse: return "Broker 返回了无法解析的数据"
        case .deviceNotSelected: return "请先选择一个 Broker 设备"
        case .server(let message): return message
        }
    }
}
