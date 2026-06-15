import SwiftUI
import WidgetKit
import Charts

// MARK: - Center Tab Mode

enum CenterTabMode: String, CaseIterable {
    case voice = "voice"
    case camera = "camera"
    case keyboard = "keyboard"

    var icon: String {
        switch self {
        case .voice: return "waveform"
        case .camera: return "camera.fill"
        case .keyboard: return "keyboard.fill"
        }
    }
}

// MARK: - 根壳层：自定义 Tab 导航

struct AppShell: View {
    let onLogout: () -> Void

    @State private var selectedTab = 0
    @State private var showDeepSeekOnboarding = false
    @AppStorage("centerTabMode") private var centerTabMode: CenterTabMode = .voice
    private let tabBarHeight: CGFloat = 70

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch selectedTab {
                case 0: TokenTab()
                case 1: AgentTab()
                case 2: CenterWorkspaceView(defaultMode: $centerTabMode)
                case 3: TeamHubView()
                case 4: SettingsTab(onLogout: onLogout)
                default: TokenTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            CustomTabBar(selectedTab: $selectedTab, centerMode: $centerTabMode)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onOpenURL { url in
            handleDeepLink(url)
        }
        .onAppear {
            let isBrokerMode = UserDefaults.standard.string(forKey: BrokerDefaults.connectionModeKey) == AgentConnectionMode.broker.rawValue
            showDeepSeekOnboarding = isBrokerMode && !KeychainCredentialStore().hasToken(for: .deepseek)
        }
        .sheet(isPresented: $showDeepSeekOnboarding) {
            TokenLoginView { token in
                try? KeychainCredentialStore().saveToken(token, for: .deepseek)
                NotificationCenter.default.post(name: .deepSeekCredentialDidChange, object: nil)
                showDeepSeekOnboarding = false
                selectedTab = 0
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "deeplink" else { return }

        // Handle configuration deep link
        if url.host == "configure" || url.pathComponents.contains("configure") {
            handleConfigurationURL(url)
            return
        }

        let target = url.host ?? ""
        let path = url.pathComponents.filter { $0 != "/" }

        switch target {
        case "token":
            selectedTab = 0
        case "agent":
            selectedTab = 1
        case "center":
            selectedTab = 2
            if let modeName = path.dropFirst().first, let mode = CenterTabMode(rawValue: modeName) {
                centerTabMode = mode
            }
        case "team":
            selectedTab = 3
        case "settings":
            selectedTab = 4
        default:
            break
        }
    }

    private func handleConfigurationURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return }

        let urlValue = queryItems.first(where: { $0.name == "url" })?.value
        let keyValue = queryItems.first(where: { $0.name == "key" })?.value

        if let url = urlValue {
            UserDefaults.standard.set(url, forKey: "hermesURL")
            UserDefaults.standard.set(AgentConnectionMode.local.rawValue, forKey: BrokerDefaults.connectionModeKey)
            Task {
                await HermesAPI.shared.configure(baseURL: url, apiKey: keyValue ?? "")
            }
        }
        if let key = keyValue, !key.isEmpty {
            try? KeychainCredentialStore().saveToken(key, for: .hermesKey)
        }

        // Switch to Agent tab to show it's connected
        selectedTab = 1
    }
}

// MARK: - Custom Tab Bar

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    @Binding var centerMode: CenterTabMode
    @State private var showCenterOptions = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                TabBarButton(icon: "dollarsign.circle", selectedIcon: "dollarsign.circle.fill", title: "Token", isSelected: selectedTab == 0) { selectedTab = 0 }
                TabBarButton(icon: "brain.head.profile", selectedIcon: "brain", title: "Agent", isSelected: selectedTab == 1) { selectedTab = 1 }

                CenterTabButton(mode: centerMode, isActive: selectedTab == 2)
                    .onTapGesture {
                        if showCenterOptions {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showCenterOptions = false }
                        } else {
                            selectedTab = 2
                        }
                    }
                    .onLongPressGesture {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { showCenterOptions = true }
                    }

                TabBarButton(icon: "person.2", selectedIcon: "person.2.fill", title: "Team", isSelected: selectedTab == 3) { selectedTab = 3 }
                TabBarButton(icon: "gearshape", selectedIcon: "gearshape.fill", title: "设置", isSelected: selectedTab == 4) { selectedTab = 4 }
            }
            .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 6)
            .background(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            if showCenterOptions {
                CenterTabOverlay(currentMode: $centerMode, isShowing: $showCenterOptions)
                    .offset(y: -55)
            }
        }
    }
}

// MARK: - Tab 按钮

struct TabBarButton: View {
    let icon: String
    let selectedIcon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? selectedIcon : icon)
                    .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
                Text(title).font(.system(size: 10, weight: isSelected ? .semibold : .regular))
            }
            .foregroundColor(isSelected ? .blue : .secondary)
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .shadow(color: .blue.opacity(0.2), radius: 8, y: 2)
                        .overlay(Capsule().stroke(Color.blue.opacity(0.15), lineWidth: 0.5))
                        .padding(.horizontal, 4).padding(.vertical, -2)
                }
            }
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
    }
}

// MARK: - Center Tab 按钮（竖线动效）

struct CenterTabButton: View {
    let mode: CenterTabMode
    let isActive: Bool
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 54, height: 54)
                .shadow(color: .blue.opacity(0.35), radius: 8, y: 4)
                .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                .offset(y: -10)
                .scaleEffect(isActive ? 1.08 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)

            Group {
                switch mode {
                case .voice:
                    HStack(spacing: 3) {
                        bar(12, pulsing: isPulsing, delay: 0)
                        bar(18, pulsing: isPulsing, delay: 0.15)
                        bar(10, pulsing: isPulsing, delay: 0.3)
                        bar(20, pulsing: isPulsing, delay: 0.1)
                        bar(14, pulsing: isPulsing, delay: 0.2)
                    }
                case .camera:
                    Image(systemName: "camera.fill").font(.system(size: 18)).foregroundColor(.white)
                case .keyboard:
                    Image(systemName: "keyboard.fill").font(.system(size: 18)).foregroundColor(.white)
                }
            }
            .offset(y: -10)

            if !isActive {
                Image(systemName: "chevron.down")
                    .font(.system(size: 6))
                    .foregroundColor(.secondary.opacity(0.5))
                    .offset(y: 18)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isPulsing.toggle()
            }
        }
    }

    private func bar(_ h: CGFloat, pulsing: Bool, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .frame(width: 3, height: pulsing ? h * 1.3 : h)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay), value: pulsing)
    }
}

// MARK: - Center Tab 液态玻璃弹出选项

struct CenterTabOverlay: View {
    @Binding var currentMode: CenterTabMode
    @Binding var isShowing: Bool

    var body: some View {
        let otherOptions = CenterTabMode.allCases.filter { $0 != currentMode }
        HStack(spacing: 16) {
            ForEach(otherOptions, id: \.self) { mode in
                GlassCircle(icon: mode.icon)
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        currentMode = mode
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isShowing = false }
                    }
            }
        }
        .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

struct GlassCircle: View {
    let icon: String

    var body: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 48, height: 48)
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .overlay(
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
            )
    }
}

// MARK: - Token Tab

struct TokenTab: View {
    @State private var summary: UserSummary?
    @State private var store = DashboardStore()
    @State private var usageAmount: UsageAmountData?
    @State private var usageCost: [UsageCostEntry]?
    @State private var token = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasAutoFetched = false
    @State private var showLoginSheet = false
    @State private var showPrinted = false
    @State private var printAnimationID: UUID?
    @State private var showUsageTab = false
    @State private var selectedModel = "DeepSeek"
    @State private var visibleDays = 14

    private let availableModels = ["DeepSeek"]
    private var savedToken: String { (try? KeychainCredentialStore().getToken(for: .deepseek)) ?? "" }
    private var hasToken: Bool { KeychainCredentialStore().hasToken(for: .deepseek) }
    private var hasHermesKey: Bool { KeychainCredentialStore().hasToken(for: .hermesKey) }
    private var currentMonth: Int { Calendar.current.component(.month, from: Date()) }
    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    balanceCard
                    quickActions
                    if summary != nil, let amount = usageAmount, !amount.dailyTokenData.isEmpty {
                        monthlyTrendChart(amount.dailyTokenData)
                    }
                    if summary != nil {
                        Toggle(isOn: $showUsageTab) {
                            Label("用量详情", systemImage: "chart.bar.fill").font(.headline)
                        }.padding(.horizontal, 4)
                        .onChange(of: showUsageTab) { _, expanded in
                            if expanded {
                                Task {
                                    await store.loadUsageDetails(month: currentMonth, year: currentYear)
                                    usageAmount = store.usageAmount
                                    usageCost = store.usageCost
                                }
                            }
                        }
                    }
                    if showUsageTab, let s = summary { usageContent(s) }
                }
                .padding(.horizontal, 16).padding(.vertical, 16).padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(availableModels, id: \.self) { model in
                            Button(action: { selectedModel = model }) {
                                HStack {
                                    Text(model)
                                    if model == selectedModel { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        Divider()
                        Text("更多模型即将支持").font(.caption).foregroundColor(.secondary)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "brain.head.profile")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(selectedModel)
                                .font(.headline)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(.primary)
                    }
                }

            }
            .onAppear {
                token = savedToken
                // 清除旧数据当 Token 被移除后
                if !hasToken { store.clear() }
                // 缓存展示由 balanceCard 兜底
                // 后台刷新
                if hasToken { refresh() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deepSeekCredentialDidChange)) { _ in
                token = savedToken
                if hasToken { refresh() }
            }
            .refreshable { await refreshData() }
            .sheet(isPresented: $showLoginSheet) {
                TokenLoginView { newToken in
                    token = newToken
                    try? KeychainCredentialStore().saveToken(newToken, for: .deepseek)
                    showLoginSheet = false; refresh()
                }
            }
            .overlay(alignment: .top) {
                PrintAnimationView(trigger: printAnimationID, summary: summary).ignoresSafeArea()
            }
            .overlay(alignment: .center) {
                if showPrinted {
                    VStack(spacing: 8) {
                        Image(systemName: "printer.fill").font(.title2)
                        Text("账单已输出到灵动岛").font(.subheadline).fontWeight(.medium)
                        Text("点击关闭").font(.caption).foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 20)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
                    .onTapGesture { withAnimation { showPrinted = false } }
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
    }

    private var balanceCard: some View {
        VStack(spacing: 16) {
            if let s = summary {
                liveBalanceView(s)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statCard(title: "本月 Token", value: formatToken(s.monthlyTokenUsage), icon: "t.circle.fill", color: .blue)
                    statCard(title: "预计可用", value: formatToken(s.totalAvailableTokenEstimation), icon: "chart.pie.fill", color: .green)
                }
            } else if !hasToken {
                VStack(spacing: 8) {
                    Image(systemName: "key.fill").font(.largeTitle).foregroundColor(.secondary)
                    Text("请先在设置中添加 Token").foregroundColor(.secondary)
                }.padding(40).frame(maxWidth: .infinity).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16))
            } else if let cached = UserDefaults.shared.savedWidgetData {
                cachedBalanceView(cached)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("正在获取数据…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }


    private func liveBalanceView(_ s: UserSummary) -> some View {
        VStack(spacing: 16) {
            if let wallet = s.normalWallets.first {
                VStack(spacing: 2) {
                    Text(formatCNY(wallet.balance)).font(.system(size: 42, weight: .bold, design: .monospaced)).foregroundColor(.white)
                    Text("可用余额").font(.caption).foregroundColor(.white.opacity(0.8))
                }
                if let bonus = s.bonusWallets.first, let b = Double(bonus.balance), b > 0 {
                    HStack {
                        Spacer()
                        Text("赠送 ¥\(bonus.balance)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                Divider().background(.white.opacity(0.3))
                VStack(spacing: 10) {
                    row("充值余额", formatCNY(wallet.balance))
                    if let bonus = s.bonusWallets.first { row("赠送余额", formatCNY(bonus.balance)) }
                    row("可调用 Token", formatToken(s.totalAvailableTokenEstimation))
                }
                Divider().background(.white.opacity(0.3))
                row("本月用量", formatToken(s.monthlyTokenUsage))
                if let cost = s.monthlyCosts.first { row("本月消费", formatCNY(cost.amount)) }
                if let d = UserDefaults.shared.savedWidgetData {
                    Divider().background(.white.opacity(0.3))
                    Text("更新于 \(d.lastUpdated.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20)).shadow(color: .blue.opacity(0.3), radius: 12, y: 4)
    }

    private func cachedBalanceView(_ cached: WidgetData) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 2) {
                Text(formatCNY(cached.balance)).font(.system(size: 42, weight: .bold, design: .monospaced)).foregroundColor(.white)
                Text("可用余额").font(.caption).foregroundColor(.white.opacity(0.8))
            }
            Text("缓存数据")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            Divider().background(.white.opacity(0.3))
            VStack(spacing: 10) {
                row("充值余额", formatCNY(cached.balance))
                row("本月用量", formatToken(cached.monthlyUsage))
                row("本月消费", cached.monthlyCost)
            }
            Divider().background(.white.opacity(0.3))
            Text("缓存数据 · 更新于 \(cached.lastUpdated.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundColor(.white.opacity(0.6))
            if isLoading {
                HStack(spacing: 4) { ProgressView().scaleEffect(0.7); Text("刷新中…").font(.caption2) }.foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(20)
        .background(LinearGradient(colors: [Color(red: 0.11, green: 0.42, blue: 0.87), Color(red: 0.04, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20)).shadow(color: .blue.opacity(0.3), radius: 12, y: 4).opacity(0.85)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            if summary != nil {
                Button(action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    if let wd = UserDefaults.shared.savedWidgetData {
                        Task { await LiveActivityManager.shared.printBill(with: wd) }
                    }
                    let id = UUID(); printAnimationID = id
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showPrinted = true }
                    Task {
                        try? await Task.sleep(for: .seconds(10))
                        guard printAnimationID == id else { return }
                        withAnimation(.easeOut(duration: 0.25)) { showPrinted = false }
                    }
                }) {
                    HStack(spacing: 6) { Image(systemName: "printer.fill"); Text("打印账单") }
                        .fontWeight(.medium).frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(.systemGray5)).foregroundColor(.primary).clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            Button(action: refresh) {
                HStack(spacing: 6) {
                    if isLoading { ProgressView().tint(.white) }
                    Image(systemName: "arrow.clockwise"); Text("刷新")
                }.fontWeight(.medium).frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color.blue).foregroundColor(.white).clipShape(RoundedRectangle(cornerRadius: 12))
            }.disabled(isLoading)
        }
    }

    private func usageContent(_ s: UserSummary) -> some View {
        VStack(spacing: 16) {
            if let cost = usageCost?.first {
                VStack(alignment: .leading, spacing: 12) {
                    Label("本月消费明细", systemImage: "chart.pie.fill").font(.headline)
                    ForEach(cost.total) { m in
                        HStack {
                            Text(m.displayName).font(.subheadline).fontWeight(.medium)
                            Spacer(); Text("¥\(String(format: "%.2f", m.totalCost))").font(.callout).fontWeight(.semibold).fontDesign(.monospaced)
                        }.padding(.vertical, 4)
                        if m.id != cost.total.last?.id { Divider() }
                    }
                    Divider()
                    HStack {
                        Text("合计").fontWeight(.medium); Spacer()
                        Text("¥\(String(format: "%.2f", cost.total.reduce(0) { $0 + $1.totalCost }))").fontWeight(.bold).fontDesign(.monospaced)
                    }
                }.padding().background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }
            if let amount = usageAmount {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Token 用量明细", systemImage: "t.circle.fill").font(.headline)
                    ForEach(amount.total) { m in
                        VStack(spacing: 6) {
                            HStack { Text(m.displayName).font(.subheadline).fontWeight(.medium); Spacer() }
                            ForEach(m.usage, id: \.type) { u in
                                HStack {
                                    Text(u.displayType).font(.caption).foregroundColor(.secondary)
                                    Spacer(); Text(formatToken(String(format: "%.0f", u.value))).font(.caption).fontDesign(.monospaced)
                                }
                            }
                        }.padding(.vertical, 6)
                        if m.id != amount.total.last?.id { Divider() }
                    }
                }.padding().background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }
            if let amount = usageAmount, !amount.dailyTokenData.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Label("每日 Token 趋势", systemImage: "chart.xyaxis.line").font(.headline)
                    Chart(amount.dailyTokenData, id: \.date) { item in
                        LineMark(x: .value("日期", item.date), y: .value("Token", item.tokens)).foregroundStyle(.blue).interpolationMethod(.catmullRom)
                        AreaMark(x: .value("日期", item.date), y: .value("Token", item.tokens))
                            .foregroundStyle(LinearGradient(colors: [.blue.opacity(0.3), .blue.opacity(0.0)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                    }
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 5)) { _ in AxisValueLabel(format: .dateTime.day()) } }
                    .chartYAxis { AxisMarks { v in if let d = v.as(Double.self) { AxisValueLabel { Text(formatTokenShort(d)) } } } }
                    .frame(height: 180)
                }.padding().background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 16)).shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }
        }
    }

    private func monthlyTrendChart(_ data: [(date: Date, tokens: Double)]) -> some View {
        let positiveData = data.filter { $0.tokens > 0 }
        let totalDays = max(positiveData.count, 1)
        let safeDays = min(visibleDays, max(3, totalDays))
        let screenWidth = UIScreen.main.bounds.width - 32
        // Each bar gets narrower as visibleDays increases (zoom effect)
        let barWidth = max(24, min(80, screenWidth / CGFloat(safeDays)))
        let chartWidth = max(screenWidth, CGFloat(positiveData.count) * barWidth)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("本月用量趋势", systemImage: "chart.bar.fill").font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Button { withAnimation { visibleDays = max(3, visibleDays - 7) } } label: {
                        Image(systemName: "minus.circle.fill").font(.caption).foregroundColor(.secondary)
                    }
                    Text("\(safeDays)天").font(.caption).foregroundColor(.secondary).frame(minWidth: 36)
                    Button { withAnimation { visibleDays = min(totalDays, visibleDays + 7) } } label: {
                        Image(systemName: "plus.circle.fill").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Chart(positiveData, id: \.date) { item in
                    BarMark(
                        x: .value("日期", item.date, unit: .day),
                        y: .value("Token", item.tokens)
                    )
                    .foregroundStyle(
                        LinearGradient(colors: [.blue.opacity(0.6), .blue.opacity(0.3)],
                                      startPoint: .top, endPoint: .bottom)
                    )
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(preset: .aligned, values: .stride(by: .day, count: max(1, safeDays / 5))) { _ in
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        if let d = v.as(Double.self) {
                            AxisValueLabel { Text(formatTokenShort(d)).font(.caption2) }
                        }
                    }
                }
                .frame(width: chartWidth, height: 180)
                // Pinch to zoom
                .gesture(
                    MagnificationGesture()
                        .onEnded { scale in
                            let newDays = min(totalDays, max(3, Int(Double(visibleDays) / scale)))
                            if newDays != visibleDays {
                                visibleDays = newDays
                            }
                        }
                )
            }
            .scrollDisabled(false)
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }

    private func refresh() {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        errorMessage = nil; isLoading = true
        Task {
            defer { isLoading = false }
            // 通过 DashboardStore 刷新（含缓存 / Widget / LiveActivity）
            summary = await store.refresh(month: currentMonth, year: currentYear)
            usageAmount = store.usageAmount
            usageCost = store.usageCost
            errorMessage = store.errorMessage
            // Auto-expand usage details when data is loaded
            if summary != nil, usageAmount != nil {
                showUsageTab = true
            }
        }
    }

    @MainActor
    private func refreshData() async {
        let t = token.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        summary = await store.refresh(month: currentMonth, year: currentYear)
        usageAmount = store.usageAmount
        usageCost = store.usageCost
        errorMessage = store.errorMessage
    }

    private func formatCNY(_ a: String) -> String { guard let v = Double(a) else { return "¥\(a)" }; return "¥\(String(format: "%.2f", v))" }
    private func formatToken(_ t: String) -> String { guard let v = Double(t) else { return t }; if v >= 1_000_000 { return String(format: "%.2fM", v / 1_000_000) }; if v >= 1_000 { return String(format: "%.1fK", v / 1_000) }; return String(format: "%.0f", v) }
    private func formatTokenShort(_ v: Double) -> String { if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }; if v >= 1_000 { return String(format: "%.0fK", v / 1_000) }; return String(format: "%.0f", v) }
    private func row(_ label: String, _ value: String) -> some View { HStack { Text(label).font(.caption).foregroundColor(.white.opacity(0.8)); Spacer(); Text(value).font(.callout).fontWeight(.semibold).foregroundColor(.white).fontDesign(.monospaced) } }
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View { VStack(spacing: 8) { Image(systemName: icon).font(.title2).foregroundColor(color); Text(value).font(.callout).fontWeight(.bold).fontDesign(.monospaced); Text(title).font(.caption2).foregroundColor(.secondary) }.padding(16).frame(maxWidth: .infinity).background(Color(.systemBackground)).clipShape(RoundedRectangle(cornerRadius: 14)).shadow(color: .black.opacity(0.04), radius: 4, y: 2) }
}

extension UsageAmountData {
    var dailyTokenData: [(date: Date, tokens: Double)] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return days.compactMap { day in
            guard let date = fmt.date(from: day.date) else { return nil }
            let total = day.data.reduce(0.0) { $0 + $1.usage.reduce(0.0) { $0 + $1.value } }
            return (date, total)
        }
    }
}
