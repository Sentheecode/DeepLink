import SwiftUI
import WidgetKit
import Charts
import UniformTypeIdentifiers
import CoreTransferable

struct ContentView: View {
    @State private var token = ""
    @State private var summary: UserSummary?
    @State private var store = DashboardStore()
    @State private var hasAutoFetched = false
    @State private var selectedTab = 0
    @State private var showLoginSheet = false
    @State private var showPrinted = false
    @State private var printAnimationID: UUID?

    private var savedToken: String { (try? KeychainCredentialStore().getToken(for: .deepseek)) ?? "" }
    private var hasToken: Bool { KeychainCredentialStore().hasToken(for: .deepseek) }

    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerView
                Picker("", selection: $selectedTab) {
                    Text("余额").tag(0)
                    Text("用量").tag(1)
                    Text("设置").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView {
                    VStack(spacing: 16) {
                        switch selectedTab {
                        case 0: balanceTab
                        case 1: usageTab
                        case 2: settingsTab
                        default: EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
                }
                .background(Color(.systemGroupedBackground))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))

        }
        .onAppear {
            try? KeychainCredentialStore().migrateLegacyTokenIfNeeded(for: .deepseek)
            if !hasAutoFetched, hasToken {
                    hasAutoFetched = true
                    token = savedToken
                    refresh()
                }
            }
            .refreshable { await refreshData() }
            .sheet(isPresented: $showLoginSheet) {
                TokenLoginView { newToken in
                    token = newToken
                    try? KeychainCredentialStore().saveToken(newToken, for: .deepseek)
                    showLoginSheet = false
                    refresh()
                }
            }
            .overlay(alignment: .bottom) {
                if showPrinted {
                    HStack(spacing: 8) {
                        Image(systemName: "printer.fill")
                            .font(.caption)
                        Text("账单已输出到灵动岛")
                            .font(.subheadline).fontWeight(.medium)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                    .padding(.bottom, 30)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87),
                                        Color(red: 0.04, green: 0.2, blue: 0.5)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("DeepSeek")
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.bold)
                Text("API 用量监控")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if hasToken {
                HStack(spacing: 4) {
                    Circle()
                        .fill(summary != nil ? Color.green : .gray)
                        .frame(width: 8, height: 8)
                    Text(summary != nil ? "已连接" : "未查询")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    // MARK: - Balance Tab

    private var balanceTab: some View {
        Group {
            if let s = summary {
                // Balance card
                VStack(spacing: 16) {
                    if let wallet = s.normalWallets.first {
                        VStack(spacing: 2) {
                            Text(formatCNY(wallet.balance))
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                            Text("可用余额")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        HStack(spacing: 8) {
                            statusBadge(icon: "checkmark", text: "API 可用", color: .green)
                            if let bonus = s.bonusWallets.first, let b = Double(bonus.balance), b > 0 {
                                statusBadge(icon: "gift.fill", text: "赠送 ¥\(bonus.balance)", color: .orange)
                            }
                        }
                        Divider().background(.white.opacity(0.3))

                        VStack(spacing: 10) {
                            row("充值余额", formatCNY(wallet.balance))
                            if let bonus = s.bonusWallets.first {
                                row("赠送余额", formatCNY(bonus.balance))
                            }
                            row("可调用 Token", formatToken(s.totalAvailableTokenEstimation))
                        }

                        Divider().background(.white.opacity(0.3))
                        row("本月用量", formatToken(s.monthlyTokenUsage))
                        if let cost = s.monthlyCosts.first {
                            row("本月消费", formatCNY(cost.amount))
                        }

                        if let data = UserDefaults.shared.savedWidgetData {
                            Divider().background(.white.opacity(0.3))
                            Text("更新于 \(data.lastUpdated.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(20)
                .background {
                    LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87),
                                            Color(red: 0.04, green: 0.2, blue: 0.5)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: .blue.opacity(0.3), radius: 12, y: 4)

                // Quick stats
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(title: "本月 Token", value: formatToken(s.monthlyTokenUsage), icon: "t.circle.fill", color: .blue)
                    statCard(title: "预计可用", value: formatToken(s.totalAvailableTokenEstimation), icon: "chart.pie.fill", color: .green)
                }
            }

            if summary != nil {
                Button(action: printBill) {
                    HStack(spacing: 6) {
                        Image(systemName: "printer.fill")
                        Text("打印账单")
                    }
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Button(action: refresh) {
                HStack(spacing: 6) {
                    if store.isLoading { ProgressView().tint(.white) }
                    Image(systemName: "arrow.clockwise")
                    Text("刷新")
                }
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(store.isLoading)

            if let error = store.errorMessage {
                errorBanner(error)
            }

            if !hasToken {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill").font(.largeTitle).foregroundColor(.secondary)
                    Text("请先在设置中添加 Web Token")
                        .foregroundColor(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Chart Data

    private var dailyTokenData: [(date: Date, tokens: Double)] {
        guard let days = store.usageAmount?.days else { return [] }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return days.compactMap { day in
            guard let date = fmt.date(from: day.date) else { return nil }
            let total = day.data.reduce(0.0) { sum, model in
                sum + model.usage.reduce(0.0) { $0 + $1.value }
            }
            return (date, total)
        }
    }

    @State private var selectedTokenModel: String?

    struct TokenBreakdown: Identifiable {
        let model: String
        let type: String
        let tokens: Double
        var id: String { "\(model)-\(type)" }
    }

    private var modelCostData: [(model: String, cost: Double)] {
        guard let total = store.usageCost?.first?.total else { return [] }
        return total.map { ($0.displayName, $0.totalCost) }
    }

    // MARK: - Model Ordering
    @AppStorage("modelOrder", store: UserDefaults.shared) private var modelOrderData: Data = {
        try! JSONEncoder().encode(["V4 Pro", "V4 Flash", "Chat & Reasoner"])
    }()

    private var modelOrder: [String] {
        (try? JSONDecoder().decode([String].self, from: modelOrderData)) ?? ["V4 Pro", "V4 Flash", "Chat & Reasoner"]
    }

    @State private var isReorderMode = false

    private func sortedModels<T>(_ items: [T], nameKey: (T) -> String) -> [T] {
        let order = modelOrder
        return items.sorted { a, b in
            let ai = order.firstIndex(of: nameKey(a)) ?? Int.max
            let bi = order.firstIndex(of: nameKey(b)) ?? Int.max
            return ai < bi
        }
    }

    private func saveOrder(_ names: [String]) {
        modelOrderData = (try? JSONEncoder().encode(names)) ?? modelOrderData
    }

    // MARK: - Usage Section Reordering

    private enum UsageSection: String, Codable, CaseIterable {
        case tokenTrend = "每日 Token 趋势"
        case tokenBreakdown = "Token 类型分布"
        case costDetail = "本月消费明细"
        case tokenDetail = "Token 用量"

        var icon: String {
            switch self {
            case .tokenTrend: return "chart.xyaxis.line"
            case .tokenBreakdown: return "chart.bar.stack.fill"
            case .costDetail: return "chart.pie.fill"
            case .tokenDetail: return "t.circle.fill"
            }
        }
    }

    @AppStorage("sectionOrder", store: UserDefaults.shared) private var sectionOrderData: Data = {
        try! JSONEncoder().encode(UsageSection.allCases.map { $0.rawValue })
    }()

    private var sectionOrder: [UsageSection] {
        guard let names = try? JSONDecoder().decode([String].self, from: sectionOrderData) else {
            return UsageSection.allCases
        }
        return names.compactMap { UsageSection(rawValue: $0) } + UsageSection.allCases.filter { !names.contains($0.rawValue) }
    }

    @State private var draggingSection: UsageSection?

    private func usageSectionView(_ section: UsageSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            switch section {
            case .tokenTrend:
                if !dailyTokenData.isEmpty {
                    Label(section.rawValue, systemImage: section.icon).font(.headline)
                    Chart(dailyTokenData, id: \.date) { item in
                        LineMark(x: .value("日期", item.date), y: .value("Token", item.tokens)).foregroundStyle(.blue).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("日期", item.date), y: .value("Token", item.tokens))
                            .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .chartYAxis { AxisMarks { value in if let d = value.as(Double.self) { AxisValueLabel { Text(formatTokenShort(d)) } } } }
                    .frame(height: 180)
                }

            case .tokenBreakdown:
                if let amount = store.usageAmount, !amount.total.isEmpty {
                    Label(section.rawValue, systemImage: section.icon).font(.headline)
                    let breakdownData = amount.total.flatMap { model -> [TokenBreakdown] in
                        model.usage.filter { $0.type != "REQUEST" }.map { TokenBreakdown(model: model.displayName, type: $0.displayType, tokens: $0.value) }
                    }
                    Chart(breakdownData) { item in
                        BarMark(x: .value("模型", item.model), y: .value("Token", item.tokens))
                            .foregroundStyle(by: .value("类型", item.type)).cornerRadius(3)
                    }
                    .chartForegroundStyleScale(["提示词": .blue, "缓存命中": .green, "缓存未命中": .orange, "回复": .purple])
                    .chartYAxis { AxisMarks { value in if let d = value.as(Double.self) { AxisValueLabel { Text(formatTokenShort(d)) } } } }
                    .frame(height: 180)
                }

            case .costDetail:
                if let cost = store.usageCost?.first {
                    Label(section.rawValue, systemImage: section.icon).font(.headline)
                    ForEach(cost.total) { model in
                        HStack {
                            Text(model.displayName).font(.subheadline).fontWeight(.medium)
                            Spacer()
                            Text("¥\(String(format: "%.2f", model.totalCost))").font(.callout).fontWeight(.semibold).fontDesign(.monospaced)
                        }
                        .padding(.vertical, 4)
                        if model.id != cost.total.last?.id { Divider() }
                    }
                    Divider()
                    HStack {
                        Text("合计").fontWeight(.medium)
                        Spacer()
                        Text("¥\(String(format: "%.2f", cost.total.reduce(0) { $0 + $1.totalCost }))").fontWeight(.bold).fontDesign(.monospaced)
                    }
                }

            case .tokenDetail:
                if let amount = store.usageAmount {
                    Label(section.rawValue, systemImage: section.icon).font(.headline)
                    ForEach(amount.total) { model in
                        VStack(spacing: 6) {
                            HStack { Text(model.displayName).font(.subheadline).fontWeight(.medium); Spacer() }
                            ForEach(model.usage, id: \.type) { usage in
                                HStack {
                                    Text(usage.displayType).font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatToken(String(format: "%.0f", usage.value))).font(.caption).fontDesign(.monospaced)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        if model.id != amount.total.last?.id { Divider() }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private var usageTab: some View {
        Group {
            if !store.isLoading, summary != nil, store.usageAmount == nil {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill").font(.largeTitle).foregroundColor(.secondary)
                    Text("加载用量详情中…").foregroundColor(.secondary)
                }
                .padding(40).frame(maxWidth: .infinity)
            }

            ForEach(Array(sectionOrder.enumerated()), id: \.element) { index, section in
                usageSectionView(section)
                    .opacity(draggingSection == section ? 0.5 : 1)
                    .onDrag {
                        draggingSection = section
                        return NSItemProvider(object: section.rawValue as NSString)
                    }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        defer { draggingSection = nil }
                        providers.first?.loadObject(ofClass: NSString.self) { name, _ in
                            if let name = name as? String,
                               let fromSection = UsageSection(rawValue: name as String),
                               let from = sectionOrder.firstIndex(of: fromSection) {
                                var newOrder = sectionOrder.map(\.rawValue)
                                newOrder.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
                                DispatchQueue.main.async {
                                    sectionOrderData = (try? JSONEncoder().encode(newOrder)) ?? sectionOrderData
                                }
                            }
                        }
                        return true
                    }
            }
        }
    }

    // MARK: - Settings Tab

    private var settingsTab: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Web Token", systemImage: "person.fill")
                    .font(.headline)

                // 手动粘贴 Token
                SecureField("粘贴 Token 到这里…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                HStack(spacing: 10) {
                    Button("保存") {
                        let t = token.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        try? KeychainCredentialStore().saveToken(t, for: .deepseek)
                        refresh()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)

                    Button("从浏览器获取") { showLoginSheet = true }
                        .buttonStyle(.bordered)
                }

                if !hasToken {
                    Label("尚未设置 Token", systemImage: "exclamationmark.circle")
                        .font(.subheadline).foregroundColor(.orange)
                } else {
                    Label("Token 已就绪", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundColor(.green)

                    Text("前20位: \(savedToken.prefix(20))…")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button("清除并重试", role: .destructive) {
                        token = ""
                        try? KeychainCredentialStore().deleteToken(for: .deepseek)
                        UserDefaults.shared.savedUserToken = nil
                        store.clear()
                        summary = nil
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)

            VStack(alignment: .leading, spacing: 12) {
                Label("关于", systemImage: "info.circle.fill")
                    .font(.headline)
                HStack {
                    Text("版本")
                    Spacer()
                    Text("2.0").foregroundColor(.secondary)
                }
                HStack {
                    Text("数据来源")
                    Spacer()
                    Text("DeepSeek Platform").foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    // MARK: - Helpers

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.callout)
                .fontWeight(.bold)
                .fontDesign(.monospaced)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
            Text(msg).font(.caption).foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption.weight(.bold))
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(color.opacity(0.25))
        .clipShape(Capsule())
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.8))
            Spacer()
            Text(value).font(.callout).fontWeight(.semibold)
                .foregroundColor(.white).fontDesign(.monospaced)
        }
    }

    private func formatCNY(_ amount: String) -> String {
        guard let val = Double(amount) else { return "¥\(amount)" }
        return "¥\(String(format: "%.2f", val))"
    }

    private func formatToken(_ token: String) -> String {
        guard let val = Double(token) else { return token }
        if val >= 1_000_000 { return String(format: "%.2fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.1fK", val / 1_000) }
        return String(format: "%.0f", val)
    }

    private func formatTokenShort(_ val: Double) -> String {
        if val >= 1_000_000 { return String(format: "%.1fM", val / 1_000_000) }
        if val >= 1_000 { return String(format: "%.0fK", val / 1_000) }
        return String(format: "%.0f", val)
    }

    private func formatCNYShort(_ val: Double) -> String {
        "¥\(String(format: "%.1f", val))"
    }

    // MARK: - Data

    private func printBill() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let widgetData = UserDefaults.shared.savedWidgetData {
            Task { await LiveActivityManager.shared.printBill(with: widgetData) }
        }

        let animationID = UUID()
        printAnimationID = animationID
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showPrinted = true
        }

        Task {
            try? await Task.sleep(for: .seconds(4.8))
            guard printAnimationID == animationID else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showPrinted = false
            }
        }
    }

    /// 启动统一刷新管线。
    private func refresh() {
        Task { await refreshData() }
    }

    @MainActor
    private func refreshData() async {
    	guard hasToken else { return }
    	summary = await store.refresh(month: currentMonth, year: currentYear)
    }

}
