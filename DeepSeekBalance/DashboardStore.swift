import SwiftUI

// MARK: - 仪表盘状态管理器

@MainActor
@Observable
public final class DashboardStore {
    var snapshot: DashboardSnapshot?
    var usageAmount: UsageAmountData?
    var usageCost: [UsageCostEntry]?
    var isLoading = false
    var errorMessage: String?

    private let repository = UsageRepository.shared
    private var refreshTask: Task<UserSummary?, Never>?

    public init() {}

    /// 刷新全部数据，返回 UserSummary（用于页面展示）。
    /// 取消旧请求，确认未取消后再提交 Widget 和灵动岛副作用。
    func refresh(month: Int, year: Int) async -> UserSummary? {
        refreshTask?.cancel()
        let task = Task<UserSummary?, Never> { [weak self] in
            guard let self = self else { return nil }
            self.isLoading = true
            self.errorMessage = nil
            defer { self.isLoading = false }

            let result = await self.repository.refresh(month: month, year: year)
            guard !Task.isCancelled else { return nil }

            // 确认未取消后，再提交副作用 + 更新本地状态
            self.repository.commit(result)
            self.snapshot = result.dashboard
            self.usageAmount = result.amount
            self.usageCost = result.cost
            if !result.dashboard.isAvailable {
                self.errorMessage = "数据可能已过期"
            }

            return result.summary
        }
        refreshTask = task
        return await task.value
    }

    /// 按需加载用量详情，在用户展开用量面板时调用
    func loadUsageDetails(month: Int, year: Int) async {
        guard usageAmount == nil || usageCost == nil else { return }
        let (amount, cost) = await repository.fetchUsageDetails(month: month, year: year)
        if !Task.isCancelled {
            usageAmount = amount
            usageCost = cost
        }
    }

    /// 清除所有数据
    public func clear() {
        refreshTask?.cancel()
        snapshot = nil
        usageAmount = nil
        usageCost = nil
        isLoading = false
        errorMessage = nil
        repository.clear()
    }
}
