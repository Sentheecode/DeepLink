import SwiftUI

@main
struct DeepLinkApp: App {
    @State private var showSetup = !UserDefaults.standard.hasCompletedSetup
    @State private var showAuth = false
    @State private var isReady = false

    init() {
        let hasSetup = UserDefaults.standard.hasCompletedSetup
        if hasSetup {
            _isReady = State(initialValue: shouldBeReady())
            _showAuth = State(initialValue: !shouldBeReady() && needsBrokerLogin())
        }
    }

    private func shouldBeReady() -> Bool {
        let mode = connectionMode()
        if mode == .local { return true }
        return KeychainCredentialStore().hasToken(for: .brokerKey)
    }

    private func needsBrokerLogin() -> Bool {
        connectionMode() == .broker && !KeychainCredentialStore().hasToken(for: .brokerKey)
    }

    private func connectionMode() -> AgentConnectionMode {
        AgentConnectionMode(rawValue: UserDefaults.standard.string(forKey: BrokerDefaults.connectionModeKey) ?? "") ?? .local
    }

    private func refreshState() {
        let hasSetup = UserDefaults.standard.hasCompletedSetup
        showSetup = !hasSetup
        if hasSetup {
            let mode = connectionMode()
            if mode == .local {
                isReady = true
                showAuth = false
            } else if KeychainCredentialStore().hasToken(for: .brokerKey) {
                isReady = true
                showAuth = false
            } else {
                isReady = false
                showAuth = true
            }
        } else {
            isReady = false
            showAuth = false
        }
    }

    var body: some Scene {
        WindowGroup {
            if showSetup {
                FirstLaunchSetupView(onComplete: {
                    UserDefaults.standard.hasCompletedSetup = true
                    refreshState()
                })
            } else if showAuth {
                AuthFlowView(onLoginSuccess: {
                    refreshState()
                })
            } else if isReady {
                AppShell(onLogout: {
                    try? KeychainCredentialStore().deleteToken(for: .brokerKey)
                    UserDefaults.standard.hasCompletedLogin = false
                    UserDefaults.standard.cachedUserDisplayName = nil
                    refreshState()
                })
            }
        }
    }
}
