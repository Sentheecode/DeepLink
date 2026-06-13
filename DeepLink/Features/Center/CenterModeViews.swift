import SwiftUI

// MARK: - Memo Model

struct MemoItem: Identifiable, Codable {
    let id: UUID
    var text: String
    var createdAt: Date
    var updatedAt: Date
    var assignedAgentID: String?

    init(id: UUID = UUID(), text: String, createdAt: Date = Date(), updatedAt: Date = Date(), assignedAgentID: String? = nil) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.assignedAgentID = assignedAgentID
    }
}

// MARK: - Full-screen Notes (Apple Notes-like)

struct CenterMemoModeView: View {
    @State private var memos: [MemoItem] = []
    @State private var selectedNote: MemoItem?
    @State private var showEditor = false
    @State private var showAgentPicker = false
    @State private var memoForAssignment: MemoItem?
    @State private var searchText = ""

    private let memosKey = "savedMemos"

    var body: some View {
        VStack(spacing: 0) {
            if memos.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredMemos) { memo in
                        NoteRow(memo: memo)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedNote = memo
                                showEditor = true
                            }
                            .contextMenu {
                                if memo.assignedAgentID == nil {
                                    Button {
                                        memoForAssignment = memo
                                        showAgentPicker = true
                                    } label: {
                                        Label("指派给 Agent", systemImage: "person.crop.circle.badge.plus")
                                    }
                                    Button(role: .destructive) {
                                        deleteMemo(memo)
                                    } label: {
                                        Label("删除", systemImage: "trash")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        deleteMemo(memo)
                                    } label: {
                                        Label("取消指派并删除", systemImage: "trash")
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) { deleteMemo(memo) }
                            }
                            .swipeActions(edge: .leading) {
                                if memo.assignedAgentID == nil {
                                    Button {
                                        memoForAssignment = memo
                                        showAgentPicker = true
                                    } label: {
                                        Label("指派", systemImage: "person.crop.circle.badge.plus")
                                    }
                                    .tint(.blue)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "搜索备忘录")
            }
        }
        .navigationTitle("备忘录")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    selectedNote = nil
                    showEditor = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.title3)
                }
            }
        }
        .onAppear { loadMemos() }
        .sheet(isPresented: $showEditor) {
            NoteEditorView(memo: selectedNote, onSave: { note in
                if let idx = memos.firstIndex(where: { $0.id == note.id }) {
                    memos[idx] = note
                } else {
                    memos.insert(note, at: 0)
                }
                persistMemos()
            }, onDelete: { note in
                deleteMemo(note)
            })
        }
        .sheet(isPresented: $showAgentPicker) {
            AgentAssignmentSheet(memo: $memoForAssignment, memos: $memos, onSave: persistMemos)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "note.text")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("无备忘录")
                .font(.title2.weight(.medium))
                .foregroundColor(.secondary)
            Text("点击右上角 + 创建新备忘录")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var filteredMemos: [MemoItem] {
        if searchText.isEmpty { return memos }
        return memos.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    private func deleteMemo(_ memo: MemoItem) {
        memos.removeAll { $0.id == memo.id }
        persistMemos()
    }

    private func persistMemos() {
        if let data = try? JSONEncoder().encode(memos) { UserDefaults.standard.set(data, forKey: memosKey) }
    }

    private func loadMemos() {
        guard let data = UserDefaults.standard.data(forKey: memosKey),
              let saved = try? JSONDecoder().decode([MemoItem].self, from: data) else { return }
        memos = saved
    }
}

// MARK: - Note Row

private struct NoteRow: View {
    let memo: MemoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(previewText)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 8) {
                Text(memo.updatedAt, style: .date)
                    .font(.caption)
                if let agentID = memo.assignedAgentID {
                    Label(agentID, systemImage: "person.crop.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var previewText: String {
        let trimmed = memo.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "空白备忘录" }
        return trimmed
    }
}

// MARK: - Note Editor (sheet)

private struct NoteEditorView: View {
    let memo: MemoItem?
    let onSave: (MemoItem) -> Void
    let onDelete: (MemoItem) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    private var isAssigned: Bool {
        memo?.assignedAgentID != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isAssigned {
                    // Read-only view
                    ScrollView {
                        Text(text)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("已指派给 Agent，不可编辑")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.bottom, 8)
                } else {
                    TextEditor(text: $text)
                        .font(.body)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }
            }
            .navigationTitle(memo == nil ? "新建备忘录" : "编辑备忘录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isAssigned {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            save()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let m = memo {
                        ToolbarItem(placement: .bottomBar) {
                            Button(role: .destructive) {
                                onDelete(m)
                                dismiss()
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            if let m = memo { text = m.text }
            isFocused = memo == nil
        }
    }

    private func save() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let existing = memo {
            let updated = MemoItem(id: existing.id, text: t, createdAt: existing.createdAt, updatedAt: Date(), assignedAgentID: existing.assignedAgentID)
            onSave(updated)
        } else {
            onSave(MemoItem(text: t))
        }
    }
}

// MARK: - Agent Assignment Sheet

private struct AgentAssignmentSheet: View {
    @Binding var memo: MemoItem?
    @Binding var memos: [MemoItem]
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var agents: [TeamNode] = []
    @State private var loadMessage = ""

    var body: some View {
        NavigationStack {
            List {
                Section("指派给 Agent") {
                    Button {
                        unassign()
                        dismiss()
                    } label: {
                        HStack {
                            Text("不指派").foregroundColor(.secondary)
                            Spacer()
                            if memo?.assignedAgentID == nil { Image(systemName: "checkmark") }
                        }
                    }

                    // Local Hermes agent (always available when configured)
                    if HermesAPI.shared.isConfigured {
                        Button {
                            assign(to: "local_hermes")
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(Color.green).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Hermes Agent").foregroundColor(.primary).fontWeight(.medium)
                                    Text("本地连接").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if memo?.assignedAgentID == "local_hermes" { Image(systemName: "checkmark") }
                            }
                        }
                    }

                    ForEach(agents) { agent in
                        Button {
                            assign(to: agent.id)
                            dismiss()
                        } label: {
                            HStack {
                                Circle().fill(agent.isOnline ? Color.green : Color.gray).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name).foregroundColor(.primary)
                                    Text(agent.role).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if memo?.assignedAgentID == agent.id { Image(systemName: "checkmark") }
                            }
                        }
                    }

                    if agents.isEmpty && !HermesAPI.shared.isConfigured {
                        Text(loadMessage.isEmpty ? "暂无可指派的 Agent" : loadMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("指派")
            .presentationDetents([.medium])
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task { await loadAgents() }
    }

    private func loadAgents() async {
        guard KeychainCredentialStore().hasToken(for: .brokerKey) else {
            loadMessage = "请先在设置中登录云端账号"
            return
        }
        do {
            let client = RemoteBrokerClient()
            await client.loadSavedConfig()
            agents = try await client.fetchDevices().map {
                TeamNode(id: $0.id, name: $0.name, role: "Agent", isOnline: $0.isOnline)
            }
            loadMessage = ""
        } catch {
            agents = []
            loadMessage = error.localizedDescription
        }
    }

    private func assign(to agentID: String) {
        guard let m = memo, let idx = memos.firstIndex(where: { $0.id == m.id }) else { return }
        memos[idx].assignedAgentID = agentID
        onSave()
        memo = memos[idx]
    }

    private func unassign() {
        guard let m = memo, let idx = memos.firstIndex(where: { $0.id == m.id }) else { return }
        memos[idx].assignedAgentID = nil
        onSave()
        memo = memos[idx]
    }
}
