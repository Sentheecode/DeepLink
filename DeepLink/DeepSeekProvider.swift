import Foundation

// MARK: - DeepSeek Provider

public final actor DeepSeekProvider: UsageProvider {
    private let api = DeepSeekAPI.shared
    private let credentialStore: CredentialStore

    public init(credentialStore: CredentialStore = KeychainCredentialStore()) {
        self.credentialStore = credentialStore
    }

    // MARK: - Token Management

    public var hasToken: Bool {
        credentialStore.hasToken(for: .deepseek)
    }

    public func saveToken(_ token: String) throws {
        try credentialStore.saveToken(token, for: .deepseek)
    }

    public func getToken() -> String? {
        try? credentialStore.getToken(for: .deepseek)
    }

    public func deleteToken() throws {
        try credentialStore.deleteToken(for: .deepseek)
    }

    // MARK: - UsageProvider

    func fetchSummary() async throws -> UserSummary {
        guard let token = getToken() else {
            throw ProviderError.notAuthenticated
        }

        do {
            return try await api.fetchSummary(token: token)
        } catch let error as APIError {
            if case .platformError(let code, _) = error, code == 40003 || code == 401 {
                throw ProviderError.tokenExpired
            }
            throw ProviderError.serviceUnavailable(error.localizedDescription)
        } catch {
            throw ProviderError.unknown(error)
        }
    }

    public func fetchBalance() async throws -> BalanceSnapshot {
        let summary = try await fetchSummary()
        let wallet = summary.normalWallets.first
        let cost = summary.monthlyCosts.first?.amount ?? "0"

        return BalanceSnapshot(
            balance: wallet?.balance ?? "0",
            currency: wallet?.currency ?? "CNY",
            monthlyUsage: summary.monthlyTokenUsage,
            monthlyCost: String(format: "%.2f", Double(cost) ?? 0),
            isAvailable: true,
            availableTokens: summary.totalAvailableTokenEstimation,
            updatedAt: Date()
        )
    }

    public func fetchUsage(month: Int, year: Int) async throws -> UsageSnapshot {
        guard let token = getToken() else {
            throw ProviderError.notAuthenticated
        }

        do {
            async let amount = try? api.fetchUsageAmount(token: token, month: month, year: year)
            async let cost = try? api.fetchUsageCost(token: token, month: month, year: year)
            let result = await (amount, cost)

            guard result.0 != nil || result.1 != nil else {
                throw ProviderError.serviceUnavailable("无法获取用量详情")
            }

            return UsageSnapshot(
                amount: result.0,
                cost: result.1,
                updatedAt: Date()
            )
        } catch let error as APIError {
            if case .platformError(let code, _) = error, code == 40003 || code == 401 {
                throw ProviderError.tokenExpired
            }
            throw ProviderError.serviceUnavailable(error.localizedDescription)
        } catch {
            throw ProviderError.unknown(error)
        }
    }
}
