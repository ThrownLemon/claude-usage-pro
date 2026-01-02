import Foundation

struct NotificationSettings: Codable {
    var enabled: Bool

    // Session notification toggles
    var sessionThreshold75Enabled: Bool
    var sessionThreshold90Enabled: Bool
    var sessionReadyEnabled: Bool

    // Weekly notification toggles
    var weeklyThreshold75Enabled: Bool
    var weeklyThreshold90Enabled: Bool

    // Default settings: all notifications enabled
    static let `default` = NotificationSettings(
        enabled: true,
        sessionThreshold75Enabled: true,
        sessionThreshold90Enabled: true,
        sessionReadyEnabled: true,
        weeklyThreshold75Enabled: true,
        weeklyThreshold90Enabled: true
    )

    // UserDefaults persistence
    private static let key = "notificationSettings"

    static func load() -> NotificationSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(NotificationSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: NotificationSettings.key)
        }
    }

    // Helper to check if a specific notification type should be sent
    func shouldSend(type: NotificationManager.NotificationType) -> Bool {
        guard enabled else { return false }

        switch type {
        case .sessionThreshold75:
            return sessionThreshold75Enabled
        case .sessionThreshold90:
            return sessionThreshold90Enabled
        case .sessionReady:
            return sessionReadyEnabled
        case .weeklyThreshold75:
            return weeklyThreshold75Enabled
        case .weeklyThreshold90:
            return weeklyThreshold90Enabled
        }
    }
}
