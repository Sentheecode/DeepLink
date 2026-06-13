import Foundation
import ActivityKit

// MARK: - Live Activity 管理器

@available(iOS 17.0, *)
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var activity: Activity<MonitorActivityAttributes>?
    private var generation = 0 // 递增，旧 generation 的操作会被忽略

    private init() {
        activity = Activity<MonitorActivityAttributes>.activities.first
    }

    /// 同步 Live Activity（自动创建或更新）。使用 generation 避免竞态。
    func sync(with widgetData: WidgetData) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let gen = generation
        let state = makeState(from: widgetData)
        Task {
            // 如果 generation 已变，说明有更新的操作，忽略这次
            guard gen == self.generation else { return }
            if activity != nil || !Activity<MonitorActivityAttributes>.activities.isEmpty {
                await update(with: state)
            } else {
                try? await start(with: state)
            }
        }
    }

    /// 结束 Live Activity。递增 generation 使所有未完成的旧操作失效。
    func end() {
        generation += 1
        Task {
            guard let activity = activity ?? Activity<MonitorActivityAttributes>.activities.first else { return }
            let finalContent = ActivityContent(state: activity.content.state, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .immediate)
            self.activity = nil
        }
    }

    /// 打印账单：短暂显示打印状态
    func printBill(with widgetData: WidgetData) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        sync(with: widgetData)
        await update(with: makeState(from: widgetData, isPrinting: true))
        try? await Task.sleep(for: .seconds(4.2))
        guard !Task.isCancelled else { return }
        await update(with: makeState(from: widgetData))
    }

    // MARK: - Private

    private func start(with state: MonitorActivityAttributes.ContentState) async throws {
        await end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { throw LiveActivityError.notEnabled }
        let attributes = MonitorActivityAttributes(displayName: "DeepSeek")
        let initial = ActivityContent(state: state, staleDate: nil)
        activity = try Activity.request(attributes: attributes, content: initial, pushType: nil)
    }

    private func update(with state: MonitorActivityAttributes.ContentState) async {
        guard let activity = activity ?? Activity<MonitorActivityAttributes>.activities.first else { return }
        self.activity = activity
        let content = ActivityContent(state: state, staleDate: nil)
        await activity.update(content, alertConfiguration: nil)
    }

    func makeState(from widgetData: WidgetData, isPrinting: Bool = false) -> MonitorActivityAttributes.ContentState {
        MonitorActivityAttributes.ContentState(
            balance: widgetData.balance, currency: widgetData.currency,
            monthlyUsage: widgetData.monthlyUsage, monthlyCost: widgetData.monthlyCost,
            isAvailable: widgetData.isAvailable, isPrinting: isPrinting,
            updatedAt: widgetData.lastUpdated
        )
    }
}

@available(iOS 17.0, *)
enum LiveActivityError: LocalizedError {
    case notEnabled
    var errorDescription: String? { "请在设置中开启灵动岛权限" }
}
