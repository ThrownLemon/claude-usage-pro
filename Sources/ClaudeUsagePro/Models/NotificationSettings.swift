import Foundation

// UserDefaults-backed notification settings
// Uses @AppStorage pattern for reactive UI updates
struct NotificationSettings {
    // MARK: - UserDefaults Keys

    static let enabledKey = "notificationsEnabled"
    static let sessionThreshold75EnabledKey = "notificationSessionThreshold75Enabled"
    static let sessionThreshold90EnabledKey = "notificationSessionThreshold90Enabled"
    static let sessionReadyEnabledKey = "notificationSessionReadyEnabled"
    static let weeklyThreshold75EnabledKey = "notificationWeeklyThreshold75Enabled"
    static let weeklyThreshold90EnabledKey = "notificationWeeklyThreshold90Enabled"

    // MARK: - Default Values

    // All notifications enabled by default (75%, 90%, Ready)
    static let defaultEnabled = true
    static let defaultSessionThreshold75Enabled = true
    static let defaultSessionThreshold90Enabled = true
    static let defaultSessionReadyEnabled = true
    static let defaultWeeklyThreshold75Enabled = true
    static let defaultWeeklyThreshold90Enabled = true

    // MARK: - Helper Methods

    // Check if a specific notification type should be sent
    static func shouldSend(type: NotificationManager.NotificationType) -> Bool {
        let defaults = UserDefaults.standard

        // Check master toggle first
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? defaultEnabled
        guard enabled else { return false }

        // Check specific notification type toggle
        switch type {
        case .sessionThreshold75:
            return defaults.object(forKey: sessionThreshold75EnabledKey) as? Bool ?? defaultSessionThreshold75Enabled
        case .sessionThreshold90:
            return defaults.object(forKey: sessionThreshold90EnabledKey) as? Bool ?? defaultSessionThreshold90Enabled
        case .sessionReady:
            return defaults.object(forKey: sessionReadyEnabledKey) as? Bool ?? defaultSessionReadyEnabled
        case .weeklyThreshold75:
            return defaults.object(forKey: weeklyThreshold75EnabledKey) as? Bool ?? defaultWeeklyThreshold75Enabled
        case .weeklyThreshold90:
            return defaults.object(forKey: weeklyThreshold90EnabledKey) as? Bool ?? defaultWeeklyThreshold90Enabled
        }
    }
}
