import SwiftUI
import WidgetKit

struct SettingsTab: View {
    let onLogout: () -> Void

    @AppStorage(BrokerDefaults.connectionModeKey) private var connectionModeRawValue = AgentConnectionMode.local.rawValue
    @State private var account: BrokerAccount?
    @State private var showDebugAlert = false

    private var connectionMode: AgentConnectionMode {
        AgentConnectionMode(rawValue: connectionModeRawValue) ?? .local
    }

    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle("设置")
                .task { await loadAccount() }
        }
    }

    private var settingsList: some View {
        Form {
            // MARK: - 账户
            Section {
                HStack {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("账户")
                            .font(.body.weight(.medium))
                        Text(account?.displayName ?? "已登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)

                Button("退出登录", role: .destructive) {
                    Task {
                        let store = KeychainCredentialStore()
                        try? store.deleteToken(for: .brokerKey)
                        UserDefaults.standard.hasCompletedLogin = false
                        UserDefaults.standard.savedUserNames = []
                        await MainActor.run { onLogout() }
                    }
                }
            }

            // MARK: - Agent
            Section {
                NavigationLink(destination: AgentConnectionSettingsView()) {
                    settingsRow(icon: "point.3.connected.trianglepath.dotted", color: .blue,
                                title: "Agent 连接",
                                subtitle: connectionMode == .broker ? "云端模式" : "局域网模式")
                }
                NavigationLink(destination: ModelCredentialSettingsView()) {
                    settingsRow(icon: "key.fill", color: .orange,
                                title: "模型与凭证",
                                subtitle: "管理 DeepSeek Token 等凭证")
                }
                NavigationLink(destination: DefaultAgentSettingsView()) {
                    settingsRow(icon: "target", color: .purple,
                                title: "默认处理 Agent",
                                subtitle: "语音和拍照自动发送的 Agent")
                }
            } header: {
                settingsSectionHeader(icon: "brain.head.profile", title: "Agent")
            }

            // MARK: - 快捷工具
            Section {
                NavigationLink(destination: CenterDefaultModeSettingsView()) {
                    settingsRow(icon: "slider.horizontal.3", color: .green,
                                title: "快捷工具",
                                subtitle: "Center 按钮的默认模式")
                }
            } header: {
                settingsSectionHeader(icon: "square.grid.2x2", title: "快捷工具")
            }

            // MARK: - 数据记录
            Section {
                NavigationLink(destination: VoiceHistoryView()) {
                    settingsRow(icon: "waveform.circle.fill", color: .purple,
                                title: "语音历史",
                                subtitle: nil)
                }
                NavigationLink(destination: PhotoHistoryView()) {
                    settingsRow(icon: "camera.circle.fill", color: .mint,
                                title: "拍照历史",
                                subtitle: nil)
                }
                NavigationLink(destination: CenterMemoModeView()) {
                    settingsRow(icon: "note.text", color: .orange,
                                title: "备忘录",
                                subtitle: nil)
                }
            } header: {
                settingsSectionHeader(icon: "tray.full", title: "数据记录")
            }

            // MARK: - 应用
            Section {
                NavigationLink(destination: WidgetPreviewView()) {
                    settingsRow(icon: "square.grid.2x2", color: .indigo,
                                title: "组件与灵动岛",
                                subtitle: "桌面小组件和 Live Activity")
                }
                NavigationLink(destination: DataAndPrivacySettingsView()) {
                    settingsRow(icon: "hand.raised.fill", color: .gray,
                                title: "数据与隐私",
                                subtitle: "安全与缓存管理")
                }
                NavigationLink(destination: AboutSettingsView()) {
                    settingsRow(icon: "info.circle.fill", color: .secondary,
                                title: "关于",
                                subtitle: nil)
                }
            } header: {
                settingsSectionHeader(icon: "gearshape.2", title: "应用")
            }

            // MARK: - 调试
            Section {
                Button {
                    connectionModeRawValue = AgentConnectionMode.local.rawValue
                    UserDefaults.standard.set("http://localhost:8642", forKey: "hermesURL")
                    Task {
                        await HermesAPI.shared.configure(baseURL: "http://localhost:8642", apiKey: "")
                    }
                    showDebugAlert = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "hammer.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.orange)
                            .frame(width: 22)
                        Text("快速配置本地模式")
                            .foregroundColor(.primary)
                    }
                }
            } header: {
                settingsSectionHeader(icon: "wrench.adjustable", title: "调试")
            }
        }
        .refreshable { await loadAccount() }
        .alert("本地模式已配置完成", isPresented: $showDebugAlert) {}
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.medium))
                if let subtitle = subtitle {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func settingsSectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.none)
        }
    }

    private func loadAccount() async {
        guard KeychainCredentialStore().hasToken(for: .brokerKey) else {
            account = nil
            return
        }
        let client = RemoteBrokerClient()
        await client.loadSavedConfig()
        account = try? await client.fetchAccount()
    }
}

struct ModelCredentialSettingsView: View {
    @State private var token = ""
    @State private var showLoginSheet = false
    @State private var statusText = ""

    private var savedToken: String {
        (try? KeychainCredentialStore().getToken(for: .deepseek)) ?? ""
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("DeepSeek", value: savedToken.isEmpty ? "未连接" : "已连接")
            } footer: {
                Text("凭证仅保存在本机 Keychain。")
            }

            Section("连接") {
                Button(action: { showLoginSheet = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").font(.caption).foregroundColor(.blue)
                        Text("通过浏览器登录")
                    }
                }
                SecureField("或粘贴 API Token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存 Token", action: saveToken)
                    .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !savedToken.isEmpty {
                Section {
                    Button("移除 DeepSeek 凭证", role: .destructive, action: clearToken)
                }
            }

            if !statusText.isEmpty {
                Section { Text(statusText).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("模型与凭证")
        .sheet(isPresented: $showLoginSheet) {
            TokenLoginView { newToken in
                token = newToken
                saveToken()
                showLoginSheet = false
            }
        }
    }

    private func saveToken() {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try KeychainCredentialStore().saveToken(trimmed, for: .deepseek)
            token = ""
            statusText = "已保存"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func clearToken() {
        try? KeychainCredentialStore().deleteToken(for: .deepseek)
        UserDefaults.shared.savedWidgetData = nil
        WidgetCenter.shared.reloadAllTimelines()
        Task { LiveActivityManager.shared.end() }
        statusText = "已移除"
    }
}

struct DataAndPrivacySettingsView: View {
    @State private var statusText = ""

    var body: some View {
        Form {
            Section("安全") {
                LabeledContent("模型凭证", value: "iOS Keychain")
                LabeledContent("云端密码", value: "加盐哈希")
                LabeledContent("Agent 通信", value: "HTTPS")
            }

            Section("本机数据") {
                Button("清除余额与组件缓存") {
                    UserDefaults.shared.savedWidgetData = nil
                    WidgetCenter.shared.reloadAllTimelines()
                    statusText = "缓存已清除"
                }
                Button("结束所有灵动岛活动") {
                    LiveActivityManager.shared.end()
                    statusText = "活动已结束"
                }
            }

            if !statusText.isEmpty {
                Section { Text(statusText).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("数据与隐私")
    }
}

struct AboutSettingsView: View {
    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("应用", value: "DeepSeekBalance")
                LabeledContent("版本", value: version)
            }
            Section("支持") {
                Text("反馈问题时请勿提供 Token、密码或访问令牌。")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("关于")
    }
}

// MARK: - Default Agent Settings

struct DefaultAgentSettingsView: View {
    @AppStorage("defaultAgentID") private var defaultAgentID: String = ""

    var body: some View {
        Form {
            Section {
                if defaultAgentID == "local" || defaultAgentID.isEmpty {
                    HStack {
                        Text("Hermes Agent (本地)").foregroundColor(.primary)
                        Spacer()
                        if defaultAgentID == "local" { Image(systemName: "checkmark").foregroundColor(.blue) }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { defaultAgentID = "local" }
                }
                if defaultAgentID.isEmpty {
                    HStack {
                        Text("不启用").foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "checkmark").foregroundColor(.blue)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { }
                } else {
                    Button("不启用") { defaultAgentID = "" }
                        .foregroundColor(.red)
                }
            } header: {
                Text("默认 Agent")
            } footer: {
                Text("设置后，语音转录内容和拍照记录将自动发送到该 Agent 的「默认任务」会话中，你可以在 Agent 页查看回复。")
            }
        }
        .navigationTitle("默认处理 Agent")
    }
}
