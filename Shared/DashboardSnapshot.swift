import Foundation

// MARK: - 统一仪表盘数据（不依赖特定服务商）

public struct DashboardSnapshot: Codable, Sendable {
    public let provider: ProviderID
    public let balance: String
    public let currency: String
    public let monthlyCost: String
    public let monthlyTokens: String
    public let availableTokens: String
    public let isAvailable: Bool
    public let updatedAt: Date

    // 计算属性用于排序和计算
    public var balanceDecimal: Decimal? { Decimal(string: balance) }
    public var monthlyCostDecimal: Decimal? { Decimal(string: monthlyCost) }
    public var monthlyTokensValue: Int64? { Int64(monthlyTokens) }

    public init(
        provider: ProviderID,
        balance: String,
        currency: String,
        monthlyCost: String,
        monthlyTokens: String,
        availableTokens: String,
        isAvailable: Bool,
        updatedAt: Date
    ) {
        self.provider = provider
        self.balance = balance
        self.currency = currency
        self.monthlyCost = monthlyCost
        self.monthlyTokens = monthlyTokens
        self.availableTokens = availableTokens
        self.isAvailable = isAvailable
        self.updatedAt = updatedAt
    }
}

// MARK: - 用量明细快照

public struct UsageDetailSnapshot: Codable, Sendable {
    public let models: [ModelUsageSnapshot]
    public let costs: [ModelCostSnapshot]
    public let updatedAt: Date
}

public struct ModelUsageSnapshot: Codable, Sendable, Identifiable {
    public let name: String
    public let tokens: [String: Double]

    public var id: String { name }
}

public struct ModelCostSnapshot: Codable, Sendable, Identifiable {
    public let name: String
    public let cost: Double

    public var id: String { name }
}
