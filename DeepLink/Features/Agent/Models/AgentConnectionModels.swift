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

    var operatingSystem: String {
        let lowered = "\(name) \(endpoint ?? "")".lowercased()
        if lowered.contains("mac") || lowered.contains("darwin") { return "macOS" }
        if lowered.contains("windows") || lowered.contains("win") { return "Windows" }
        if lowered.contains("linux") || lowered.contains("ubuntu") { return "Linux" }
        return "未知系统"
    }

    var systemImage: String {
        switch operatingSystem {
        case "macOS": "macbook"
        case "Windows": "pc"
        case "Linux": "server.rack"
        default: "desktopcomputer"
        }
    }
}

struct AgentInfo: Identifiable, Codable, Hashable {
    let id: String
    let deviceId: String
    let name: String
    let kind: String
    let endpoint: String?
    let version: String?
    let status: String
    let isOnline: Bool
    let capabilities: [String]
    let skills: [AgentSkill]
    let lastSeenAt: Date?

    var kindDisplayName: String {
        switch kind.lowercased() {
        case "hermes": "Hermes"
        case "claude-code", "claude": "Claude Code"
        case "codex": "Codex"
        case "openclaw": "OpenClaw"
        default: kind
        }
    }

    var brandInitials: String {
        switch kind.lowercased() {
        case "hermes": "H"
        case "claude-code", "claude": "AI"
        case "codex": "CX"
        case "openclaw": "OC"
        default: String(name.prefix(2)).uppercased()
        }
    }
}

struct AgentSkill: Identifiable, Codable, Hashable {
    let name: String
    let description: String?
    var id: String { name }
}

enum AgentSelectionResolver {
    static func resolve(agents: [AgentInfo], preferredAgentID: String) -> AgentInfo? {
        agents.first(where: { $0.id == preferredAgentID }) ?? agents.first
    }
}

struct AgentConnectionProfile: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let kind: AgentConnectionKind
    let deviceId: String?
    let endpoint: String?
}
