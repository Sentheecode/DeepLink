import Foundation
import ActivityKit

// MARK: - Live Activity 属性定义

struct MonitorActivityAttributes: ActivityAttributes {
    /// 创建后不变的数据
    let displayName: String

    /// 每次刷新会变化的数据
    struct ContentState: Codable, Hashable {
        let balance: String
        let currency: String
        let monthlyUsage: String
        let monthlyCost: String
        let isAvailable: Bool
        let isPrinting: Bool
        let updatedAt: Date
    }
}
