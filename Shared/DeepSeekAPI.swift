import Foundation

class DeepSeekAPI {
    static let shared = DeepSeekAPI()

    private let base = "https://platform.deepseek.com"
    private let decoder = JSONDecoder()

    private func request(path: String, token: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "\(base)\(path)")!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        return req
    }

    private func decode<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        try decoder.decode(T.self, from: data)
    }

    /// 检查 HTTP 响应状态码，非 2xx 时尝试解析错误信息
    private func checkResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            // 尝试从 response body 提取错误信息
            if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let msg = body["msg"] as? String, !msg.isEmpty {
                throw APIError.platformError(code: http.statusCode, msg: msg)
            }
            throw APIError.platformError(code: http.statusCode, msg: "HTTP \(http.statusCode)")
        }
    }

    // MARK: - Platform API (requires userToken from web)

    func fetchSummary(token: String) async throws -> UserSummary {
        let (data, resp) = try await URLSession.shared.data(for: request(path: "/api/v0/users/get_user_summary", token: token))
        try checkResponse(resp, data: data)
        let wrapper = try decode(data, as: BizDataWrapper<UserSummary>.self)
        guard let inner = wrapper.data, wrapper.code == 0 else {
            throw APIError.platformError(code: wrapper.code, msg: wrapper.msg)
        }
        guard inner.bizCode == 0 else {
            throw APIError.platformError(code: inner.bizCode, msg: inner.bizMsg)
        }
        return inner.bizData
    }

    func fetchUsageAmount(token: String, month: Int, year: Int) async throws -> UsageAmountData {
        let path = "/api/v0/usage/amount?month=\(month)&year=\(year)"
        let (data, resp) = try await URLSession.shared.data(for: request(path: path, token: token))
        try checkResponse(resp, data: data)
        let wrapper = try decode(data, as: BizDataWrapper<UsageAmountData>.self)
        guard let inner = wrapper.data, wrapper.code == 0 else {
            throw APIError.platformError(code: wrapper.code, msg: wrapper.msg)
        }
        guard inner.bizCode == 0 else {
            throw APIError.platformError(code: inner.bizCode, msg: inner.bizMsg)
        }
        return inner.bizData
    }

    func fetchUsageCost(token: String, month: Int, year: Int) async throws -> [UsageCostEntry] {
        let path = "/api/v0/usage/cost?month=\(month)&year=\(year)"
        let (data, resp) = try await URLSession.shared.data(for: request(path: path, token: token))
        try checkResponse(resp, data: data)
        let wrapper = try decode(data, as: BizDataWrapper<[UsageCostEntry]>.self)
        guard let inner = wrapper.data, wrapper.code == 0 else {
            throw APIError.platformError(code: wrapper.code, msg: wrapper.msg)
        }
        guard inner.bizCode == 0 else {
            throw APIError.platformError(code: inner.bizCode, msg: inner.bizMsg)
        }
        return inner.bizData
    }
}

enum APIError: LocalizedError {
    case platformError(code: Int, msg: String)

    var errorDescription: String? {
        switch self {
        case .platformError(let code, let msg):
            return msg.isEmpty ? "平台错误 (\(code))" : msg
        }
    }
}
