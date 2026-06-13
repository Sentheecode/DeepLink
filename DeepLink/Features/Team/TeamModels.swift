import Foundation

enum TeamMode: String, Codable, CaseIterable {
    case multiUser
    case multiAgent

    var title: String {
        switch self {
        case .multiUser: return "多人协作"
        case .multiAgent: return "多 Agent 协作"
        }
    }
}

struct TeamNode: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let role: String
    let isOnline: Bool
}
