import Foundation
import WidgetKit

// MARK: - 统一刷新结果

struct RefreshResult: Sendable {
    let dashboard: DashboardSnapshot
    let summary: UserSummary?
    let amount: UsageAmountData?
    let cost: [UsageCostEntry]?
}

// MARK: - 统一数据仓库

@MainActor
public final class UsageRepository {
    public static let shared = UsageRepository()

    private let provider = DeepSeekProvider()
    private var lastSnapshot: DashboardSnapshot?
    private var cachedSummary: UserSummary?
    private var cachedAmount: UsageAmountData?
    private var cachedCost: [UsageCostEntry]?
    private var lastSuccessfulRefresh: Date?
    private let staleThreshold: TimeInterval = 3600

    private init() {}

    /// 刷新全部数据，返回纯数据。Repository 不修改内部缓存，不提交副作用。
    /// Store 在确认任务未取消后自行调用 commit() 提交。
    func refresh(month: Int, year: Int) async -> RefreshResult {
        // 缓存够新鲜则跳过网络请求
        if let last = lastSuccessfulRefresh, Date().timeIntervalSince(last) < staleThreshold,
           let dash = lastSnapshot {
            return RefreshResult(dashboard: dash, summary: cachedSummary, amount: cachedAmount, cost: cachedCost)
        }

        do {
            let summary = try await provider.fetchSummary()
            cachedSummary = summary
            let balance = BalanceSnapshot(
                balance: summary.normalWallets.first?.balance ?? "0",
                currency: summary.normalWallets.first?.currency ?? "CNY",
                monthlyUsage: summary.monthlyTokenUsage,
                monthlyCost: String(format: "%.2f", Double(summary.monthlyCosts.first?.amount ?? "0") ?? 0),
                isAvailable: true,
                availableTokens: summary.totalAvailableTokenEstimation,
                updatedAt: Date()
            )

            let dashboard = DashboardSnapshot(
                provider: .deepseek,
                balance: balance.balance,
                currency: balance.currency,
                monthlyCost: balance.monthlyCost,
                monthlyTokens: balance.monthlyUsage,
                availableTokens: balance.availableTokens,
                isAvailable: true,
                updatedAt: balance.updatedAt
            )
            lastSnapshot = dashboard
            lastSuccessfulRefresh = Date()

            // 懒惰加载用量详情：先返回摘要数据，用量详情由调用方按需触发
            var amount: UsageAmountData? = cachedAmount
            var cost: [UsageCostEntry]? = cachedCost

            return RefreshResult(dashboard: dashboard, summary: summary, amount: amount, cost: cost)

        } catch {
            // 失败时返回上次成功快照（标记为不可用）
            if let last = lastSnapshot {
                let stale = DashboardSnapshot(
                    provider: last.provider, balance: last.balance,
                    currency: last.currency, monthlyCost: last.monthlyCost,
                    monthlyTokens: last.monthlyTokens, availableTokens: last.availableTokens,
                    isAvailable: false, updatedAt: last.updatedAt
                )
                return RefreshResult(dashboard: stale, summary: cachedSummary, amount: cachedAmount, cost: cachedCost)
            }
            let empty = makeEmptySnapshot()
            return RefreshResult(dashboard: empty, summary: nil, amount: nil, cost: nil)
        }
    }

    /// 按需加载用量详情（amount + cost），仅在用户展开用量面板时调用
    func fetchUsageDetails(month: Int, year: Int) async -> (UsageAmountData?, [UsageCostEntry]?) {
        if let usage = try? await provider.fetchUsage(month: month, year: year) {
            let amount = usage.decodeAmount()
            let cost = usage.decodeCost()
            cachedAmount = amount
            cachedCost = cost
            return (amount, cost)
        }
        return (cachedAmount, cachedCost)
    }

    /// 提交副作用：缓存 Widget 数据、更新灵动岛
    func commit(_ result: RefreshResult) {
        let data = WidgetData(
            balance: result.dashboard.balance, currency: result.dashboard.currency,
            monthlyUsage: result.dashboard.monthlyTokens, monthlyCost: result.dashboard.monthlyCost,
            lastUpdated: result.dashboard.updatedAt, isAvailable: result.dashboard.isAvailable
        )
        UserDefaults.shared.savedWidgetData = data
        WidgetCenter.shared.reloadAllTimelines()
        LiveActivityManager.shared.sync(with: data)
    }

    func clear() {
        lastSnapshot = nil
        cachedAmount = nil
        cachedCost = nil
        cachedSummary = nil
        UserDefaults.shared.savedWidgetData = nil
        WidgetCenter.shared.reloadAllTimelines()
        LiveActivityManager.shared.end()
    }

    // MARK: - Private

    private func makeEmptySnapshot() -> DashboardSnapshot {
        DashboardSnapshot(
            provider: .deepseek, balance: "0", currency: "CNY",
            monthlyCost: "0", monthlyTokens: "0", availableTokens: "0",
            isAvailable: false, updatedAt: Date()
        )
    }
}
