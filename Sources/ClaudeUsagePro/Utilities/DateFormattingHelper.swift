import Foundation

/// Centralized utility for date formatting operations used across the app.
/// Consolidates date parsing and formatting to ensure consistency and avoid duplication.
enum DateFormattingHelper {

    // MARK: - ISO8601 Parsers

    /// Primary ISO8601 formatter with fractional seconds support
    /// Note: ISO8601DateFormatter is not thread-safe, so we protect access with a lock
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Fallback ISO8601 formatter without fractional seconds
    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Lock for thread-safe access to ISO8601 formatters
    private static let iso8601FormatterLock = NSLock()

    // MARK: - Display Formatters

    /// Formatter for date display (e.g., "Thu 8:59 PM")
    /// Note: DateFormatter is not thread-safe, so we protect access with a lock
    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E h:mm a"
        // Use current locale and timezone for user-friendly display
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Lock for thread-safe access to displayDateFormatter
    private static let displayFormatterLock = NSLock()

    // MARK: - Public API

    /// Parse an ISO8601 date string, trying with and without fractional seconds.
    /// - Parameter isoDate: The ISO8601 formatted date string
    /// - Returns: The parsed Date, or nil if parsing failed
    static func parseISO8601(_ isoDate: String) -> Date? {
        iso8601FormatterLock.withLock {
            iso8601Formatter.date(from: isoDate) ?? iso8601FallbackFormatter.date(from: isoDate)
        }
    }

    /// Formats an ISO date string into a human-readable time remaining string.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "3h 21m" or "Ready" if time has passed
    static func formatResetTime(isoDate: String) -> String {
        guard let date = parseISO8601(isoDate) else {
            Log.debug(Log.Category.app, "Failed to parse ISO8601 date: \(isoDate.prefix(50))")
            return isoDate
        }
        return formatTimeRemaining(date)
    }

    /// Formats a Date into a human-readable time remaining string.
    /// - Parameters:
    ///   - date: The target date
    ///   - referenceDate: The reference date to calculate from (defaults to now)
    /// - Returns: Formatted string like "3h 21m", "2d 5h", "<1m", or "Ready" if time has passed
    static func formatTimeRemaining(_ date: Date, referenceDate: Date = Date()) -> String {
        let diff = date.timeIntervalSince(referenceDate)
        if diff <= 0 { return Constants.Status.ready }

        let totalSeconds = Int(diff)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let mins = (totalSeconds % 3600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours == 0 && mins == 0 {
            return "<1m"
        }
        return "\(hours)h \(mins)m"
    }

    /// Formats an ISO date string into a human-readable date display.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "Thu 8:59 PM"
    static func formatResetDate(isoDate: String) -> String {
        guard let date = parseISO8601(isoDate) else {
            Log.debug(Log.Category.app, "Failed to parse ISO8601 date for display: \(isoDate.prefix(50))")
            return isoDate
        }
        return formatDateDisplay(date)
    }

    /// Formats a Date into a display string.
    /// - Parameters:
    ///   - date: The date to format
    ///   - locale: The locale to use (defaults to current locale)
    ///   - timeZone: The timezone to use (defaults to current timezone)
    /// - Returns: Formatted string like "Thu 8:59 PM"
    static func formatDateDisplay(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        displayFormatterLock.withLock {
            displayDateFormatter.locale = locale
            displayDateFormatter.timeZone = timeZone
            return displayDateFormatter.string(from: date)
        }
    }
}
