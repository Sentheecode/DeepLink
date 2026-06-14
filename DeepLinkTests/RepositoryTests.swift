import XCTest
@testable import DeepLink

final class RepositoryTests: XCTestCase {

    @MainActor
    func testRepositoryDoesNotSaveBadDataOnFailure() async {
        let repo = UsageRepository.shared
        let result = await repo.refresh(month: 6, year: 2026)
        XCTAssertFalse(result.dashboard.isAvailable)
        XCTAssertEqual(result.dashboard.balance, "0")
        XCTAssertEqual(result.dashboard.currency, "CNY")
    }

    @MainActor
    func testDashboardStoreShowsIsLoadingCorrectly() async {
        let store = DashboardStore()
        XCTAssertFalse(store.isLoading, "isLoading should start as false")
        await store.refresh(month: 6, year: 2026)
        XCTAssertFalse(store.isLoading, "isLoading should be false after refresh completes")
        XCTAssertNotNil(store.snapshot)
        XCTAssertFalse(store.snapshot!.isAvailable)
    }

    @MainActor
    func testDashboardStoreClear() {
        let store = DashboardStore()
        store.clear()
        XCTAssertNil(store.snapshot)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.errorMessage)
    }

    func testTokenDomainCheck() {
        // 验证生产环境 isAllowedDeepSeekDomain 函数
        let valid: [(String, String)] = [
            ("platform.deepseek.com", "主域名"),
            ("auth.platform.deepseek.com", "子域名"),
        ]
        let invalid: [(String, String)] = [
            ("platform.deepseek.com.evil.com", "后缀绕过"),
            ("evil-platform.deepseek.com", "前缀不匹配"),
            ("deepseek.com", "父域名"),
            ("", "空字符串"),
        ]

        for (domain, desc) in valid {
            XCTAssertTrue(isAllowedDeepSeekDomain(domain), "\(domain) (\(desc)) 应被允许")
        }
        for (domain, desc) in invalid {
            XCTAssertFalse(isAllowedDeepSeekDomain(domain), "\(domain) (\(desc)) 应被拒绝")
        }
    }

    func testVoiceAudioFileRejectsMissingAndEmptyFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(VoiceAudioFile.isPlayable(filename: "missing.wav", directory: directory))

        let emptyFile = directory.appendingPathComponent("empty.wav")
        FileManager.default.createFile(atPath: emptyFile.path, contents: Data())
        XCTAssertFalse(VoiceAudioFile.isPlayable(filename: emptyFile.lastPathComponent, directory: directory))

        let corruptFile = directory.appendingPathComponent("corrupt.wav")
        FileManager.default.createFile(atPath: corruptFile.path, contents: Data(repeating: 1, count: 256))
        XCTAssertFalse(VoiceAudioFile.isPlayable(filename: corruptFile.lastPathComponent, directory: directory))
    }

    func testAgentInstallCommandUsesOneTimeInstallerURL() {
        let enrollmentURL = URL(string: "https://broker.example.com/channel/one-time-token")!

        XCTAssertEqual(
            AgentInstallInstructions.command(for: enrollmentURL),
            "curl -fsSL 'https://broker.example.com/channel/one-time-token/install.sh' | sh"
        )
    }

    func testHermesMessageParsesNumericAndStringIdentifiers() {
        let numeric = HermesMessage.parse([
            "id": 12887,
            "role": "user",
            "content": "数字消息",
            "created_at": "2026-06-14T00:00:00Z",
        ])
        let string = HermesMessage.parse([
            "id": "message-2",
            "role": "assistant",
            "content": "字符串消息",
        ])

        XCTAssertEqual(numeric?.id, "12887")
        XCTAssertEqual(numeric?.content, "数字消息")
        XCTAssertEqual(string?.id, "message-2")
    }

    func testHermesMessageMergeUpdatesExistingAndAppendsOnlyNewMessages() {
        let existing = [
            HermesMessage(id: "1", role: "user", content: "旧内容", createdAt: nil),
            HermesMessage(id: "2", role: "assistant", content: "回答", createdAt: nil),
        ]
        let incoming = [
            HermesMessage(id: "1", role: "user", content: "更新内容", createdAt: nil),
            HermesMessage(id: "3", role: "assistant", content: "新增回答", createdAt: nil),
        ]

        let merged = HermesMessage.merge(existing: existing, incoming: incoming)

        XCTAssertEqual(merged.map(\.id), ["1", "2", "3"])
        XCTAssertEqual(merged[0].content, "更新内容")
    }

    func testHermesMessageDisplayFiltersEmptyAndToolPayloads() {
        XCTAssertTrue(HermesMessage(id: "1", role: "user", content: "你好", createdAt: nil).isDisplayable)
        XCTAssertFalse(HermesMessage(id: "2", role: "assistant", content: "", createdAt: nil).isDisplayable)
        XCTAssertFalse(HermesMessage(id: "3", role: "tool", content: #"{"ok":true}"#, createdAt: nil).isDisplayable)
    }

    func testAgentSelectionUsesCurrentAgentsDeviceInsteadOfStaleSavedDevice() {
        let agent = AgentInfo(
            id: "hermes-agent",
            deviceId: "current-device",
            name: "Hermes",
            kind: "hermes",
            endpoint: "http://mac.local:8642",
            version: "0.16.0",
            status: "online",
            isOnline: true,
            capabilities: ["sessions"],
            skills: [],
            lastSeenAt: nil
        )

        let selected = AgentSelectionResolver.resolve(agents: [agent], preferredAgentID: "hermes-agent")

        XCTAssertEqual(selected?.id, "hermes-agent")
        XCTAssertEqual(selected?.deviceId, "current-device")
    }

    func testAgentSelectionFallsBackToFirstAvailableAgent() {
        let agent = AgentInfo(
            id: "available-agent",
            deviceId: "available-device",
            name: "Hermes",
            kind: "hermes",
            endpoint: nil,
            version: nil,
            status: "online",
            isOnline: true,
            capabilities: [],
            skills: [],
            lastSeenAt: nil
        )

        let selected = AgentSelectionResolver.resolve(agents: [agent], preferredAgentID: "removed-agent")

        XCTAssertEqual(selected?.id, "available-agent")
        XCTAssertEqual(selected?.deviceId, "available-device")
    }

    func testDeepSeekTokenCandidateExtractsNestedAndBearerValues() {
        XCTAssertEqual(
            DeepSeekTokenCandidate.values(
                key: "userToken",
                raw: #"{"value":"opaque-deepseek-token-1234567890","__version":"0"}"#
            ),
            ["opaque-deepseek-token-1234567890"]
        )
        XCTAssertEqual(
            DeepSeekTokenCandidate.values(
                key: "authorization",
                raw: "Bearer opaque-deepseek-token-abcdefghij"
            ),
            ["opaque-deepseek-token-abcdefghij"]
        )
    }

    func testDeepSeekTokenCandidateRejectsUnrelatedStorage() {
        XCTAssertEqual(
            DeepSeekTokenCandidate.values(key: "theme", raw: "dark-mode-and-other-preferences"),
            []
        )
        XCTAssertEqual(
            DeepSeekTokenCandidate.values(key: "auth", raw: "too-short"),
            []
        )
    }
}
