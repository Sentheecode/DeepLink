import Foundation

protocol AgentDeviceRegistry: Sendable {
    func fetchDevices() async throws -> [AgentDevice]
    func saveSelectedDeviceID(_ deviceID: String?) async
    func selectedDeviceID() async -> String?
}

actor LocalAgentDeviceRegistry: AgentDeviceRegistry {
    private let key = "agent.selectedDeviceID"

    func fetchDevices() async throws -> [AgentDevice] {
        []
    }

    func saveSelectedDeviceID(_ deviceID: String?) async {
        UserDefaults.standard.set(deviceID, forKey: key)
    }

    func selectedDeviceID() async -> String? {
        UserDefaults.standard.string(forKey: key)
    }
}
