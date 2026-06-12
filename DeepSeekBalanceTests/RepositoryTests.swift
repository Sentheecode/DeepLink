import XCTest
@testable import DeepSeekBalance

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
}
