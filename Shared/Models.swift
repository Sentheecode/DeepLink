import Foundation

// MARK: - Platform API envelope
struct BizDataWrapper<T: Codable>: Codable {
    let code: Int
    let msg: String
    let data: BizInner<T>?
}

struct BizInner<T: Codable>: Codable {
    let bizCode: Int
    let bizMsg: String
    let bizData: T

    enum CodingKeys: String, CodingKey {
        case bizCode = "biz_code"
        case bizMsg = "biz_msg"
        case bizData = "biz_data"
    }
}

// MARK: - User Summary
struct UserSummary: Codable {
    let currentToken: Int
    let monthlyUsage: String
    let totalUsage: Int
    let normalWallets: [WalletInfo]
    let bonusWallets: [WalletInfo]
    let totalAvailableTokenEstimation: String
    let monthlyCosts: [MonthlyCost]
    let monthlyTokenUsage: String

    enum CodingKeys: String, CodingKey {
        case currentToken = "current_token"
        case monthlyUsage = "monthly_usage"
        case totalUsage = "total_usage"
        case normalWallets = "normal_wallets"
        case bonusWallets = "bonus_wallets"
        case totalAvailableTokenEstimation = "total_available_token_estimation"
        case monthlyCosts = "monthly_costs"
        case monthlyTokenUsage = "monthly_token_usage"
    }
}

struct WalletInfo: Codable {
    let currency: String
    let balance: String
    let tokenEstimation: String

    enum CodingKeys: String, CodingKey {
        case currency
        case balance
        case tokenEstimation = "token_estimation"
    }
}

struct MonthlyCost: Codable {
    let currency: String
    let amount: String
}

// MARK: - Usage Amount
struct UsageAmountData: Codable {
    let total: [ModelUsageItem]
    let days: [DayUsageItem]

    enum CodingKeys: String, CodingKey {
        case total, days
    }
}

struct ModelUsageItem: Codable, Identifiable {
    let model: String
    let usage: [TokenDetail]

    var id: String { model }

    var displayName: String {
        switch model {
        case "deepseek-v4-pro": return "V4 Pro"
        case "deepseek-v4-flash": return "V4 Flash"
        case "deepseek-chat & deepseek-reasoner": return "Chat & Reasoner"
        default: return model.replacingOccurrences(of: "deepseek-", with: "").capitalized
        }
    }
}

struct TokenDetail: Codable {
    let type: String
    let amount: String?
    let typedAmount: String?

    var displayType: String {
        switch type {
        case "PROMPT_TOKEN": return "提示词"
        case "PROMPT_CACHE_HIT_TOKEN": return "缓存命中"
        case "PROMPT_CACHE_MISS_TOKEN": return "缓存未命中"
        case "RESPONSE_TOKEN": return "回复"
        case "REQUEST": return "请求次数"
        default: return type
        }
    }

    var value: Double { Double(amount ?? typedAmount ?? "0") ?? 0 }
}

struct DayUsageItem: Codable {
    let date: String
    let data: [ModelUsageItem]
}

// MARK: - Usage Cost
struct UsageCostEntry: Codable {
    let total: [CostModelItem]
    let days: [DayCostItem]
    let currency: String
}

struct CostModelItem: Codable, Identifiable {
    let model: String
    let usage: [CostDetailItem]

    var id: String { model }

    var displayName: String {
        switch model {
        case "deepseek-v4-pro": return "V4 Pro"
        case "deepseek-v4-flash": return "V4 Flash"
        case "deepseek-chat & deepseek-reasoner": return "Chat & Reasoner"
        default: return model
        }
    }

    var totalCost: Double {
        usage.reduce(0.0) { $0 + $1.amountValue }
    }
}

struct CostDetailItem: Codable {
    let type: String
    let amount: String?

    var amountValue: Double { Double(amount ?? "0") ?? 0 }

    var displayType: String {
        switch type {
        case "PROMPT_TOKEN": return "提示词"
        case "PROMPT_CACHE_HIT_TOKEN": return "缓存命中"
        case "PROMPT_CACHE_MISS_TOKEN": return "缓存未命中"
        case "RESPONSE_TOKEN": return "回复"
        case "REQUEST": return "请求次数"
        default: return type
        }
    }
}

struct DayCostItem: Codable {
    let date: String
    let data: [CostModelItem]
}

// MARK: - Cached data for widget
struct WidgetData: Codable {
    let balance: String
    let currency: String
    let monthlyUsage: String
    let monthlyCost: String
    let lastUpdated: Date
    let isAvailable: Bool
}
