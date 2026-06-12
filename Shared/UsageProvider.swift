import Foundation

// MARK: - Data Models

public struct BalanceSnapshot: Codable, Sendable {
    public let balance: String
    public let currency: String
    public let monthlyUsage: String
    public let monthlyCost: String
    public let isAvailable: Bool
    public let availableTokens: String
    public let updatedAt: Date
}

public struct UsageSnapshot: Sendable {
    public let amount: Data?
    public let cost: Data?
    public let updatedAt: Date

    init(amount: UsageAmountData?, cost: [UsageCostEntry]?, updatedAt: Date) {
        self.amount = amount.flatMap { try? JSONEncoder().encode($0) }
        self.cost = cost.flatMap { try? JSONEncoder().encode($0) }
        self.updatedAt = updatedAt
    }

    func decodeAmount() -> UsageAmountData? {
        amount.flatMap { try? JSONDecoder().decode(UsageAmountData.self, from: $0) }
    }

    func decodeCost() -> [UsageCostEntry]? {
        cost.flatMap { try? JSONDecoder().decode([UsageCostEntry].self, from: $0) }
    }
}

// MARK: - Provider Protocol

public protocol UsageProvider: Sendable {
    func fetchBalance() async throws -> BalanceSnapshot
    func fetchUsage(month: Int, year: Int) async throws -> UsageSnapshot
}

// MARK: - Provider Errors

public enum ProviderError: LocalizedError {
    case notAuthenticated
    case tokenExpired
    case serviceUnavailable(String)
    case unknown(Error)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "未登录，请先设置 Token"
        case .tokenExpired: return "Token 已过期，请重新登录"
        case .serviceUnavailable(let msg): return msg
        case .unknown(let e): return e.localizedDescription
        }
    }
}
