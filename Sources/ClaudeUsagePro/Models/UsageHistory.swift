import Foundation

/// A single historical usage data point
struct UsageDataPoint: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let sessionPercentage: Double
    let weeklyPercentage: Double
    let sonnetPercentage: Double?

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionPercentage: Double,
        weeklyPercentage: Double,
        sonnetPercentage: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionPercentage = sessionPercentage
        self.weeklyPercentage = weeklyPercentage
        self.sonnetPercentage = sonnetPercentage
    }
}

/// Thread-safe storage for usage history data.
/// Uses actor isolation for safe concurrent access.
actor UsageHistoryStore {
    /// Shared singleton instance
    static let shared = UsageHistoryStore()

    /// Maximum number of data points to store per account
    private let maxDataPoints = 48  // At 5-min intervals = 4 hours of data

    /// Historical data keyed by account ID
    private var history: [UUID: [UsageDataPoint]] = [:]

    /// Records a new usage data point for an account.
    /// - Parameters:
    ///   - usageData: The current usage data
    ///   - accountId: The account's unique identifier
    func record(_ usageData: UsageData, for accountId: UUID) {
        let dataPoint = usageData.toDataPoint()

        var accountHistory = history[accountId] ?? []
        accountHistory.append(dataPoint)

        // Trim to max size
        if accountHistory.count > maxDataPoints {
            accountHistory = Array(accountHistory.suffix(maxDataPoints))
        }

        history[accountId] = accountHistory
    }

    /// Retrieves usage history for an account.
    /// - Parameters:
    ///   - accountId: The account's unique identifier
    ///   - limit: Maximum number of data points to return (default: all available)
    /// - Returns: Array of historical data points, oldest first
    func getHistory(for accountId: UUID, limit: Int? = nil) -> [UsageDataPoint] {
        let accountHistory = history[accountId] ?? []

        if let limit = limit, limit < accountHistory.count {
            return Array(accountHistory.suffix(limit))
        }

        return accountHistory
    }

    /// Clears all history for an account.
    /// - Parameter accountId: The account's unique identifier
    func clear(for accountId: UUID) {
        history[accountId] = nil
    }

    /// Clears all stored history.
    func clearAll() {
        history.removeAll()
    }

    /// Returns the number of data points stored for an account.
    /// - Parameter accountId: The account's unique identifier
    /// - Returns: Number of stored data points
    func count(for accountId: UUID) -> Int {
        history[accountId]?.count ?? 0
    }
}

// MARK: - UsageData Extension for History

extension UsageData {
    /// Creates a UsageDataPoint from this usage data.
    func toDataPoint() -> UsageDataPoint {
        UsageDataPoint(
            sessionPercentage: sessionPercentage,
            weeklyPercentage: weeklyPercentage,
            sonnetPercentage: sonnetPercentage
        )
    }
}
