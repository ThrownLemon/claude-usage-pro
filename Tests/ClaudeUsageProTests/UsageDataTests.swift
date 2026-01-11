import XCTest
@testable import ClaudeUsagePro

final class UsageDataTests: XCTestCase {

    // MARK: - Session Reset Display Formatting Tests

    func testFormatSessionResetDisplayReady() {
        // Given
        let sessionReset = Constants.Status.ready

        // When
        let result = UsageData.formatSessionResetDisplay(sessionReset)

        // Then
        XCTAssertEqual(result, Constants.Status.ready)
    }

    func testFormatSessionResetDisplayEmpty() {
        // Given
        let sessionReset = ""

        // When
        let result = UsageData.formatSessionResetDisplay(sessionReset)

        // Then
        XCTAssertEqual(result, "")
    }

    func testFormatSessionResetDisplayWithTime() {
        // Given
        let sessionReset = "3h 21m"

        // When
        let result = UsageData.formatSessionResetDisplay(sessionReset)

        // Then
        XCTAssertEqual(result, "\(Constants.Status.resetsInPrefix) 3h 21m")
    }

    func testFormatSessionResetDisplayWithShortTime() {
        // Given
        let sessionReset = "45m"

        // When
        let result = UsageData.formatSessionResetDisplay(sessionReset)

        // Then
        XCTAssertEqual(result, "\(Constants.Status.resetsInPrefix) 45m")
    }

    // MARK: - UsageData Initialization Tests

    func testUsageDataCreation() {
        // Given/When
        let usageData = UsageData(
            sessionPercentage: 0.75,
            sessionReset: "2h 30m",
            sessionResetDisplay: "Resets in 2h 30m",
            weeklyPercentage: 0.50,
            weeklyReset: "Thu 8:00 AM",
            weeklyResetDisplay: "Thu 8:00 AM",
            tier: "Pro",
            email: "test@example.com",
            fullName: "Test User",
            orgName: "Test Org",
            planType: "Pro"
        )

        // Then
        XCTAssertEqual(usageData.sessionPercentage, 0.75)
        XCTAssertEqual(usageData.weeklyPercentage, 0.50)
        XCTAssertEqual(usageData.tier, "Pro")
        XCTAssertEqual(usageData.email, "test@example.com")
    }

    func testUsageDataEquality() {
        // Given
        let usageData1 = UsageData(
            sessionPercentage: 0.75,
            sessionReset: "2h 30m",
            sessionResetDisplay: "Resets in 2h 30m",
            weeklyPercentage: 0.50,
            weeklyReset: "Thu 8:00 AM",
            weeklyResetDisplay: "Thu 8:00 AM",
            tier: "Pro",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: nil
        )

        let usageData2 = UsageData(
            sessionPercentage: 0.75,
            sessionReset: "2h 30m",
            sessionResetDisplay: "Resets in 2h 30m",
            weeklyPercentage: 0.50,
            weeklyReset: "Thu 8:00 AM",
            weeklyResetDisplay: "Thu 8:00 AM",
            tier: "Pro",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: nil
        )

        // Then
        XCTAssertEqual(usageData1, usageData2)
    }

    func testUsageDataCoding() throws {
        // Given
        let usageData = UsageData(
            sessionPercentage: 0.75,
            sessionReset: "2h 30m",
            sessionResetDisplay: "Resets in 2h 30m",
            weeklyPercentage: 0.50,
            weeklyReset: "Thu 8:00 AM",
            weeklyResetDisplay: "Thu 8:00 AM",
            tier: "Pro",
            email: "test@example.com",
            fullName: "Test User",
            orgName: "Test Org",
            planType: "Pro"
        )

        // When - encode and decode
        let encoder = JSONEncoder()
        let data = try encoder.encode(usageData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UsageData.self, from: data)

        // Then
        XCTAssertEqual(decoded, usageData)
    }

    // MARK: - OAuth Extended Fields Tests

    func testUsageDataWithOAuthFields() {
        // Given/When
        let usageData = UsageData(
            sessionPercentage: 0.75,
            sessionReset: "2h 30m",
            sessionResetDisplay: "Resets in 2h 30m",
            weeklyPercentage: 0.50,
            weeklyReset: "Thu 8:00 AM",
            weeklyResetDisplay: "Thu 8:00 AM",
            tier: "Max",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: "Max",
            opusPercentage: 0.30,
            opusReset: "Fri 10:00 AM",
            sonnetPercentage: 0.45,
            sonnetReset: "Sat 2:00 PM"
        )

        // Then
        XCTAssertEqual(usageData.opusPercentage, 0.30)
        XCTAssertEqual(usageData.opusReset, "Fri 10:00 AM")
        XCTAssertEqual(usageData.sonnetPercentage, 0.45)
        XCTAssertEqual(usageData.sonnetReset, "Sat 2:00 PM")
    }

    // MARK: - GLM Fields Tests

    func testUsageDataWithGLMFields() {
        // Given/When
        let usageData = UsageData(
            sessionPercentage: 0.60,
            sessionReset: Constants.Status.ready,
            sessionResetDisplay: Constants.Status.ready,
            weeklyPercentage: 0.40,
            weeklyReset: Constants.Status.ready,
            weeklyResetDisplay: "200 / 500 tokens",
            tier: "GLM Coding Plan",
            email: nil,
            fullName: nil,
            orgName: "GLM",
            planType: "Coding Plan",
            glmSessionUsed: 300.0,
            glmSessionLimit: 500.0,
            glmMonthlyUsed: 2000.0,
            glmMonthlyLimit: 5000.0
        )

        // Then
        XCTAssertEqual(usageData.glmSessionUsed, 300.0)
        XCTAssertEqual(usageData.glmSessionLimit, 500.0)
        XCTAssertEqual(usageData.glmMonthlyUsed, 2000.0)
        XCTAssertEqual(usageData.glmMonthlyLimit, 5000.0)
    }
}
