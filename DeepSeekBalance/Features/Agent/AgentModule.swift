import SwiftUI
import WidgetKit

// MARK: - Channel Adapter

final class HermesChannel: AgentChannel {
    func loadSavedConfig() async {
        await HermesAPI.shared.loadSavedConfig()
    }

    var isConfigured: Bool {
        HermesAPI.shared.isConfigured
    }

    func listSessions() async throws -> [HermesSession] {
        try await HermesAPI.shared.listSessions()
    }

    func createSession(title: String?) async throws -> HermesSession {
        try await HermesAPI.shared.createSession(title: title)
    }

    func deleteSession(id: String) async throws {
        try await HermesAPI.shared.deleteSession(id: id)
    }

    func listMessages(sessionId: String, before: String? = nil, limit: Int = 50) async throws -> [HermesMessage] {
        try await HermesAPI.shared.listMessages(sessionId: sessionId, before: before, limit: limit)
    }

    func chatStream(sessionId: String, message: String) async -> AsyncThrowingStream<HermesStreamEvent, Error> {
        await HermesAPI.shared.chatStream(sessionId: sessionId, message: message)
    }

    func health() async throws -> Bool {
        try await HermesAPI.shared.health()
    }

    func configure(baseURL: String, apiKey: String) async {
        await HermesAPI.shared.configure(baseURL: baseURL, apiKey: apiKey)
    }
}

// MARK: - Agent Tab

struct AgentTab: View {
    @State private var store = AgentStore(channel: PreferredAgentChannel())
    @State private var showNewSession = false
    @State private var newSessionTitle = ""
    @State private var selectedAgentID = "local"
    @State private var showAgentPicker = false
    @AppStorage("defaultAgentID") private var defaultAgentID: String = ""
    @State private var agents: [ConfiguredAgent] = []

    private var selectedAgentName: String {
        if selectedAgentID == "local" { return "本地" }
        return agents.first(where: { $0.id == selectedAgentID })?.name ?? "本地"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(destination: GlobalSearchView()) {
                        Label("全局检索", systemImage: "doc.text.magnifyingglass")
                            .font(.body)
                    }
                }

                // Sessions section
                Section {
                    if store.isLoading && store.conversations.isEmpty {
                        HStack { Spacer(); ProgressView("连接 Agent…"); Spacer() }
                            .listRowBackground(Color.clear)
                    } else if store.errorMessage != nil && store.conversations.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "wifi.slash").font(.title2).foregroundColor(.secondary)
                            Text("无法连接").foregroundColor(.secondary)
                            Text(store.errorMessage ?? "").font(.caption).foregroundColor(.secondary)
                            Button("重试") { Task { await store.loadSessions() } }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    } else if store.conversations.isEmpty {
                        Text("暂无会话").foregroundColor(.secondary).frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.conversations) { conv in
                            NavigationLink(destination: AgentConversationView(sessionId: conv.id, store: store)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conv.displayTitle).font(.headline)
                                    Text(conv.model ?? "hermes").font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) { store.deleteSession(id: conv.id) }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("会话")
                        Spacer()
                        if !agents.isEmpty || HermesAPI.shared.isConfigured {
                            Button { showAgentPicker = true } label: {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.green).frame(width: 6, height: 6)
                                    Text(selectedAgentName).font(.caption).fontWeight(.medium)
                                    Image(systemName: "chevron.down").font(.caption2)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.systemGray6))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Agent")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showNewSession = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                Task { await store.loadSessions() }
                loadAgents()
            }
            .refreshable { await store.refreshSessions() }
            .alert("新建会话", isPresented: $showNewSession) {
                TextField("标题（可选）", text: $newSessionTitle)
                Button("取消", role: .cancel) { newSessionTitle = "" }
                Button("创建") {
                    store.createSession(title: newSessionTitle.isEmpty ? nil : newSessionTitle)
                    newSessionTitle = ""
                }
            }
            .sheet(isPresented: $showAgentPicker) {
                AgentPickerView(agents: agents, selectedID: $selectedAgentID, defaultID: $defaultAgentID)
            }
        }
    }

    private func loadAgents() {
        if HermesAPI.shared.isConfigured {
            var localAgents: [ConfiguredAgent] = []
            if HermesAPI.shared.isConfigured {
                localAgents.append(ConfiguredAgent(id: "local", name: "Hermes Agent", type: "本地连接", icon: "point.3.connected.trianglepath.dotted", isConnected: true))
            }
            // Load cloud agents if available
            if KeychainCredentialStore().hasToken(for: .brokerKey) {
                Task {
                    do {
                        let client = RemoteBrokerClient()
                        await client.loadSavedConfig()
                        let devices = try await client.fetchDevices()
                        agents = localAgents + devices.map {
                            ConfiguredAgent(id: $0.id, name: $0.name, type: $0.kind.rawValue, icon: "desktopcomputer", isConnected: $0.isOnline)
                        }
                    } catch {
                        agents = localAgents
                    }
                }
            } else {
                agents = localAgents
            }
        }
    }
}

// MARK: - Agent Picker Sheet

struct AgentPickerView: View {
    let agents: [ConfiguredAgent]
    @Binding var selectedID: String
    @Binding var defaultID: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("当前 Agent") {
                    ForEach(agents) { agent in
                        Button {
                            selectedID = agent.id
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(agent.isConnected ? Color.green : Color.gray).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name).foregroundColor(.primary).fontWeight(.medium)
                                    Text(agent.type).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if selectedID == agent.id { Image(systemName: "checkmark").font(.caption) }
                            }
                        }
                    }
                }

                Section {
                    ForEach(agents) { agent in
                        Button {
                            defaultID = agent.id
                            dismiss()
                        } label: {
                            HStack {
                                Text(agent.name).foregroundColor(.primary)
                                Spacer()
                                if defaultID == agent.id { Image(systemName: "checkmark").font(.caption) }
                            }
                        }
                    }
                    if defaultID.isEmpty {
                        HStack {
                            Text("不启用").foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "checkmark").font(.caption)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { defaultID = ""; dismiss() }
                    }
                } header: {
                    Text("默认处理 Agent")
                } footer: {
                    Text("语音和拍照内容将自动发送到默认 Agent。")
                }
            }
            .navigationTitle("选择 Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 全局检索

struct GlobalSearchView: View {
    @State private var searchText = ""
    @State private var messages: [GlobalSearchMessage] = []
    @State private var isSearching = false
    @State private var sendTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            // Message area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 44))
                                    .foregroundColor(.secondary.opacity(0.4))
                                Text("全局检索")
                                    .foregroundColor(.secondary)
                                Text("输入问题，搜索所有历史会话和记忆")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .padding(.vertical, 60)
                            .frame(maxWidth: .infinity)
                        } else {
                            ForEach(messages) { msg in
                                searchBubble(msg)
                                    .id(msg.id)
                            }
                            if isSearching {
                                HStack {
                                    ProgressView().scaleEffect(0.8)
                                    Text("搜索中…").font(.caption).foregroundColor(.secondary)
                                }
                                .padding(.leading, 16)
                                .id("typing")
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                    }
                }
            }

            Divider()
            // Bottom input bar
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("搜索所有历史会话…", text: $searchText)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { performSearch() }
                        .disabled(isSearching)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if isSearching {
                    Button(action: cancelSearch) {
                        Image(systemName: "stop.circle.fill").font(.title2).foregroundColor(.red)
                    }
                } else {
                    Button(action: performSearch) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .navigationTitle("全局检索")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func searchBubble(_ msg: GlobalSearchMessage) -> some View {
        switch msg.role {
        case "user":
            HStack {
                Spacer(minLength: 60)
                Text(msg.content)
                    .font(.body)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .textSelection(.enabled)
            }
        case "assistant":
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass").font(.caption).foregroundColor(.secondary)
                        Text("Agent").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }
                    Text(msg.content)
                        .font(.body)
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 60)
            }
        default:
            EmptyView()
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, !isSearching else { return }
        searchText = ""

        let userMsg = GlobalSearchMessage(role: "user", content: query)
        messages.append(userMsg)
        isSearching = true

        sendTask = Task {
            defer { isSearching = false }
            let channel = HermesChannel()
            await channel.loadSavedConfig()
            guard channel.isConfigured else {
                messages.append(GlobalSearchMessage(role: "assistant", content: "请先在设置中配置 Agent 连接。"))
                return
            }
            do {
                let session = try await channel.createSession(title: "全局检索")
                defer { Task { try? await channel.deleteSession(id: session.id) } }

                let prompt = "请搜索我所有的历史会话和记忆，找出与「\(query)」相关的内容并总结。请注明每个信息的来源会话。"
                let stream = await channel.chatStream(sessionId: session.id, message: prompt)
                var fullContent = ""
                let assistantMsg = GlobalSearchMessage(role: "assistant", content: "")
                messages.append(assistantMsg)

                for try await event in stream {
                    if Task.isCancelled { break }
                    if let content = event.content {
                        fullContent += content
                        if let idx = messages.lastIndex(where: { $0.id == assistantMsg.id }) {
                            messages[idx].content = fullContent
                        }
                    }
                }
                if fullContent.isEmpty {
                    if let idx = messages.lastIndex(where: { $0.id == assistantMsg.id }) {
                        messages[idx].content = "未找到相关内容。"
                    }
                }
            } catch {
                if !Task.isCancelled {
                    messages.append(GlobalSearchMessage(role: "assistant", content: "搜索失败: \(error.localizedDescription)"))
                }
            }
        }
    }

    private func cancelSearch() {
        sendTask?.cancel()
        sendTask = nil
        isSearching = false
    }
}

struct GlobalSearchMessage: Identifiable {
    let id = UUID().uuidString
    let role: String  // "user" or "assistant"
    var content: String
}

// MARK: - Agent Message Model

struct AgentChatMessage: Identifiable {
    enum State: Equatable {
        case normal
        case streaming
        case failed(retryText: String)
    }

    let id: String
    let role: String
    let content: String
    let isStreaming: Bool
    let state: State

    var icon: String {
        switch role {
        case "user": return "person.circle"
        case "assistant": return "brain.head.profile"
        default: return "circle"
        }
    }
}

// MARK: - Agent Conversation View

struct AgentConversationView: View {
    let sessionId: String
    let store: AgentStore
    @State private var inputText = ""
    @State private var messages: [AgentChatMessage] = []
    @State private var isLoadingHistory = false
    @State private var isSending = false
    @State private var sendTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if isLoadingHistory {
                            ProgressView().padding()
                        } else if messages.isEmpty, !isSending {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right").font(.title2).foregroundColor(.secondary)
                                Text("新会话，发一条消息开始吧").font(.subheadline).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 60)
                        }
                        ForEach(messages) { msg in
                            messageBubble(msg).id(msg.id)
                        }
                        if isSending {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("Agent 思考中…").font(.caption).foregroundColor(.secondary)
                            }
                            .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id ?? "typing", anchor: .bottom)
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if focused, let last = messages.last?.id {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation {
                                proxy.scrollTo(last, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 8) {
                TextField("输入消息…", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .disabled(isSending)
                if isSending {
                    Button(action: cancelSend) {
                        Image(systemName: "stop.circle.fill").font(.title2).foregroundColor(.red)
                    }
                } else {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            .padding(.bottom, 0)
        }
        .navigationTitle("会话")
        .task { await loadMessages() }
        .onAppear { observeKeyboard() }
        .onDisappear {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        }
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil, queue: .main
        ) { notification in
            if let rect = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
                withAnimation(.easeOut(duration: duration)) {
                    keyboardHeight = rect.height
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil, queue: .main
        ) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                keyboardHeight = 0
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ msg: AgentChatMessage) -> some View {
        switch msg.state {
        case .failed(let retryText):
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                        Text("发送失败")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.red)
                    }
                    Text(msg.content)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                    Button("重试此消息") {
                        retryMessage(retryText)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.12))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        default:
            HStack {
                if msg.role == "user" { Spacer(minLength: 60) }
                VStack(alignment: msg.role == "user" ? .trailing : .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        if msg.role != "user" {
                            Image(systemName: msg.icon).font(.caption).foregroundColor(.blue)
                        }
                        markdownContent(msg.content, streaming: msg.isStreaming)
                        if msg.role == "user" {
                            Image(systemName: msg.icon).font(.caption).foregroundColor(.green)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(msg.role == "user" ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                if msg.role == "assistant" { Spacer(minLength: 60) }
            }
        }
    }

    /// 渲染 Markdown 内容，流式消息用纯文本避免闪烁
    @ViewBuilder
    private func markdownContent(_ text: String, streaming: Bool) -> some View {
        if streaming || text.isEmpty {
            Text(text).font(.subheadline).textSelection(.enabled)
        } else if let attributed = try? AttributedString(markdown: text) {
            Text(attributed).font(.subheadline).textSelection(.enabled)
        } else {
            Text(text).font(.subheadline).textSelection(.enabled)
        }
    }

    private func loadMessages() async {
        messages = store.messageCache[sessionId] ?? []
        // Try local disk cache first
        if messages.isEmpty, let cached = store.loadMessagesFromDisk(sessionId: sessionId) {
            messages = cached
        }
        isLoadingHistory = true
        do {
            let msgs = try await store.channel.listMessages(sessionId: sessionId, before: nil, limit: 50)
            let mapped = msgs.map {
                AgentChatMessage(id: $0.id, role: $0.role, content: $0.content, isStreaming: false, state: .normal)
            }
            if !mapped.isEmpty {
                messages = mapped
                store.messageCache[sessionId] = mapped
                store.saveMessagesToDisk(sessionId: sessionId, messages: mapped)
            }
        } catch {
            // 保留缓存，不打断页面
        }
        isLoadingHistory = false

        // 如果有活跃的后台流正在运行，启动轮询恢复 UI 更新
        if let last = messages.last, last.isStreaming, sendTask == nil, store.hasActiveStream(sessionId: sessionId) {
            await MainActor.run {
                isSending = true
                startPollingForUpdates()
            }
        }
    }

    /// 轮询后台流状态并更新 UI
    private func startPollingForUpdates() {
        sendTask?.cancel()
        sendTask = Task {
            var lastKnownContent: String? = messages.last?.content
            while !Task.isCancelled {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(300))
                let cached = store.messageCache[sessionId] ?? store.loadMessagesFromDisk(sessionId: sessionId) ?? []
                if cached.count > messages.count {
                    messages = cached
                    lastKnownContent = messages.last?.content
                } else if cached.count == messages.count, cached.count > 0 {
                    let lastCached = cached.last
                    let lastMsg = messages.last
                    if lastCached?.content != lastMsg?.content {
                        messages = cached
                        lastKnownContent = messages.last?.content
                    }
                }
                // Check if streaming is done
                if let last = messages.last, !last.isStreaming {
                    await MainActor.run {
                        isSending = false
                        sendTask = nil
                    }
                    break
                }
            }
        }
    }

    @MainActor private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        isFocused = false

        let userMsg = AgentChatMessage(id: UUID().uuidString, role: "user", content: text, isStreaming: false, state: .normal)
        messages.append(userMsg)
        messages.append(AgentChatMessage(id: "reply_\(sessionId)", role: "assistant", content: "", isStreaming: true, state: .streaming))
        store.messageCache[sessionId] = messages
        store.saveMessagesToDisk(sessionId: sessionId, messages: messages)
        isSending = true

        // 唯一流媒体请求，由 AgentStore 持有（切 tab 不中断）
        store.startBackgroundStream(sessionId: sessionId, message: text)

        // 轮询后台流的进度更新界面
        startPollingForUpdates()
    }

    private func cancelSend() {
        sendTask?.cancel()
        sendTask = nil
        isSending = false
        messages.removeAll { $0.content.isEmpty && $0.isStreaming }
        store.messageCache[sessionId] = messages
        store.saveMessagesToDisk(sessionId: sessionId, messages: messages)
    }

    private func retryMessage(_ text: String) {
        inputText = text
        isFocused = true
        messages.removeAll {
            if case .failed = $0.state { return true }
            return false
        }
        store.messageCache[sessionId] = messages
        store.saveMessagesToDisk(sessionId: sessionId, messages: messages)
        sendMessage()
    }
}

// MARK: - Agent Store

@MainActor @Observable
final class AgentStore {
    let channel: any AgentChannel
    var conversations: [HermesSession] = []
    var isLoading = false
    var errorMessage: String?
    var messageCache: [String: [AgentChatMessage]] = [:]

    // Active stream management (survives view lifecycles)
    private var activeStreams: [String: Task<Void, Never>] = [:]

    init(channel: any AgentChannel) {
        self.channel = channel
    }

    // MARK: - Disk Persistence

    func saveMessagesToDisk(sessionId: String, messages: [AgentChatMessage]) {
        let key = "chat_messages_\(sessionId)_v1"
        let saveable = messages.map { msg in
            ["id": msg.id, "role": msg.role, "content": msg.content, "isStreaming": String(msg.isStreaming)]
        }
        UserDefaults.standard.set(saveable, forKey: key)
    }

    func loadMessagesFromDisk(sessionId: String) -> [AgentChatMessage]? {
        let key = "chat_messages_\(sessionId)_v1"
        guard let saved = UserDefaults.standard.array(forKey: key) as? [[String: String]] else { return nil }
        return saved.compactMap { dict in
            guard let id = dict["id"], let role = dict["role"], let content = dict["content"] else { return nil }
            return AgentChatMessage(id: id, role: role, content: content, isStreaming: false, state: .normal)
        }
    }

    // MARK: - Background Streaming

    func startBackgroundStream(sessionId: String, message: String) {
        // Cancel any existing stream for this session
        activeStreams[sessionId]?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            var replyContent = ""
            let replyId = "reply_\(sessionId)"
            do {
                let stream = await channel.chatStream(sessionId: sessionId, message: message)
                for try await event in stream {
                    if let content = event.content, !content.isEmpty {
                        replyContent += content
                        // Save to disk in real-time so it survives tab switches
                        var msgs = messageCache[sessionId] ?? loadMessagesFromDisk(sessionId: sessionId) ?? []
                        if let idx = msgs.lastIndex(where: { $0.id == replyId }) {
                            msgs[idx] = AgentChatMessage(
                                id: replyId,
                                role: "assistant",
                                content: replyContent,
                                isStreaming: true,
                                state: .streaming
                            )
                        } else {
                            msgs.append(AgentChatMessage(
                                id: replyId,
                                role: "assistant",
                                content: replyContent,
                                isStreaming: true,
                                state: .streaming
                            ))
                        }
                        messageCache[sessionId] = msgs
                        saveMessagesToDisk(sessionId: sessionId, messages: msgs)
                    }
                }
                // Stream completed - finalize
                var msgs = messageCache[sessionId] ?? loadMessagesFromDisk(sessionId: sessionId) ?? []
                if let idx = msgs.lastIndex(where: { $0.id == replyId }) {
                    msgs[idx] = AgentChatMessage(
                        id: replyId,
                        role: "assistant",
                        content: replyContent,
                        isStreaming: false,
                        state: .normal
                    )
                }
                messageCache[sessionId] = msgs
                saveMessagesToDisk(sessionId: sessionId, messages: msgs)
            } catch {
                guard !Task.isCancelled else { return }
                var msgs = messageCache[sessionId] ?? loadMessagesFromDisk(sessionId: sessionId) ?? []
                if let idx = msgs.lastIndex(where: { $0.id == replyId }) {
                    msgs[idx] = AgentChatMessage(
                        id: replyId,
                        role: "assistant",
                        content: replyContent.isEmpty ? "错误: \(error.localizedDescription)" : replyContent,
                        isStreaming: false,
                        state: .failed(retryText: message)
                    )
                }
                messageCache[sessionId] = msgs
                saveMessagesToDisk(sessionId: sessionId, messages: msgs)
            }
            activeStreams.removeValue(forKey: sessionId)
        }
        activeStreams[sessionId] = task
    }

    func getBackgroundStreamContent(sessionId: String) -> [AgentChatMessage]? {
        return messageCache[sessionId] ?? loadMessagesFromDisk(sessionId: sessionId)
    }

    func loadSessions() async {
        await channel.loadSavedConfig()
        guard channel.isConfigured else {
            errorMessage = "请在设置中配置 Agent 连接"
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            conversations = try await channel.listSessions()
            // Filter out irrelevant sources
            conversations = conversations.filter { s in
                let source = s.source ?? ""
                return source != "cron" && source != "unknown"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// 检查指定 session 是否有活跃的流
    func hasActiveStream(sessionId: String) -> Bool {
        activeStreams[sessionId] != nil && !(activeStreams[sessionId]?.isCancelled ?? true)
    }

    func refreshSessions() async {
        guard channel.isConfigured else { return }
        do {
            conversations = try await channel.listSessions()
            // Filter out irrelevant sources
            conversations = conversations.filter { s in
                let source = s.source ?? ""
                return source != "cron" && source != "unknown"
            }
        } catch {}
    }

    func createSession(title: String?) {
        isLoading = true
        Task {
            do {
                let session = try await channel.createSession(title: title)
                conversations.insert(session, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func deleteSession(id: String) {
        messageCache.removeValue(forKey: id)
        UserDefaults.standard.removeObject(forKey: "chat_messages_\(id)_v1")
        Task {
            do {
                try await channel.deleteSession(id: id)
                conversations.removeAll { $0.id == id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Agent 连接配置

struct AgentConnectionSettingsView: View {
    @AppStorage(BrokerDefaults.connectionModeKey) private var connectionModeRawValue = AgentConnectionMode.local.rawValue

    var body: some View {
        Form {
            Section {
                Picker("模式", selection: $connectionModeRawValue) {
                    Text("云端").tag(AgentConnectionMode.broker.rawValue)
                    Text("局域网").tag(AgentConnectionMode.local.rawValue)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("当前通道")
            } footer: {
                Text(connectionModeRawValue == AgentConnectionMode.broker.rawValue
                     ? "推荐。手机与 Agent 均主动连接云端，无需开放家庭网络端口。"
                     : "适合调试。手机必须能够直接访问运行 Hermes 的设备。")
            }

            if connectionModeRawValue == AgentConnectionMode.broker.rawValue {
                Section("云端连接") {
                    NavigationLink(destination: BrokerConfigView()) {
                        Label("账号与 Agent 设备", systemImage: "person.2.badge.gearshape")
                    }
                }
            } else {
                Section("局域网连接") {
                    NavigationLink(destination: HermesConfigView()) {
                        Label("Hermes 地址与凭证", systemImage: "network")
                    }
                    NavigationLink(destination: HermesQuickTestView()) {
                        Label("连接诊断", systemImage: "stethoscope")
                    }
                }
            }
        }
        .navigationTitle("Agent 连接方式")
    }
}

struct BrokerConfigView: View {
    @State private var url: String
    @State private var key: String
    @State private var selectedDeviceID: String
    @State private var devices: [AgentDevice] = []
    @State private var statusText = ""
    @State private var isLoading = false
    @State private var enrollmentURL: URL?
    @State private var showAdvanced = false
    @State private var account: BrokerAccount?

    init() {
        _url = State(initialValue: UserDefaults.standard.string(forKey: BrokerDefaults.baseURLKey) ?? BrokerDefaults.defaultBaseURL)
        _key = State(initialValue: (try? KeychainCredentialStore().getToken(for: .brokerKey)) ?? "")
        _selectedDeviceID = State(initialValue: UserDefaults.standard.string(forKey: BrokerDefaults.deviceIDKey) ?? "")
    }

    var body: some View {
        Form {
            Section {
                if let account {
                    LabeledContent("账户", value: account.displayName)
                    LabeledContent("设备", value: "\(account.deviceCount)")
                    LabeledContent("Agent 请求", value: "\(account.rpcCount)")
                } else {
                    Text("登录状态已失效，请返回设置页重新登录。")
                        .foregroundStyle(.secondary)
                }
            }

            if account != nil {
                Section {
                    if devices.isEmpty {
                        Text("暂无设备，请先添加 Agent")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(devices) { device in
                            Button {
                                selectDevice(device)
                            } label: {
                                HStack {
                                    Image(systemName: device.isOnline ? "desktopcomputer.and.macbook" : "desktopcomputer")
                                        .foregroundStyle(device.isOnline ? .green : .secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(device.name).foregroundStyle(.primary)
                                        Text(device.isOnline ? "在线" : "离线")
                                            .font(.caption)
                                            .foregroundStyle(device.isOnline ? .green : .secondary)
                                    }
                                    Spacer()
                                    if selectedDeviceID == device.id {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .swipeActions {
                                Button("解绑", role: .destructive) {
                                    revokeDevice(device)
                                }
                            }
                        }
                    }
                } header: {
                    Text("设备")
                } footer: {
                    if !devices.isEmpty {
                        Text("点击设备即可设为 Agent 页的当前设备，左滑可解绑。")
                    }
                }

                Section("添加 Agent") {
                    Button("生成 Agent 配对二维码") {
                        createEnrollmentLink()
                    }
                    .disabled(isLoading)

                    if let enrollmentURL {
                        HStack {
                            Spacer()
                            BrokerQRCodeView(value: enrollmentURL.absoluteString, size: 220)
                            Spacer()
                        }
                        ShareLink(item: enrollmentURL) {
                            Label("分享安装链接", systemImage: "square.and.arrow.up")
                        }
                        Text("二维码只能使用一次，并会自动过期。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                DisclosureGroup("高级配置", isExpanded: $showAdvanced) {
                    TextField("云端服务地址", text: $url)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    SecureField("用户访问令牌", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("保存手动配置") {
                        saveAndFetchDevices()
                    }
                    if !key.isEmpty {
                        Button("退出云端账号", role: .destructive) {
                            signOut()
                        }
                    }
                }
            }

            if !statusText.isEmpty {
                Section("状态") {
                    Text(statusText).foregroundColor(.secondary)
                }
            }

            if url.hasPrefix("http://") {
                Section("安全提醒") {
                    Text("当前云端服务使用明文 HTTP，仅适用于开发调试。")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .navigationTitle("云端账号与设备")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveAndFetchDevices()
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isLoading || key.isEmpty)
                .accessibilityLabel("刷新设备")
            }
        }
        .task {
            guard !key.isEmpty else { return }
            await refreshAccountAndDevices()
        }
    }

    private func saveAndFetchDevices() {
        isLoading = true
        statusText = ""
        Task {
            do {
                let client = RemoteBrokerClient()
                try await client.configure(baseURL: url, token: key, deviceID: selectedDeviceID)
                devices = try await client.fetchDevices()
                account = try await client.fetchAccount()
                statusText = devices.isEmpty ? "云端服务可访问，但暂无 Agent 设备" : "已同步 \(devices.count) 个设备"
            } catch {
                statusText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func selectDevice(_ device: AgentDevice) {
        selectedDeviceID = device.id
        UserDefaults.standard.set(device.id, forKey: BrokerDefaults.deviceIDKey)
        UserDefaults.standard.set(AgentConnectionMode.broker.rawValue, forKey: BrokerDefaults.connectionModeKey)
        statusText = "Agent 页将连接 \(device.name)"
    }

    private func createEnrollmentLink() {
        isLoading = true
        statusText = ""
        Task {
            do {
                let client = RemoteBrokerClient()
                try await client.configure(baseURL: url, token: key, deviceID: selectedDeviceID)
                enrollmentURL = try await client.createEnrollmentURL()
                statusText = "配对链接只能使用一次，并会自动过期"
            } catch {
                statusText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func refreshAccountAndDevices() async {
        do {
            let client = RemoteBrokerClient()
            await client.loadSavedConfig()
            async let fetchedDevices = client.fetchDevices()
            async let fetchedAccount = client.fetchAccount()
            devices = try await fetchedDevices
            account = try await fetchedAccount
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func revokeDevice(_ device: AgentDevice) {
        isLoading = true
        Task {
            do {
                let client = RemoteBrokerClient()
                await client.loadSavedConfig()
                try await client.deleteDevice(id: device.id)
                if selectedDeviceID == device.id { selectedDeviceID = "" }
                devices = try await client.fetchDevices()
                account = try await client.fetchAccount()
                statusText = "已解绑 \(device.name)"
            } catch {
                statusText = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func signOut() {
        let client = RemoteBrokerClient()
        Task {
            do {
                try await client.signOut()
                key = ""
                selectedDeviceID = ""
                devices = []
                account = nil
                enrollmentURL = nil
                statusText = "已退出云端账号"
            } catch {
                statusText = error.localizedDescription
            }
        }
    }
}

// MARK: - Hermes 配置

struct HermesQuickTestView: View {
    @State private var statusText = "尚未测试"
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("状态") {
                Text(statusText)
                    .foregroundColor(.secondary)
            }
            Section {
                Button(isTesting ? "测试中…" : "开始测试") {
                    testConnection()
                }
                .disabled(isTesting)
            }
        }
        .navigationTitle("Hermes 测试")
    }

    private func testConnection() {
        isTesting = true
        statusText = "连接中…"
        Task {
            do {
                let channel = HermesChannel()
                await channel.loadSavedConfig()
                let ok = try await channel.health()
                statusText = ok ? "✅ Hermes 可用" : "❌ Hermes 不可用"
            } catch {
                statusText = "❌ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

struct HermesConfigView: View {
    @State private var url: String
    @State private var key: String
    @State private var statusText = ""
    @State private var isTesting = false

    init() {
        let savedURL = UserDefaults.standard.string(forKey: "hermesURL") ?? ""
        let savedKey = (try? KeychainCredentialStore().getToken(for: .hermesKey)) ?? ""
        _url = State(initialValue: savedURL.isEmpty ? "http://" : savedURL)
        _key = State(initialValue: savedKey)
    }

    var body: some View {
        Form {
            Section("连接信息") {
                TextField("服务器地址", text: $url)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                SecureField("API Key", text: $key)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Section {
                Button(isTesting ? "测试中…" : "测试连接") {
                    testConnection()
                }
                .disabled(isTesting)

                Button("保存") {
                    guard !url.trimmingCharacters(in: .whitespaces).isEmpty else {
                        statusText = "请输入服务器地址"
                        return
                    }
                    guard URL(string: url) != nil else {
                        statusText = "地址格式无效，应以 http:// 开头"
                        return
                    }
                    UserDefaults.standard.set(url, forKey: "hermesURL")
                    try? KeychainCredentialStore().saveToken(key, for: .hermesKey)
                    Task { await HermesChannel().configure(baseURL: url, apiKey: key) }
                    statusText = "已保存"
                }
            }

            if !statusText.isEmpty {
                Section { Text(statusText).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("Hermes 配置")
    }

    private func testConnection() {
        isTesting = true
        statusText = ""
        Task {
            do {
                await HermesChannel().configure(baseURL: url, apiKey: key)
                let ok = try await HermesChannel().health()
                statusText = ok ? "✅ 连接成功" : "❌ 认证失败"
            } catch {
                statusText = "❌ \(error.localizedDescription)"
            }
            isTesting = false
        }
    }
}

struct CenterDefaultModeSettingsView: View {
    @AppStorage("centerTabMode") private var centerTabModeRawValue: String = CenterTabMode.voice.rawValue

    var body: some View {
        Form {
            Section("默认模式") {
                Picker("启动默认模式", selection: $centerTabModeRawValue) {
                    Text("语音").tag(CenterTabMode.voice.rawValue)
                    Text("拍照").tag(CenterTabMode.camera.rawValue)
                    Text("键盘").tag(CenterTabMode.keyboard.rawValue)
                }
            }
        }
        .navigationTitle("快捷工具")
    }
}

// MARK: - Agent Dispatch (auto-send to default agent)

actor AgentDispatcher {
    static func sendToDefaultAgent(title: String, content: String) async {
        let defaultID = UserDefaults.standard.string(forKey: "defaultAgentID") ?? ""
        guard !defaultID.isEmpty else { return }

        let channel = HermesChannel()
        await channel.loadSavedConfig()
        guard channel.isConfigured else { return }

        do {
            // Try to find existing "默认任务" session, or create a new one
            let sessions = try await channel.listSessions()
            var defaultSession = sessions.first(where: { $0.title == "默认任务" })
            if defaultSession == nil {
                defaultSession = try await channel.createSession(title: "默认任务")
            }
            guard let session = defaultSession else { return }

            let message = "【\(title)】\n\(content)"
            let stream = await channel.chatStream(sessionId: session.id, message: message)
            for try await _ in stream { }
            // Message sent and response received; response is ignored for now
            // The user can find the reply in the "默认任务" session on Agent tab
        } catch {
            // Silent failure - don't interrupt the user
            print("AgentDispatch error: \(error.localizedDescription)")
        }
    }
}
