import SwiftUI

struct TeamHubView: View {
    @AppStorage("teamMode") private var teamModeRawValue: String = TeamMode.multiAgent.rawValue
    @State private var configuredAgents: [ConfiguredAgent] = []
    @State private var account: BrokerAccount?
    @State private var loadMessage = ""

    private var teamMode: TeamMode {
        TeamMode(rawValue: teamModeRawValue) ?? .multiAgent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("模式", selection: $teamModeRawValue) {
                    Text("多 Agent").tag(TeamMode.multiAgent.rawValue)
                    Text("多人").tag(TeamMode.multiUser.rawValue)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()

                switch teamMode {
                case .multiAgent:
                    multiAgentContent
                case .multiUser:
                    multiUserContent
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Team")
            .task { await loadServerData() }
        }
    }

    // MARK: - Multi-Agent

    private var multiAgentContent: some View {
        List {
            Section {
                if configuredAgents.isEmpty && !HermesAPI.shared.isConfigured {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("还没有 Agent")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("请先在设置中配置 Agent 连接")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } else if configuredAgents.isEmpty && HermesAPI.shared.isConfigured {
                    LocalAgentRow()
                        .listRowBackground(Color(.systemBackground))
                } else {
                    ForEach(configuredAgents) { agent in
                        AgentRow(agent: agent)
                            .listRowBackground(Color(.systemBackground))
                    }
                }
            } header: {
                Label("Agent", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.subheadline)
                    .textCase(nil)
            }

            Section {
                NavigationLink(destination: AgentConnectionSettingsView()) {
                    Label("连接管理", systemImage: "gearshape")
                }
                NavigationLink(destination: TaskAssignmentView(agents: configuredAgents)) {
                    Label("任务指派", systemImage: "checklist")
                }
            }

            if !loadMessage.isEmpty {
                Section {
                    Text(loadMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadServerData() }
    }

    // MARK: - Multi-User

    private var multiUserContent: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 46, height: 46)
                        Image(systemName: "person.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account?.displayName ?? "未登录")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text(account == nil ? "请先登录云端账号" : "已登录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Label("我的账号", systemImage: "person.circle")
                    .font(.subheadline)
                    .textCase(nil)
            }

            Section {
                Button {} label: {
                    Label("分享邀请链接", systemImage: "square.and.arrow.up")
                }
                .disabled(true)

                Text("多人团队服务尚未启用，邀请链接将在服务端接入后开放。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await loadServerData() }
    }

    private func loadServerData() async {
        guard KeychainCredentialStore().hasToken(for: .brokerKey) else {
            configuredAgents = []
            account = nil
            if !HermesAPI.shared.isConfigured {
                loadMessage = "请先在设置中配置 Agent 连接。"
            } else {
                loadMessage = ""
            }
            return
        }

        do {
            let client = RemoteBrokerClient()
            await client.loadSavedConfig()
            async let devices = client.fetchDevices()
            async let currentAccount = client.fetchAccount()
            let loadedDevices = try await devices
            configuredAgents = loadedDevices.map(ConfiguredAgent.init)
            account = try await currentAccount
            loadMessage = ""
        } catch {
            configuredAgents = []
            account = nil
            loadMessage = error.localizedDescription
        }
    }
}

// MARK: - Configured Agent Model

struct ConfiguredAgent: Identifiable {
    let id: String
    let name: String
    let type: String
    let icon: String
    var isConnected: Bool

    init(id: String, name: String, type: String, icon: String, isConnected: Bool) {
        self.id = id
        self.name = name
        self.type = type
        self.icon = icon
        self.isConnected = isConnected
    }

    init(device: AgentDevice) {
        id = device.id
        name = device.name
        type = device.kind == .brokerRelay ? "Broker Agent" : device.kind.rawValue
        icon = "point.3.connected.trianglepath.dotted"
        isConnected = device.isOnline
    }
}

// MARK: - Task Assignment View

struct TaskAssignmentView: View {
    let agents: [ConfiguredAgent]
    private let memosKey = "savedMemos"

    private var assignedMemos: [MemoItem] {
        guard let data = UserDefaults.standard.data(forKey: memosKey),
              let saved = try? JSONDecoder().decode([MemoItem].self, from: data) else {
            return []
        }
        return saved.filter { $0.assignedAgentID != nil }
    }

    var body: some View {
        List {
            let tasks = assignedMemos
            if tasks.isEmpty {
                Section("已指派的任务") {
                    Text("暂无已指派的任务。")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                ForEach(agents + [localAgentPlaceholder()], id: \.id) { agent in
                    let agentTasks = tasks.filter { $0.assignedAgentID == agent.id }
                    if !agentTasks.isEmpty {
                        Section(agent.name) {
                            ForEach(agentTasks) { task in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.text)
                                        .font(.body)
                                        .lineLimit(3)
                                    Text(task.updatedAt.formatted())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }

            Section("Agent 列表") {
                ForEach(agents) { agent in
                    HStack {
                        Circle()
                            .fill(agent.isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(agent.name)
                        Spacer()
                        let count = tasks.filter { $0.assignedAgentID == agent.id }.count
                        if count > 0 {
                            Text("\(count) 个任务")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text(agent.isConnected ? "在线" : "离线")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                // Local agent
                if HermesAPI.shared.isConfigured {
                    HStack {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                        Text("Hermes Agent")
                        Spacer()
                        let count = tasks.filter { $0.assignedAgentID == "local_hermes" }.count
                        if count > 0 {
                            Text("\(count) 个任务")
                                .font(.caption)
                                .foregroundColor(.blue)
                        } else {
                            Text("本地连接").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("任务指派")
    }

    private func localAgentPlaceholder() -> ConfiguredAgent {
        ConfiguredAgent(id: "local_hermes", name: "Hermes Agent", type: "本地连接", icon: "point.3.connected.trianglepath.dotted", isConnected: HermesAPI.shared.isConfigured)
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agent: ConfiguredAgent

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(agent.isConnected ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
                    .frame(width: 46, height: 46)
                Image(systemName: agent.icon)
                    .font(.system(size: 18))
                    .foregroundColor(agent.isConnected ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                Text(agent.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(agent.isConnected ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(agent.isConnected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 3)
                        .scaleEffect(1.4)
                )
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Local Agent Row

private struct LocalAgentRow: View {
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(HermesAPI.shared.isConfigured ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
                    .frame(width: 46, height: 46)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 18))
                    .foregroundColor(HermesAPI.shared.isConfigured ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Hermes Agent").font(.headline).fontWeight(.semibold)
                Text("本地连接").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(HermesAPI.shared.isConfigured ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(HermesAPI.shared.isConfigured ? Color.green.opacity(0.3) : Color.clear, lineWidth: 3)
                        .scaleEffect(1.4)
                )
        }
        .padding(.vertical, 2)
    }
}
