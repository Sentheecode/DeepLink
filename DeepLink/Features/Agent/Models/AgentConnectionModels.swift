import Foundation

enum AgentConnectionKind: String, Codable, CaseIterable {
    case localHermes
    case tailscaleNode
    case brokerRelay
}

struct AgentDevice: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: AgentConnectionKind
    let endpoint: String?
    let isOnline: Bool
    let lastSeenAt: Date?
    let agentCount: Int
    let agents: [AgentInfo]
}

struct AgentInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: String
    let endpoint: String?
    let version: String?
    let status: String
    let isOnline: Bool
    let capabilities: [String]
    let skills: [AgentSkill]
    let lastSeenAt: Date?
}

struct AgentSkill: Identifiable, Codable, Hashable {
    let name: String
    let description: String?
    var id: String { name }
}

struct AgentConnectionProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: AgentConnectionKind
    let deviceId: String?
    let endpoint: String?
}
