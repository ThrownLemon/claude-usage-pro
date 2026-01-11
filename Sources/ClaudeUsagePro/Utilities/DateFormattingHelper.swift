import Foundation

/// Centralized utility for date formatting operations used across the app.
/// Consolidates date parsing and formatting to ensure consistency and avoid duplication.
enum DateFormattingHelper {

    // MARK: - ISO8601 Parsers

    /// Primary ISO8601 formatter with fractional seconds support
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
        iso8601Formatter.date(from: isoDate) ?? iso8601FallbackFormatter.date(from: isoDate)
    }

    /// Formats an ISO date string into a human-readable time remaining string.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "3h 21m" or "Ready" if time has passed
    static func formatResetTime(isoDate: String) -> String {
        guard let date = parseISO8601(isoDate) else { return isoDate }
        return formatTimeRemaining(date)
    }

    /// Formats a Date into a human-readable time remaining string.
    /// - Parameter date: The target date
    /// - Returns: Formatted string like "3h 21m" or "Ready" if time has passed
    static func formatTimeRemaining(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return Constants.Status.ready }

        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)h \(mins)m"
    }

    /// Formats an ISO date string into a human-readable date display.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "Thu 8:59 PM"
    static func formatResetDate(isoDate: String) -> String {
        guard let date = parseISO8601(isoDate) else { return isoDate }
        return formatDateDisplay(date)
    }

    /// Formats a Date into a display string.
    /// - Parameter date: The date to format
    /// - Returns: Formatted string like "Thu 8:59 PM"
    static func formatDateDisplay(_ date: Date) -> String {
        displayFormatterLock.lock()
        defer { displayFormatterLock.unlock() }
        return displayDateFormatter.string(from: date)
    }
}
