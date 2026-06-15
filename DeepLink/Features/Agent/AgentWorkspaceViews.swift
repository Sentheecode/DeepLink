import SwiftUI

struct AgentBrandMark: View {
    let agent: AgentInfo
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3)
                .fill(agent.isOnline ? Color.primary : Color.secondary.opacity(0.35))
            Text(agent.brandInitials)
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .foregroundStyle(Color(.systemBackground))
        }
        .frame(width: size, height: size)
        .accessibilityLabel(agent.kindDisplayName)
    }
}

struct AgentWorkspaceSidebar: View {
    let agents: [AgentInfo]
    let selectedAgentID: String
    let onSelectAgent: (AgentInfo) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("工作空间").font(.title2.bold())
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            .padding(20)

            List {
                Section {
                    NavigationLink(destination: GlobalSearchView()) {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                    Label("项目", systemImage: "folder")
                    Label("资源", systemImage: "shippingbox")
                    Label("知识库", systemImage: "books.vertical")
                    Label("插件", systemImage: "puzzlepiece.extension")
                }

                Section("Agent") {
                    ForEach(agents) { agent in
                        Button {
                            onSelectAgent(agent)
                        } label: {
                            HStack(spacing: 11) {
                                AgentBrandMark(agent: agent, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name).foregroundStyle(.primary)
                                    Text(agent.kindDisplayName).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if agent.id == selectedAgentID {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .frame(maxWidth: 330, maxHeight: .infinity)
        .background(.regularMaterial)
        .shadow(color: .black.opacity(0.18), radius: 24, x: 8)
    }
}

struct AgentWorkspaceEmptyState: View {
    let agentName: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 38, weight: .light))
            Text(agentName == "选择 Agent" ? "今天想做什么？" : "和 \(agentName) 开始工作")
                .font(.title2.bold())
            Text("新建对话，或从左上角打开项目、资源、知识库和插件。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("开始新对话", action: action)
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            Spacer()
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
