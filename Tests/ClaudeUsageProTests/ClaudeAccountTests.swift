import XCTest
@testable import ClaudeUsagePro

final class ClaudeAccountTests: XCTestCase {

    // MARK: - Account Type Tests

    func testAccountTypeCoding() throws {
        // Given
        let types: [AccountType] = [.claude, .cursor, .glm]

        for type in types {
            // When - encode and decode
            let data = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(AccountType.self, from: data)

            // Then
            XCTAssertEqual(decoded, type)
        }
    }

    func testAccountTypeRawValues() {
        XCTAssertEqual(AccountType.claude.rawValue, "claude")
        XCTAssertEqual(AccountType.cursor.rawValue, "cursor")
        XCTAssertEqual(AccountType.glm.rawValue, "glm")
    }

    // MARK: - Account Initialization Tests

    func testClaudeAccountWithCookiesInit() {
        // Given
        let name = "Test Account"

        // When
        let account = ClaudeAccount(name: name, cookies: [])

        // Then
        XCTAssertEqual(account.name, name)
        XCTAssertEqual(account.type, .claude)
        XCTAssertTrue(account.cookieProps.isEmpty)
        XCTAssertNil(account.apiToken)
        XCTAssertNil(account.oauthToken)
    }

    func testClaudeAccountWithOAuthInit() {
        // Given
        let name = "OAuth Account"
        let token = "sk-ant-oat-test-token"
        let refreshToken = "refresh-token"

        // When
        let account = ClaudeAccount(name: name, oauthToken: token, refreshToken: refreshToken)

        // Then
        XCTAssertEqual(account.name, name)
        XCTAssertEqual(account.type, .claude)
        XCTAssertEqual(account.oauthToken, token)
        XCTAssertEqual(account.oauthRefreshToken, refreshToken)
        XCTAssertTrue(account.usesOAuth)
    }

    func testGLMAccountInit() {
        // Given
        let name = "GLM Account"
        let token = "glm-api-token"

        // When
        let account = ClaudeAccount(name: name, apiToken: token)

        // Then
        XCTAssertEqual(account.name, name)
        XCTAssertEqual(account.type, .glm)
        XCTAssertEqual(account.apiToken, token)
        XCTAssertTrue(account.cookieProps.isEmpty)
    }

    // MARK: - Convenience Properties Tests

    func testUsesOAuthWithToken() {
        // Given
        let account = ClaudeAccount(name: "Test", oauthToken: "test-token")

        // Then
        XCTAssertTrue(account.usesOAuth)
    }

    func testUsesOAuthWithoutToken() {
        // Given
        let account = ClaudeAccount(name: "Test", cookies: [])

        // Then
        XCTAssertFalse(account.usesOAuth)
    }

    func testUsesOAuthWithEmptyToken() {
        // Given
        var account = ClaudeAccount(name: "Test", cookies: [])
        account.oauthToken = ""

        // Then
        XCTAssertFalse(account.usesOAuth)
    }

    func testHasCredentialsClaudeWithCookies() {
        // Given - create account then manually set cookieProps
        var account = ClaudeAccount(name: "Test", cookies: [])
        account.cookieProps = [["name": "session", "value": "test"]]

        // Then
        XCTAssertTrue(account.hasCredentials)
    }

    func testHasCredentialsClaudeWithOAuth() {
        // Given
        let account = ClaudeAccount(name: "Test", oauthToken: "test-token")

        // Then
        XCTAssertTrue(account.hasCredentials)
    }

    func testHasCredentialsGLMWithToken() {
        // Given
        let account = ClaudeAccount(name: "Test", apiToken: "test-token")

        // Then
        XCTAssertTrue(account.hasCredentials)
    }

    func testHasCredentialsEmpty() {
        // Given
        let account = ClaudeAccount(name: "Test", cookies: [])

        // Then
        XCTAssertFalse(account.hasCredentials)
    }

    // MARK: - Limit Details Tests

    func testLimitDetailsWithUsageData() {
        // Given
        var account = ClaudeAccount(name: "Test", cookies: [])
        account.usageData = UsageData(
            sessionPercentage: 0.5,
            sessionReset: "Ready",
            sessionResetDisplay: "Ready",
            weeklyPercentage: 0.3,
            weeklyReset: "Ready",
            weeklyResetDisplay: "Ready",
            tier: "Pro",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: nil
        )

        // Then
        XCTAssertEqual(account.limitDetails, "Pro")
    }

    func testLimitDetailsWithoutUsageData() {
        // Given
        let account = ClaudeAccount(name: "Test", cookies: [])

        // Then
        XCTAssertEqual(account.limitDetails, Constants.Status.fetching)
    }

    // MARK: - Coding Tests

    func testAccountCodingExcludesSensitiveData() throws {
        // Given - account with sensitive data
        var account = ClaudeAccount(name: "Test", oauthToken: "secret-token", refreshToken: "refresh-secret")
        account.apiToken = "api-secret"
        account.cookieProps = [["name": "session", "value": "cookie-secret"]]

        // When - encode
        let data = try JSONEncoder().encode(account)
        let json = String(data: data, encoding: .utf8)!

        // Then - sensitive data should NOT be in JSON
        XCTAssertFalse(json.contains("secret-token"))
        XCTAssertFalse(json.contains("refresh-secret"))
        XCTAssertFalse(json.contains("api-secret"))
        XCTAssertFalse(json.contains("cookie-secret"))
    }

    func testAccountCodingPreservesNonSensitiveData() throws {
        // Given
        var account = ClaudeAccount(name: "Test Account", cookies: [])
        account.usageData = UsageData(
            sessionPercentage: 0.5,
            sessionReset: "Ready",
            sessionResetDisplay: "Ready",
            weeklyPercentage: 0.3,
            weeklyReset: "Ready",
            weeklyResetDisplay: "Ready",
            tier: "Pro",
            email: "test@example.com",
            fullName: nil,
            orgName: nil,
            planType: nil
        )

        // When - encode and decode
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(ClaudeAccount.self, from: data)

        // Then
        XCTAssertEqual(decoded.id, account.id)
        XCTAssertEqual(decoded.name, account.name)
        XCTAssertEqual(decoded.type, account.type)
        XCTAssertEqual(decoded.usageData?.tier, "Pro")
    }

    // MARK: - Hashable/Identifiable Tests

    func testAccountHashableById() {
        // Given
        let id = UUID()
        let account1 = ClaudeAccount(id: id, name: "Account 1", cookies: [], usageData: nil)
        let account2 = ClaudeAccount(id: id, name: "Account 2", cookies: [], usageData: nil)

        // Then - accounts with same ID should be equal
        XCTAssertEqual(account1, account2)
        XCTAssertEqual(account1.hashValue, account2.hashValue)
    }

    func testAccountNotEqualDifferentIds() {
        // Given
        let account1 = ClaudeAccount(name: "Account", cookies: [])
        let account2 = ClaudeAccount(name: "Account", cookies: [])

        // Then - different UUIDs mean different accounts
        XCTAssertNotEqual(account1, account2)
    }

    // MARK: - Needs Reauth Tests

    func testNeedsReauthDefaultFalse() {
        // Given
        let account = ClaudeAccount(name: "Test", cookies: [])

        // Then
        XCTAssertFalse(account.needsReauth)
    }

    func testNeedsReauthCanBeSet() {
        // Given
        var account = ClaudeAccount(name: "Test", cookies: [])

        // When
        account.needsReauth = true

        // Then
        XCTAssertTrue(account.needsReauth)
    }
}
