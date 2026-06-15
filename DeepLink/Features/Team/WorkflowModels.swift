import Foundation

struct AgentAssignmentTarget: Identifiable, Hashable {
    let agent: AgentInfo
    let deviceName: String

    var id: String { agent.id }
    var title: String { agent.name }
    var subtitle: String { "\(deviceName) · \(agent.kindDisplayName)" }
}

struct AgentWorkflow: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var goal: String = ""
    var successCriteria: String = ""
    var maxIterations: Int = 3
    var currentIteration: Int = 0
    var state: WorkflowLoopState = .draft
    var createdAt = Date()
    var steps: [AgentWorkflowStep]
}

struct AgentWorkflowStep: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var instructions: String
    var agentID: String
    var agentName: String
    var deviceName: String
    var reviewerAgentID: String?
    var reviewerAgentName: String?
    var requiresHumanApproval: Bool = false
    var state: WorkflowStepState = .waiting
}

enum WorkflowLoopState: String, Codable, CaseIterable {
    case draft
    case running
    case waitingForReview
    case completed
    case stopped

    var title: String {
        switch self {
        case .draft: "草稿"
        case .running: "循环中"
        case .waitingForReview: "等待审查"
        case .completed: "已达成"
        case .stopped: "已停止"
        }
    }
}

enum WorkflowStepState: String, Codable, CaseIterable {
    case waiting
    case running
    case completed

    var title: String {
        switch self {
        case .waiting: "等待"
        case .running: "进行中"
        case .completed: "已完成"
        }
    }
}

enum WorkflowStore {
    private static let key = "agent.workflows.v1"

    static func load() -> [AgentWorkflow] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let workflows = try? JSONDecoder().decode([AgentWorkflow].self, from: data) else {
            return []
        }
        return workflows
    }

    static func save(_ workflows: [AgentWorkflow]) {
        guard let data = try? JSONEncoder().encode(workflows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
