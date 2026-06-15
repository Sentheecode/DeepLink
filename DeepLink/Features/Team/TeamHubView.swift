import SwiftUI

struct TeamHubView: View {
    @AppStorage("teamMode") private var teamModeRawValue: String = TeamMode.multiAgent.rawValue
    @State private var devices: [AgentDevice] = []
    @State private var account: BrokerAccount?
    @State private var loadMessage = ""
    @State private var selectedAgent: AgentInfo?
    @State private var showDeleteConfirm = false
    @State private var deletingDeviceId: String?
    @State private var errorMessage: String?

    private var teamMode: TeamMode {
        TeamMode(rawValue: teamModeRawValue) ?? .multiAgent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            .sheet(item: $selectedAgent) { agent in
                AgentDetailView(agent: agent)
            }
            .alert("删除设备", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) { deletingDeviceId = nil }
                Button("删除", role: .destructive) {
                    if let deviceId = deletingDeviceId {
                        Task {
                            do {
                                let client = RemoteBrokerClient()
                                await client.loadSavedConfig()
                                try await client.deleteDevice(id: deviceId)
                                await loadServerData()
                            } catch {
                                errorMessage = "删除失败: \(error.localizedDescription)"
                                await loadServerData()
                            }
                        }
                    }
                    deletingDeviceId = nil
                }
            } message: {
                Text("确定删除此设备及其所有 Agent？此操作不可撤销。")
            }
            .alert("错误", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("确定") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Multi-Agent

    private var multiAgentContent: some View {
        List {
            if devices.isEmpty && !loadMessage.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.4))
                        Text("还没有 Agent")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(loadMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            ForEach(devices) { device in
                Section {
                    DeviceTreeCard(device: device) { agent in
                        selectedAgent = agent
                    } onDelete: {
                        deletingDeviceId = device.id
                        showDeleteConfirm = true
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                NavigationLink(destination: AgentConnectionSettingsView()) {
                    Label("连接管理", systemImage: "gearshape")
                }
                NavigationLink(destination: TaskAssignmentView(devices: devices)) {
                    Label("任务指派", systemImage: "checklist")
                }
                NavigationLink(destination: WorkflowBoardView(devices: devices)) {
                    Label("工作流编排", systemImage: "point.3.filled.connected.trianglepath.dotted")
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
            devices = []
            account = nil
            loadMessage = "请先登录云端账号。"
            return
        }

        do {
            let client = RemoteBrokerClient()
            await client.loadSavedConfig()
            async let fetchedDevices = client.fetchDevices()
            async let currentAccount = client.fetchAccount()
            devices = try await fetchedDevices
            account = try await currentAccount
            loadMessage = ""
        } catch {
            loadMessage = error.localizedDescription
        }
    }
}

private struct DeviceTreeCard: View {
    let device: AgentDevice
    let onSelectAgent: (AgentInfo) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: device.systemImage)
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(Color(.tertiarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name).font(.headline)
                    Text("\(device.operatingSystem) · \(device.isOnline ? "在线" : "离线") · \(device.agents.count) 个 Agent")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("移除设备", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            .padding(14)

            if !device.agents.isEmpty {
                Divider().padding(.leading, 68)
                VStack(spacing: 0) {
                    ForEach(device.agents) { agent in
                        Button { onSelectAgent(agent) } label: {
                            HStack(spacing: 11) {
                                Rectangle().fill(Color.secondary.opacity(0.22)).frame(width: 1, height: 30)
                                AgentBrandMark(agent: agent, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text("\(agent.kindDisplayName)\(agent.version.map { " · v\($0)" } ?? "")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Circle().fill(agent.isOnline ? Color.green : Color.gray).frame(width: 7, height: 7)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(.leading, 28)
                            .padding(.trailing, 14)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Device Header Row

private struct DeviceHeaderRow: View {
    let device: AgentDevice

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(device.isOnline ? Color.blue.opacity(0.1) : Color.gray.opacity(0.08))
                    .frame(width: 46, height: 46)
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 18))
                    .foregroundColor(device.isOnline ? .blue : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                HStack(spacing: 4) {
                    Circle()
                        .fill(device.isOnline ? Color.green : Color.gray)
                        .frame(width: 6, height: 6)
                    Text(device.isOnline ? "在线 · \(device.agents.count) 个 Agent" : "离线")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Agent Row

private struct AgentRow: View {
    let agent: AgentInfo

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(agent.isOnline ? Color.green.opacity(0.1) : Color.gray.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: agentIcon)
                    .font(.system(size: 16))
                    .foregroundColor(agent.isOnline ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    if let v = agent.version, !v.isEmpty {
                        Text("v\(v)")
                    }
                    if let ep = agent.endpoint {
                        Text(ep.components(separatedBy: "://").last ?? ep)
                    }
                    if !agent.capabilities.isEmpty {
                        Text("· \(agent.capabilities.count) 能力")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            Spacer()

            Circle()
                .fill(agent.isOnline ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
        }
        .padding(.vertical, 3)
    }

    private var agentIcon: String {
        switch agent.kind {
        case "hermes": return "brain.head.profile"
        case "claude-code", "codex": return "terminal"
        default: return "gearshape.2"
        }
    }
}

// MARK: - Agent Detail View

struct AgentDetailView: View {
    let agent: AgentInfo

    var body: some View {
        NavigationStack {
            List {
                Section("基本信息") {
                    LabeledContent("名称", value: agent.name)
                    LabeledContent("类型", value: agent.kind)
                    if let v = agent.version { LabeledContent("版本", value: v) }
                    if let ep = agent.endpoint { LabeledContent("地址", value: ep) }
                    LabeledContent("状态", value: agent.isOnline ? "在线" : "离线")
                }

                if !agent.capabilities.isEmpty {
                    Section("能力 (\(agent.capabilities.count))") {
                        ForEach(agent.capabilities, id: \.self) { cap in
                            Label(cap, systemImage: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundColor(.green)
                        }
                    }
                }

                if !agent.skills.isEmpty {
                    Section("Skills (\(agent.skills.count))") {
                        ForEach(agent.skills) { skill in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.subheadline.weight(.medium))
                                if let d = skill.description {
                                    Text(d)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                if !agent.skills.isEmpty {
                    Section {
                        Text("你可以在此 Agent 上使用以上 \(agent.skills.count) 个 Skill。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(agent.name)
        }
    }
}

// MARK: - Task Assignment View (updated)

struct TaskAssignmentView: View {
    let devices: [AgentDevice]

    private var allAgents: [(deviceName: String, agent: AgentInfo)] {
        devices.flatMap { d in
            d.agents.map { (deviceName: d.name, agent: $0) }
        }
    }

    private var assignedMemos: [MemoItem] {
        guard let data = UserDefaults.standard.data(forKey: "savedMemos"),
              let saved = try? JSONDecoder().decode([MemoItem].self, from: data) else { return [] }
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
                ForEach(allAgents, id: \.agent.id) { item in
                    let agentTasks = tasks.filter { $0.assignedAgentID == item.agent.id }
                    if !agentTasks.isEmpty {
                        Section("\(item.deviceName) / \(item.agent.name)") {
                            ForEach(agentTasks) { task in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(task.text).font(.body).lineLimit(3)
                                    Text(task.updatedAt.formatted()).font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
            }

            Section("Agent 列表") {
                ForEach(allAgents, id: \.agent.id) { item in
                    HStack {
                        Circle().fill(item.agent.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                        Text("\(item.deviceName) / \(item.agent.name)")
                            .font(.subheadline)
                        Spacer()
                        let count = tasks.filter { $0.assignedAgentID == item.agent.id }.count
                        if count > 0 {
                            Text("\(count) 个任务").font(.caption).foregroundColor(.blue)
                        } else {
                            Text(item.agent.isOnline ? "在线" : "离线").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("任务指派")
    }
}
