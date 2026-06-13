import SwiftUI

// Local preview models (mirrors widget types, kept separate to avoid cross-target dependency)
struct PreviewBalanceEntry {
    let balance: String
    let currency: String
    let monthlyUsage: String
    let monthlyCost: String
    let isAvailable: Bool
}

struct PreviewLiveActivityState {
    let balance: String
    let currency: String
    let monthlyUsage: String
    let monthlyCost: String
    let isAvailable: Bool
    let isPrinting: Bool
}

// MARK: - Widget Preview (Settings)

struct WidgetPreviewView: View {
    @State private var instructionsTitle = ""
    @State private var instructionsMessage = ""
    @State private var showInstructions = false
    @State private var liveActivityStatus = ""

    private let entry = PreviewBalanceEntry(
        balance: "82.93", currency: "CNY",
        monthlyUsage: "779M", monthlyCost: "¥36.33",
        isAvailable: true
    )
    private let liveState = PreviewLiveActivityState(
        balance: "82.93", currency: "CNY",
        monthlyUsage: "779000000", monthlyCost: "36.33",
        isAvailable: true, isPrinting: false
    )

    var body: some View {
        List {
            Section("桌面插件（中号）") {
                PreviewDashboardWidget(entry: entry)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets())

                Button("添加到桌面") {
                    instructionsTitle = "添加桌面组件"
                    instructionsMessage = "回到主屏幕，长按空白处，点击左上角“+”，搜索 DeepLink，然后选择组件尺寸并添加。"
                    showInstructions = true
                }
            }

            Section("锁屏插件") {
                PreviewAccessoryView(entry: entry)
                    .frame(height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets())

                Button("添加锁屏插件") {
                    instructionsTitle = "添加锁屏组件"
                    instructionsMessage = "锁屏后长按屏幕，点击“自定”并选择锁定屏幕，然后点击组件区域，搜索 DeepLink 并添加。"
                    showInstructions = true
                }
            }

            Section("灵动岛") {
                PreviewLiveActivityView(state: liveState)
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets())

                Text("余额变动或打印账单时，灵动岛会自动显示。")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("测试灵动岛") {
                    let data = UserDefaults.shared.savedWidgetData ?? WidgetData(
                        balance: "0",
                        currency: "CNY",
                        monthlyUsage: "0",
                        monthlyCost: "0",
                        lastUpdated: Date(),
                        isAvailable: false
                    )
                    Task {
                        await LiveActivityManager.shared.printBill(with: data)
                        liveActivityStatus = "测试已发送；若未出现，请检查系统是否允许实时活动。"
                    }
                }

                if !liveActivityStatus.isEmpty {
                    Text(liveActivityStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("快捷入口") {
                LabeledContent("Token") { Text("deepseekbalance://token").foregroundColor(.secondary) }
                LabeledContent("Agent") { Text("deepseekbalance://agent").foregroundColor(.secondary) }
                LabeledContent("快捷工具") { Text("deepseekbalance://center/voice").foregroundColor(.secondary) }
            }
        }
        .navigationTitle("组件与快捷入口")
        .alert(instructionsTitle, isPresented: $showInstructions) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(instructionsMessage)
        }
    }
}

// MARK: - Preview Dashboard Widget

struct PreviewDashboardWidget: View {
    let entry: PreviewBalanceEntry

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "brain.head.profile")
                    .font(.caption).foregroundColor(.white).padding(6)
                    .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("DeepSeek").font(.headline)
                    Text("¥\(entry.balance)")
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.bold)
                }
                Spacer()
                if entry.isAvailable {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                }
            }

            HStack(spacing: 8) {
                ShortcutLinkPreview(title: "Token", icon: "dollarsign.circle.fill")
                ShortcutLinkPreview(title: "Agent", icon: "brain.head.profile")
                ShortcutLinkPreview(title: "快捷工具", icon: "waveform")
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
    }
}

struct ShortcutLinkPreview: View {
    let title: String
    let icon: String

    var body: some View {
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

// MARK: - Preview Accessory View

struct PreviewAccessoryView: View {
    let entry: PreviewBalanceEntry

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(entry.isAvailable ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: entry.isAvailable ? "checkmark" : "xmark")
                        .foregroundColor(entry.isAvailable ? .green : .red)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("DeepSeek 余额")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("¥\(entry.balance)")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.bold)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview Live Activity

struct PreviewLiveActivityView: View {
    let state: PreviewLiveActivityState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.title2).foregroundColor(.white).padding(8)
                .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("DeepSeek").font(.headline)
                    Spacer()
                    Circle().fill(state.isAvailable ? Color.green : Color.red).frame(width: 8, height: 8)
                }
                Text("余额 ¥\(state.balance)")
                    .font(.subheadline).fontWeight(.bold).fontDesign(.monospaced)
                Text("本月 Token \(state.monthlyUsage) · 消费 \(state.monthlyCost)")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }
}
