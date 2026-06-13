import Foundation

let appGroupID = "group.com.deepseek.balance"
let widgetDataKey = "widgetData"
let userTokenKey = "userToken"
let usageAmountKey = "usageAmount"
let usageCostKey = "usageCost"

extension UserDefaults {
    static var shared: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    var savedWidgetData: WidgetData? {
        get {
            guard let data = data(forKey: widgetDataKey) else { return nil }
            return try? JSONDecoder().decode(WidgetData.self, from: data)
        }
        set {
            if let newValue = newValue {
                let data = try? JSONEncoder().encode(newValue)
                set(data, forKey: widgetDataKey)
            } else {
                removeObject(forKey: widgetDataKey)
            }
        }
    }

    var savedUserToken: String? {
        get { string(forKey: userTokenKey) }
        set { set(newValue, forKey: userTokenKey) }
    }

    var cachedUsageAmount: UsageAmountData? {
        get {
            guard let data = data(forKey: usageAmountKey) else { return nil }
            return try? JSONDecoder().decode(UsageAmountData.self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { set(data, forKey: usageAmountKey) }
            else { removeObject(forKey: usageAmountKey) }
        }
    }

    var cachedUsageCost: [UsageCostEntry]? {
        get {
            guard let data = data(forKey: usageCostKey) else { return nil }
            return try? JSONDecoder().decode([UsageCostEntry].self, from: data)
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { set(data, forKey: usageCostKey) }
            else { removeObject(forKey: usageCostKey) }
        }
    }

    var savedUserNames: [String] {
        get { stringArray(forKey: "savedUsers") ?? [] }
        set { set(newValue, forKey: "savedUsers") }
    }

    var hasCompletedSetup: Bool {
        get { bool(forKey: "hasCompletedSetup") }
        set { set(newValue, forKey: "hasCompletedSetup") }
    }

    var cachedUserDisplayName: String? {
        get { string(forKey: "cachedUserDisplayName") }
        set { set(newValue, forKey: "cachedUserDisplayName") }
    }

    var hasCompletedLogin: Bool {
        get { bool(forKey: "hasCompletedLogin") }
        set { set(newValue, forKey: "hasCompletedLogin") }
    }
}
