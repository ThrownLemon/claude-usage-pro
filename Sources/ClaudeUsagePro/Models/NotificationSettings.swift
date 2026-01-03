import Foundation

// MARK: - Threshold Configuration

/// Centralized configuration for usage thresholds
/// All threshold values, notification types, and settings are defined here
struct ThresholdConfig: Identifiable {
    let id: String                                  // Unique identifier for this threshold
    let defaultThreshold: Double                    // Default threshold value (e.g., 0.75, 0.90)
    let thresholdKey: String                        // UserDefaults key for the threshold value
    let notificationType: NotificationManager.NotificationType
    let enabledKey: String                          // UserDefaults key for this threshold's toggle
    let defaultEnabled: Bool                        // Default value for the toggle
    let label: String                               // UI label for settings
    let isSession: Bool                             // true = session, false = weekly

    /// Current threshold value from UserDefaults (or default)
    var threshold: Double {
        let stored = UserDefaults.standard.double(forKey: thresholdKey)
        return stored > 0 ? stored : defaultThreshold
    }

    /// Formatted percentage string (e.g., "75%")
    var percentageLabel: String {
        "\(Int(threshold * 100))%"
    }
}

// MARK: - Centralized Threshold Definitions

/// All threshold configurations defined in one place
/// To add/modify thresholds, update this array only
enum ThresholdDefinitions {
    // MARK: - UserDefaults Keys for Threshold Values
    // Note: Weekly thresholds share the same value keys as session thresholds
    // so users configure one value that applies to both session and weekly alerts

    static let sessionThreshold1ValueKey = "threshold1Value"
    static let sessionThreshold2ValueKey = "threshold2Value"

    // MARK: - Default Values

    static let defaultThreshold1: Double = 0.75
    static let defaultThreshold2: Double = 0.90

    // MARK: - Threshold Configurations

    // Session thresholds
    static let sessionThreshold1 = ThresholdConfig(
        id: "sessionThreshold1",
        defaultThreshold: defaultThreshold1,
        thresholdKey: sessionThreshold1ValueKey,
        notificationType: .sessionThreshold75,
        enabledKey: "notificationSessionThreshold1Enabled",
        defaultEnabled: true,
        label: "Session Threshold 1",
        isSession: true
    )

    static let sessionThreshold2 = ThresholdConfig(
        id: "sessionThreshold2",
        defaultThreshold: defaultThreshold2,
        thresholdKey: sessionThreshold2ValueKey,
        notificationType: .sessionThreshold90,
        enabledKey: "notificationSessionThreshold2Enabled",
        defaultEnabled: true,
        label: "Session Threshold 2",
        isSession: true
    )

    // Weekly thresholds (share the same value keys as session for unified configuration)
    static let weeklyThreshold1 = ThresholdConfig(
        id: "weeklyThreshold1",
        defaultThreshold: defaultThreshold1,
        thresholdKey: sessionThreshold1ValueKey,  // Uses same value as session threshold 1
        notificationType: .weeklyThreshold75,
        enabledKey: "notificationWeeklyThreshold1Enabled",
        defaultEnabled: true,
        label: "Weekly Threshold 1",
        isSession: false
    )

    static let weeklyThreshold2 = ThresholdConfig(
        id: "weeklyThreshold2",
        defaultThreshold: defaultThreshold2,
        thresholdKey: sessionThreshold2ValueKey,  // Uses same value as session threshold 2
        notificationType: .weeklyThreshold90,
        enabledKey: "notificationWeeklyThreshold2Enabled",
        defaultEnabled: true,
        label: "Weekly Threshold 2",
        isSession: false
    )

    /// All session thresholds for iteration
    static let sessionThresholds: [ThresholdConfig] = [
        sessionThreshold1,
        sessionThreshold2
    ]

    /// All weekly thresholds for iteration
    static let weeklyThresholds: [ThresholdConfig] = [
        weeklyThreshold1,
        weeklyThreshold2
    ]

    /// All thresholds combined
    static let allThresholds: [ThresholdConfig] = sessionThresholds + weeklyThresholds

    /// Get fresh threshold configs with current values from UserDefaults
    static func currentSessionThresholds() -> [ThresholdConfig] {
        sessionThresholds
    }

    static func currentWeeklyThresholds() -> [ThresholdConfig] {
        weeklyThresholds
    }
}

// MARK: - Notification Settings

// UserDefaults-backed notification settings
// Uses @AppStorage pattern for reactive UI updates
struct NotificationSettings {
    // MARK: - UserDefaults Keys

    static let enabledKey = "notificationsEnabled"
    static let sessionReadyEnabledKey = "notificationSessionReadyEnabled"

    // Threshold enabled keys (derived from ThresholdDefinitions)
    static let sessionThreshold1EnabledKey = ThresholdDefinitions.sessionThreshold1.enabledKey
    static let sessionThreshold2EnabledKey = ThresholdDefinitions.sessionThreshold2.enabledKey
    static let weeklyThreshold1EnabledKey = ThresholdDefinitions.weeklyThreshold1.enabledKey
    static let weeklyThreshold2EnabledKey = ThresholdDefinitions.weeklyThreshold2.enabledKey

    // Threshold value keys (derived from ThresholdDefinitions)
    // Note: These are shared between session and weekly thresholds
    static let threshold1ValueKey = ThresholdDefinitions.sessionThreshold1ValueKey
    static let threshold2ValueKey = ThresholdDefinitions.sessionThreshold2ValueKey

    // MARK: - Default Values

    static let defaultEnabled = true
    static let defaultSessionReadyEnabled = true
    static let defaultThreshold1 = ThresholdDefinitions.defaultThreshold1
    static let defaultThreshold2 = ThresholdDefinitions.defaultThreshold2

    // Threshold enabled defaults (derived from ThresholdDefinitions)
    static let defaultSessionThreshold1Enabled = ThresholdDefinitions.sessionThreshold1.defaultEnabled
    static let defaultSessionThreshold2Enabled = ThresholdDefinitions.sessionThreshold2.defaultEnabled
    static let defaultWeeklyThreshold1Enabled = ThresholdDefinitions.weeklyThreshold1.defaultEnabled
    static let defaultWeeklyThreshold2Enabled = ThresholdDefinitions.weeklyThreshold2.defaultEnabled

    // MARK: - Helper Methods

    /// Check if a specific notification type should be sent
    static func shouldSend(type: NotificationManager.NotificationType) -> Bool {
        let defaults = UserDefaults.standard

        // Check master toggle first
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? defaultEnabled
        guard enabled else { return false }

        // Handle session ready separately (not a threshold)
        if type == .sessionReady {
            return defaults.object(forKey: sessionReadyEnabledKey) as? Bool ?? defaultSessionReadyEnabled
        }

        // Find the threshold config for this notification type
        if let config = ThresholdDefinitions.allThresholds.first(where: { $0.notificationType == type }) {
            return defaults.object(forKey: config.enabledKey) as? Bool ?? config.defaultEnabled
        }

        return false
    }
}
