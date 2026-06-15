import SwiftUI
import WidgetKit

struct SettingsTab: View {
    let onLogout: () -> Void

    @State private var account: BrokerAccount?
    @State private var isLoadingAccount = false
    @State private var cachedName = UserDefaults.standard.cachedUserDisplayName

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
                        Text(account?.displayName ?? cachedName ?? (isLoadingAccount ? "加载中..." : "未登录"))
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
                        try? store.deleteToken(for: .deepseek)
                        try? store.deleteToken(for: .hermesKey)
                        UserDefaults.standard.hasCompletedLogin = false
                        UserDefaults.standard.savedUserNames = []
                        UserDefaults.standard.cachedUserDisplayName = nil
                        UserDefaults.shared.savedWidgetData = nil
                        await WidgetCenter.shared.reloadAllTimelines()
                        await MainActor.run { onLogout() }
                    }
                }
            }

            Section {
                NavigationLink(destination: AgentConnectionSettingsView()) {
                    settingsRow(icon: "network", color: .secondary, title: "连接与设备", subtitle: "云端 Channel、局域网与配对")
                }
                NavigationLink(destination: ModelCredentialSettingsView()) {
                    settingsRow(icon: "key", color: .secondary, title: "模型与凭证", subtitle: "DeepSeek 与其他模型服务")
                }
            } header: {
                Text("连接")
            }

            Section {
                NavigationLink(destination: DefaultAgentSettingsView()) {
                    settingsRow(icon: "target", color: .secondary, title: "默认 Agent", subtitle: "处理语音、图像和文字记录")
                }
                NavigationLink(destination: CenterDefaultModeSettingsView()) {
                    settingsRow(icon: "slider.horizontal.3", color: .secondary, title: "Center 默认模式", subtitle: nil)
                }
            } header: {
                Text("偏好")
            }

            Section {
                NavigationLink(destination: WidgetPreviewView()) {
                    settingsRow(icon: "square.grid.2x2", color: .secondary, title: "组件与灵动岛", subtitle: nil)
                }
                NavigationLink(destination: DataAndPrivacySettingsView()) {
                    settingsRow(icon: "hand.raised", color: .secondary, title: "数据与隐私", subtitle: nil)
                }
                NavigationLink(destination: AboutSettingsView()) {
                    settingsRow(icon: "info.circle", color: .secondary, title: "关于", subtitle: nil)
                }
            } header: {
                Text("应用")
            }
        }
        .refreshable { await loadAccount() }
    }

    private func settingsRow(icon: String, color: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
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
            isLoadingAccount = false
            return
        }
        isLoadingAccount = true
        let client = RemoteBrokerClient()
        await client.loadSavedConfig()
        account = try? await client.fetchAccount()
        if let name = account?.displayName {
            cachedName = name
            UserDefaults.standard.cachedUserDisplayName = name
        }
        isLoadingAccount = false
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
                LabeledContent("应用", value: "DeepLink")
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
