import XCTest
@testable import DeepLink

final class CredentialStoreTests: XCTestCase {
    let store = KeychainCredentialStore()
    let provider = ProviderID.deepseek

    override func tearDown() {
        try? store.deleteToken(for: provider)
        super.tearDown()
    }

    func testSaveAndReadToken() throws {
        try store.saveToken("test-token-123", for: provider)
        let token = try store.getToken(for: provider)
        XCTAssertEqual(token, "test-token-123")
    }

    func testDeleteToken() throws {
        try store.saveToken("test-token-123", for: provider)
        try store.deleteToken(for: provider)
        let token = try store.getToken(for: provider)
        XCTAssertNil(token)
    }

    func testHasTokenReturnsCorrectValues() throws {
        XCTAssertFalse(store.hasToken(for: provider))
        try store.saveToken("test-token-123", for: provider)
        XCTAssertTrue(store.hasToken(for: provider))
        try store.deleteToken(for: provider)
        XCTAssertFalse(store.hasToken(for: provider))
    }

    func testMigrateLegacyTokenIfNeeded() throws {
        // No token in keychain and no legacy UserDefaults token
        try store.deleteToken(for: provider)
        XCTAssertNoThrow(try store.migrateLegacyTokenIfNeeded(for: provider))
        XCTAssertFalse(store.hasToken(for: provider))
    }

    func testBrokerSignOutKeepsCloudModeSelected() async throws {
        UserDefaults.standard.set(AgentConnectionMode.broker.rawValue, forKey: BrokerDefaults.connectionModeKey)
        let client = RemoteBrokerClient()

        try await client.signOut()

        XCTAssertEqual(
            UserDefaults.standard.string(forKey: BrokerDefaults.connectionModeKey),
            AgentConnectionMode.broker.rawValue
        )
    }
}
