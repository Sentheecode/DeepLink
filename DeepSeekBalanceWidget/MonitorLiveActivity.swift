import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Live Activity Widget

struct MonitorLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MonitorActivityAttributes.self) { context in
            // 锁屏/通知中心显示的完整卡片
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color(.systemGray6))
        } dynamicIsland: { context in
            DynamicIsland {
                // 展开状态（长按）
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(
                            LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87),
                                                    Color(red: 0.04, green: 0.2, blue: 0.5)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 2) {
                        Image(systemName: context.state.isPrinting ? "printer.fill" : "circle.fill")
                            .font(.caption2)
                            .foregroundColor(context.state.isPrinting ? .white : (context.state.isAvailable ? .green : .red))
                        Text(context.state.isPrinting ? "打印中" : (context.state.isAvailable ? "正常" : "异常"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.isPrinting ? "printer.fill" : "brain.head.profile")
                    .font(.caption)
                    .foregroundColor(.white)
            } compactTrailing: {
                Text(context.state.isPrinting ? "打印" : formatCompact(context.state))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
            } minimal: {
                Circle()
                    .fill(context.state.isAvailable ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }
        }
    }

    private func formatCompact(_ state: MonitorActivityAttributes.ContentState) -> String {
        guard let val = Double(state.balance) else { return "¥0" }
        return "¥\(Int(val))"
    }
}

// MARK: - 锁屏视图

struct LockScreenView: View {
    let state: MonitorActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2)
                .foregroundColor(.white)
                .padding(8)
                .background(
                    LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87),
                                            Color(red: 0.04, green: 0.2, blue: 0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("DeepSeek")
                        .font(.headline)
                    Spacer()
                    Circle()
                        .fill(state.isAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                Text("余额 \(formatBalance(state.balance, currency: state.currency))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                Text("本月 Token \(formatToken(state.monthlyUsage)) · 消费 \(formatCost(state.monthlyCost))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("更新于 \(state.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func formatBalance(_ balance: String, currency: String) -> String {
        guard let val = Double(balance) else { return "\(balance) \(currency)" }
        return "¥\(String(format: "%.2f", val))"
    }

    private func formatToken(_ token: String) -> String {
        guard let val = Double(token) else { return token }
        if val >= 1_000_000 { return String(format: "%.2fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
        return String(format: "%.0f", val)
    }

    private func formatCost(_ cost: String) -> String {
        guard let val = Double(cost) else { return "¥\(cost)" }
        return "¥\(String(format: "%.2f", val))"
    }
}

// MARK: - 灵动岛展开视图

struct ExpandedView: View {
    let state: MonitorActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label("余额", systemImage: "dollarsign.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatBalance(state.balance, currency: state.currency))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
            }

            Divider().frame(height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Label("本月 Token", systemImage: "t.circle")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatToken(state.monthlyUsage))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.bold)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if state.isPrinting {
                Label("打印中", systemImage: "printer.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private func formatBalance(_ balance: String, currency: String) -> String {
        guard let val = Double(balance) else { return "\(balance) \(currency)" }
        return "¥\(String(format: "%.2f", val))"
    }

    private func formatToken(_ token: String) -> String {
        guard let val = Double(token) else { return token }
        if val >= 1_000_000 { return String(format: "%.2fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
        return String(format: "%.0f", val)
    }
}
