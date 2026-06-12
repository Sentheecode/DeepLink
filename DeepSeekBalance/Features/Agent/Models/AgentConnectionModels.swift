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
}

struct AgentConnectionProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: AgentConnectionKind
    let deviceId: String?
    let endpoint: String?
}
