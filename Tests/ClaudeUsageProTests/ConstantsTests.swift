import XCTest
@testable import ClaudeUsagePro

final class ConstantsTests: XCTestCase {

    // MARK: - Status Constants Tests

    func testStatusReady() {
        XCTAssertEqual(Constants.Status.ready, "Ready")
    }

    func testStatusResetsInPrefix() {
        XCTAssertEqual(Constants.Status.resetsInPrefix, "Resets in")
    }

    func testStatusFetching() {
        XCTAssertEqual(Constants.Status.fetching, "Fetching...")
    }

    func testStatusUnknown() {
        XCTAssertEqual(Constants.Status.unknown, "Unknown")
    }

    func testStatusRefreshing() {
        XCTAssertEqual(Constants.Status.refreshing, "Refreshing...")
    }

    // MARK: - Usage Thresholds Tests

    func testUsageThresholdsValues() {
        XCTAssertEqual(Constants.UsageThresholds.low, 0.50)
        XCTAssertEqual(Constants.UsageThresholds.medium, 0.75)
        XCTAssertEqual(Constants.UsageThresholds.high, 0.90)
    }

    func testUsageThresholdsOrdering() {
        XCTAssertLessThan(Constants.UsageThresholds.low, Constants.UsageThresholds.medium)
        XCTAssertLessThan(Constants.UsageThresholds.medium, Constants.UsageThresholds.high)
    }

    // MARK: - Timeouts Tests

    func testTimeoutValues() {
        XCTAssertGreaterThan(Constants.Timeouts.pingTimeout, 0)
        XCTAssertGreaterThan(Constants.Timeouts.defaultRefreshInterval, 0)
        XCTAssertGreaterThan(Constants.Timeouts.networkRequestTimeout, 0)
    }

    func testDefaultRefreshInterval() {
        // Default should be 5 minutes (300 seconds)
        XCTAssertEqual(Constants.Timeouts.defaultRefreshInterval, 300)
    }

    // MARK: - Notifications Tests

    func testNotificationCooldownInterval() {
        // Should be 5 minutes (300 seconds)
        XCTAssertEqual(Constants.Notifications.cooldownInterval, 300)
    }

    // MARK: - OAuth Configuration Tests

    func testOAuthClientIdNotEmpty() {
        XCTAssertFalse(Constants.OAuth.clientId.isEmpty)
    }

    func testOAuthURLsAreValid() {
        XCTAssertNotNil(URL(string: Constants.OAuth.authURL))
        XCTAssertNotNil(URL(string: Constants.OAuth.tokenURL))
        XCTAssertNotNil(URL(string: Constants.OAuth.redirectURI))
    }

    // MARK: - Anthropic API Tests

    func testAnthropicAPIBaseURL() {
        XCTAssertTrue(Constants.AnthropicAPI.baseURL.starts(with: "https://"))
        XCTAssertNotNil(URL(string: Constants.AnthropicAPI.baseURL))
    }

    func testAnthropicAPIRetryConfig() {
        XCTAssertGreaterThan(Constants.AnthropicAPI.maxRetries, 0)
        XCTAssertGreaterThan(Constants.AnthropicAPI.baseBackoffSeconds, 0)
        XCTAssertGreaterThan(Constants.AnthropicAPI.rateLimitBackoffSeconds, 0)
    }

    // MARK: - Window Size Tests

    func testWindowSizeReasonable() {
        XCTAssertGreaterThan(Constants.WindowSize.width, 200)
        XCTAssertGreaterThan(Constants.WindowSize.height, 200)
        XCTAssertLessThan(Constants.WindowSize.width, 1000)
        XCTAssertLessThan(Constants.WindowSize.height, 1000)
    }

    // MARK: - UserDefaults Keys Tests

    func testUserDefaultsKeysUnique() {
        // Collect all UserDefaults keys from Constants and NotificationSettings
        let keys = [
            // App settings from Constants.UserDefaultsKeys
            Constants.UserDefaultsKeys.refreshInterval,
            Constants.UserDefaultsKeys.autoWakeUp,
            Constants.UserDefaultsKeys.savedAccounts,
            Constants.UserDefaultsKeys.debugModeEnabled,
            Constants.UserDefaultsKeys.keychainMigrationComplete,
            Constants.UserDefaultsKeys.selectedTheme,
            Constants.UserDefaultsKeys.colorSchemeMode,
            // Notification settings from NotificationSettings
            NotificationSettings.enabledKey,
            NotificationSettings.sessionReadyEnabledKey,
            NotificationSettings.sessionThreshold1EnabledKey,
            NotificationSettings.sessionThreshold2EnabledKey,
            NotificationSettings.weeklyThreshold1EnabledKey,
            NotificationSettings.weeklyThreshold2EnabledKey,
            NotificationSettings.threshold1ValueKey,
            NotificationSettings.threshold2ValueKey
        ]

        // All keys should be unique
        let uniqueKeys = Set(keys)
        XCTAssertEqual(keys.count, uniqueKeys.count, "UserDefaults keys should be unique")
    }
}
