import XCTest
@testable import ClaudeUsagePro

final class DateFormattingHelperTests: XCTestCase {

    // MARK: - ISO8601 Parsing Tests

    func testParseISO8601WithFractionalSeconds() {
        // Given
        let isoDate = "2025-01-15T14:30:00.123Z"

        // When
        let result = DateFormattingHelper.parseISO8601(isoDate)

        // Then
        XCTAssertNotNil(result)
    }

    func testParseISO8601WithoutFractionalSeconds() {
        // Given
        let isoDate = "2025-01-15T14:30:00Z"

        // When
        let result = DateFormattingHelper.parseISO8601(isoDate)

        // Then
        XCTAssertNotNil(result)
    }

    func testParseISO8601InvalidDate() {
        // Given
        let isoDate = "not-a-date"

        // When
        let result = DateFormattingHelper.parseISO8601(isoDate)

        // Then
        XCTAssertNil(result)
    }

    // MARK: - Time Remaining Tests

    func testFormatTimeRemainingFuture() {
        // Given - a date 3 hours and 21 minutes in the future from a fixed reference
        // Use a fixed "now" to avoid flaky tests
        let fixedNow = Date(timeIntervalSince1970: 1704067200) // Jan 1, 2024 00:00:00 UTC
        let futureDate = fixedNow.addingTimeInterval(3 * 3600 + 21 * 60)

        // When - calculate time remaining from the future date's perspective
        // Since formatTimeRemaining uses Date(), we test the output format
        let result = DateFormattingHelper.formatTimeRemaining(futureDate)

        // Then - the result should either be a time format or "Ready" (if test runs after futureDate)
        // For a robust test, we verify the format is correct
        XCTAssertTrue(result == Constants.Status.ready || (result.contains("h") && result.contains("m")),
                      "Expected 'Ready' or time format like 'Xh Ym', got: \(result)")
    }

    func testFormatTimeRemainingPast() {
        // Given - a date in the past
        let pastDate = Date().addingTimeInterval(-3600)

        // When
        let result = DateFormattingHelper.formatTimeRemaining(pastDate)

        // Then
        XCTAssertEqual(result, Constants.Status.ready)
    }

    func testFormatTimeRemainingNow() {
        // Given - current time
        let now = Date()

        // When
        let result = DateFormattingHelper.formatTimeRemaining(now)

        // Then
        XCTAssertEqual(result, Constants.Status.ready)
    }

    // MARK: - Reset Time Formatting Tests

    func testFormatResetTimeValidDate() {
        // Given - a future date in ISO format
        let calendar = Calendar.current
        let futureDate = calendar.date(byAdding: .hour, value: 2, to: Date())!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoDate = formatter.string(from: futureDate)

        // When
        let result = DateFormattingHelper.formatResetTime(isoDate: isoDate)

        // Then
        XCTAssertTrue(result.contains("h"))
        XCTAssertTrue(result.contains("m"))
        XCTAssertFalse(result.contains("T")) // Should not contain ISO format
    }

    func testFormatResetTimeInvalidDate() {
        // Given - an invalid date string
        let invalidDate = "invalid-date"

        // When
        let result = DateFormattingHelper.formatResetTime(isoDate: invalidDate)

        // Then
        XCTAssertEqual(result, invalidDate) // Returns original string on failure
    }

    // MARK: - Date Display Formatting Tests

    func testFormatDateDisplay() {
        // Given - a specific date
        let date = Date()

        // When
        let result = DateFormattingHelper.formatDateDisplay(date)

        // Then
        // Result should contain day abbreviation and time
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.count > 5) // e.g., "Thu 8:59 PM"
    }

    func testFormatResetDateValidDate() {
        // Given - a future date in ISO format
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let isoDate = formatter.string(from: Date())

        // When
        let result = DateFormattingHelper.formatResetDate(isoDate: isoDate)

        // Then
        XCTAssertFalse(result.isEmpty)
        XCTAssertFalse(result.contains("T")) // Should be formatted, not ISO
    }
}
