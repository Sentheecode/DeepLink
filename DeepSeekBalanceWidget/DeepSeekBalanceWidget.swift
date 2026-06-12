import SwiftUI
import WidgetKit

// MARK: - Entry

struct BalanceEntry: TimelineEntry {
    let date: Date
    let balance: String?
    let currency: String?
    let monthlyUsage: String?
    let monthlyCost: String?
    let isAvailable: Bool?
}

// MARK: - Provider

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(
            date: Date(),
            balance: "82.93",
            currency: "CNY",
            monthlyUsage: "779M",
            monthlyCost: "¥36.33",
            isAvailable: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        completion(buildEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        let entry = buildEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func buildEntry() -> BalanceEntry {
        let data = UserDefaults.shared.savedWidgetData
        return BalanceEntry(
            date: data?.lastUpdated ?? Date(),
            balance: data?.balance,
            currency: data?.currency,
            monthlyUsage: data?.monthlyUsage,
            monthlyCost: data?.monthlyCost,
            isAvailable: data?.isAvailable
        )
    }
}

// MARK: - Widgets

struct DeepSeekBalanceWidgetMedium: Widget {
    let kind = "DeepSeekBalanceWidgetMedium"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DashboardWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("DeepSeek Dashboard")
        .description("余额与三个直达入口")
        .supportedFamilies([.systemMedium])
    }
}

struct DeepSeekBalanceWidgetSmall: Widget {
    let kind = "DeepSeekBalanceWidgetSmall"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            SmallWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("DeepSeek 余额概览")
        .description("快速查看总余额")
        .supportedFamilies([.systemSmall])
    }
}

struct DeepSeekBalanceWidgetLarge: Widget {
    let kind = "DeepSeekBalanceWidgetLarge"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            LargeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("DeepSeek 完整面板")
        .description("余额、用量和消费汇总")
        .supportedFamilies([.systemLarge])
    }
}

struct DeepSeekBalanceWidgetAccessory: Widget {
    let kind = "DeepSeekBalanceWidgetAccessory"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            AccessoryView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("DeepSeek 锁屏")
        .description("锁屏查看余额")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Formatting

func formatBalance(_ balance: String, currency: String) -> String {
    guard let value = Double(balance) else { return "\(balance) \(currency)" }
    if currency == "CNY" {
        return "¥\(String(format: "%.2f", value))"
    }
    return String(format: "%.2f %@", value, currency)
}

func formatCost(_ cost: String) -> String {
    if let val = Double(cost) {
        return "¥\(String(format: "%.2f", val))"
    }
    return cost.hasPrefix("¥") ? cost : "¥\(cost)"
}

func formatToken(_ token: String) -> String {
    guard let val = Double(token) else { return token }
    if val >= 1_000_000 { return String(format: "%.2fM", val / 1_000_000) }
    if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
    return String(format: "%.0f", val)
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: BalanceEntry

    var body: some View {
        if let balance = entry.balance, let currency = entry.currency {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption).foregroundColor(.white).padding(6)
                            .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("DeepSeek").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                        Spacer()
                        Circle().fill(entry.isAvailable == true ? Color.green : .red).frame(width: 8, height: 8)
                    }
                    Spacer()
                    Text(formatBalance(balance, currency: currency))
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.6)
                }
                .padding(.leading, 16).padding(.vertical, 14)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("本月用量")
                        .font(.caption2).foregroundColor(.secondary)
                    if let usage = entry.monthlyUsage {
                        Text(formatToken(usage))
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                    }
                    Text("Token")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding(.trailing, 16).padding(.vertical, 14)
            }
        } else {
            EmptyStateView(icon: "brain.head.profile", message: "打开 App 查询余额")
        }
    }
}

// MARK: - Dashboard Widget

struct DashboardWidgetView: View {
    let entry: BalanceEntry

    private var tokenURL: URL { URL(string: "deepseekbalance://token")! }
    private var agentURL: URL { URL(string: "deepseekbalance://agent")! }
    private var centerURL: URL { URL(string: "deepseekbalance://center/voice")! }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeepSeek").font(.headline)
                    if let balance = entry.balance, let currency = entry.currency {
                        Text(formatBalance(balance, currency: currency))
                            .font(.system(.title3, design: .monospaced))
                            .fontWeight(.bold)
                    } else {
                        Text("暂无数据").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if entry.isAvailable == true {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.orange)
                }
            }

            HStack(spacing: 8) {
                ShortcutLink(title: "Token", icon: "dollarsign.circle.fill", url: tokenURL)
                ShortcutLink(title: "Agent", icon: "brain.head.profile", url: agentURL)
                ShortcutLink(title: "Center", icon: "waveform", url: centerURL)
            }
        }
        .padding(12)
    }
}

struct ShortcutLink: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: BalanceEntry

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(entry.isAvailable == true ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: entry.isAvailable == true ? "checkmark" : "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(entry.isAvailable == true ? .green : .red)
            }
            if let balance = entry.balance, let currency = entry.currency {
                Text(formatBalance(balance, currency: currency))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
                    .multilineTextAlignment(.center)
                Text("余额").font(.caption2).foregroundColor(.secondary)
            } else {
                Text("--").font(.system(size: 28, weight: .bold, design: .monospaced)).foregroundColor(.secondary)
                Text("暂无数据").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Large Widget

struct LargeWidgetView: View {
    let entry: BalanceEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "brain.head.profile")
                    .font(.caption).foregroundColor(.white).padding(6)
                    .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("DeepSeek").font(.headline)
                    if let b = entry.balance, let c = entry.currency {
                        Text(formatBalance(b, currency: c)).font(.system(.title2, design: .monospaced)).fontWeight(.bold)
                    }
                }
                Spacer()
                Circle().fill(entry.isAvailable == true ? Color.green : .red).frame(width: 8, height: 8)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            Divider().padding(.horizontal, 12)

            VStack(spacing: 0) {
                if let usage = entry.monthlyUsage {
                    HStack {
                        Label("本月 Token", systemImage: "t.circle.fill").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text(formatToken(usage)).font(.subheadline).fontWeight(.semibold).fontDesign(.monospaced)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
                if let cost = entry.monthlyCost {
                    Divider().padding(.horizontal, 12)
                    HStack {
                        Label("本月消费", systemImage: "chart.line.uptrend.xyaxis").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text(formatCost(cost)).font(.subheadline).fontWeight(.semibold).fontDesign(.monospaced)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }

            Spacer(minLength: 0)
            HStack {
                Spacer()
                Text("更新于 \(entry.date.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
    }
}

// MARK: - Accessory Widgets

struct AccessoryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BalanceEntry

    var body: some View {
        switch family {
        case .accessoryCircular: accessoryCircular
        case .accessoryRectangular: accessoryRectangular
        case .accessoryInline: accessoryInline
        default: EmptyView()
        }
    }

    private var accessoryCircular: some View {
        let value = Double(entry.balance ?? "0") ?? 0
        return Gauge(value: 0.85) {
            Text("DS").font(.system(size: 7, weight: .medium))
        } currentValueLabel: {
            VStack(spacing: -1) {
                Text("¥").font(.system(size: 6, weight: .regular))
                Text("\(Int(value))").font(.system(size: 9, weight: .bold)).minimumScaleFactor(0.4)
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(entry.isAvailable == true ? .green : .red)
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: "brain.head.profile").font(.system(size: 9))
                Text("DeepSeek").font(.system(size: 12, weight: .semibold))
                Spacer()
                Circle().fill(entry.isAvailable == true ? Color.green : .red).frame(width: 6, height: 6)
            }
            if let b = entry.balance, let c = entry.currency {
                Text(formatBalance(b, currency: c)).font(.system(size: 14, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.5)
            } else {
                Text("打开 App").font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let usage = entry.monthlyUsage {
                HStack(spacing: 2) {
                    Text("月").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(formatToken(usage)).font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
            }
        }
    }

    private var accessoryInline: some View {
        if let b = entry.balance, let c = entry.currency {
            Text("DS \(formatBalance(b, currency: c))")
        } else {
            Text("DeepSeek: --")
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle).foregroundColor(.secondary)
            Text(message).font(.caption).foregroundColor(.secondary)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
