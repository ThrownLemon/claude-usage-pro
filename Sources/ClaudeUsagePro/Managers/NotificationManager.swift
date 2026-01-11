import Foundation
import UserNotifications
import Combine
import os

/// Manages macOS user notifications for usage alerts and session ready events.
/// Handles permission requests, notification delivery, and rate limiting.
@MainActor
class NotificationManager: NSObject, ObservableObject {
    /// Shared singleton instance
    static let shared = NotificationManager()
    private let category = Log.Category.notifications

    /// The system notification center (may be nil when running outside app bundle)
    private var notificationCenter: UNUserNotificationCenter?
    /// Current notification authorization status
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    /// Whether the notification system is available
    @Published var isAvailable: Bool = false

    /// Called when notification permission is granted
    var onPermissionGranted: (() -> Void)?
    /// Called when notification permission is denied
    var onPermissionDenied: (() -> Void)?
    /// Called when a notification-related error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Rate Limiting

    /// Tracks last notification time per account per type to prevent spam
    /// Thread-safe access protected by notificationLock
    private var lastNotificationTimes: [String: Date] = [:]
    /// Lock for thread-safe access to lastNotificationTimes
    private let notificationLock = NSLock()
    /// Cooldown period between notifications of the same type
    private let cooldownInterval: TimeInterval = Constants.Notifications.cooldownInterval

    override init() {
        super.init()
        initializeNotificationCenter()
    }

    /// Safely initialize the notification center (may fail when running outside app bundle)
    private func initializeNotificationCenter() {
        // Check if we're running in a proper app bundle to avoid crash
        guard Bundle.main.bundleIdentifier != nil else {
            Log.warning(category, "No bundle identifier - notifications disabled (running via swift run?)")
            isAvailable = false
            return
        }

        let center = UNUserNotificationCenter.current()
        notificationCenter = center
        center.delegate = self
        isAvailable = true
        checkAuthorizationStatus()
    }

    // MARK: - Notification Types

    /// Types of notifications the app can send
    enum NotificationType {
        case sessionThreshold75
        case sessionThreshold90
        case weeklyThreshold75
        case weeklyThreshold90
        case sessionReady

        var identifier: String {
            switch self {
            case .sessionThreshold75:
                return "session.threshold.75"
            case .sessionThreshold90:
                return "session.threshold.90"
            case .weeklyThreshold75:
                return "weekly.threshold.75"
            case .weeklyThreshold90:
                return "weekly.threshold.90"
            case .sessionReady:
                return "session.ready"
            }
        }
    }

    // MARK: - Notification Content Builders

    /// Contains the text content for a notification
    struct NotificationContent {
        /// The notification title
        let title: String
        /// The notification body text
        let body: String
        /// Unique identifier for the notification
        let identifier: String
    }

    /// Builds notification content for a given notification type.
    /// - Parameters:
    ///   - type: The type of notification to build
    ///   - accountName: The name of the account this notification is for
    ///   - thresholdPercent: The threshold percentage to display (for threshold notifications)
    /// - Returns: A NotificationContent struct with title, body, and identifier
    func buildNotificationContent(
        type: NotificationType,
        accountName: String,
        thresholdPercent: Int? = nil
    ) -> NotificationContent {
        let title: String
        let body: String

        switch type {
        case .sessionThreshold75, .sessionThreshold90:
            title = "Usage Alert"
            let percent = thresholdPercent ?? 75
            body = "\(accountName): Session usage has reached \(percent)%"

        case .weeklyThreshold75, .weeklyThreshold90:
            title = "Usage Alert"
            let percent = thresholdPercent ?? 75
            body = "\(accountName): Weekly usage has reached \(percent)%"

        case .sessionReady:
            title = "Session Ready"
            body = "\(accountName): Your session is ready to start"
        }

        return NotificationContent(
            title: title,
            body: body,
            identifier: type.identifier
        )
    }

    // MARK: - Rate Limiting Helpers

    /// Generate a unique key for tracking notification cooldown per account and type
    /// - Parameters:
    ///   - accountId: The stable UUID of the account (not name, which can change)
    ///   - type: The notification type
    /// - Returns: A unique key string in format "accountId:type.identifier"
    func cooldownKey(accountId: UUID, type: NotificationType) -> String {
        return "\(accountId.uuidString):\(type.identifier)"
    }

    /// Check if cooldown period has passed since last notification of this type for this account
    /// - Parameters:
    ///   - accountId: The stable UUID of the account
    ///   - type: The notification type
    /// - Returns: true if cooldown has passed (can send notification), false if still in cooldown period
    private func canSendNotification(accountId: UUID, type: NotificationType) -> Bool {
        let key = cooldownKey(accountId: accountId, type: type)

        notificationLock.lock()
        defer { notificationLock.unlock() }

        guard let lastSent = lastNotificationTimes[key] else {
            // Never sent this notification type for this account, so we can send
            return true
        }

        let timeSinceLastSent = Date().timeIntervalSince(lastSent)
        return timeSinceLastSent >= cooldownInterval
    }

    /// Record that a notification was sent for rate limiting tracking
    /// - Parameters:
    ///   - accountId: The stable UUID of the account
    ///   - type: The notification type
    private func recordNotificationSent(accountId: UUID, type: NotificationType) {
        let key = cooldownKey(accountId: accountId, type: type)

        notificationLock.lock()
        defer { notificationLock.unlock() }

        lastNotificationTimes[key] = Date()
    }

    // MARK: - Permission Management

    /// Requests notification permission from the user.
    /// Results are returned via onPermissionGranted, onPermissionDenied, or onError callbacks.
    func requestPermission() {
        guard let center = notificationCenter else {
            Log.debug(category, "Skipping permission request - not available")
            return
        }

        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.onError?(error)
                    return
                }

                self?.checkAuthorizationStatus()

                if granted {
                    self?.onPermissionGranted?()
                } else {
                    self?.onPermissionDenied?()
                }
            }
        }
    }

    /// Checks and updates the current notification authorization status.
    func checkAuthorizationStatus() {
        guard let center = notificationCenter else { return }

        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    /// Sends a notification with the given content.
    /// - Parameters:
    ///   - title: The notification title
    ///   - body: The notification body text
    ///   - identifier: Unique identifier for the notification
    func sendNotification(title: String, body: String, identifier: String) {
        guard let center = notificationCenter else { return }

        // Check if notifications are authorized
        guard authorizationStatus == .authorized else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Create a trigger that fires immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create the request
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // Schedule the notification
        center.add(request) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.onError?(error)
                }
            }
        }
    }

    /// Sends a typed notification using the content builder.
    /// Applies rate limiting to prevent notification spam.
    /// - Parameters:
    ///   - type: The type of notification to send
    ///   - accountId: The stable UUID of the account
    ///   - accountName: The display name of the account
    ///   - thresholdPercent: The threshold percentage to display (for threshold notifications)
    func sendNotification(type: NotificationType, accountId: UUID, accountName: String, thresholdPercent: Int? = nil) {
        // Check cooldown to prevent notification spam
        guard canSendNotification(accountId: accountId, type: type) else {
            return
        }

        let content = buildNotificationContent(type: type, accountName: accountName, thresholdPercent: thresholdPercent)
        // Use cooldownKey as identifier to ensure uniqueness per account per type
        sendNotification(title: content.title, body: content.body, identifier: cooldownKey(accountId: accountId, type: type))

        // Record that notification was sent for rate limiting
        recordNotificationSent(accountId: accountId, type: type)
    }

    /// Removes a pending notification by its identifier.
    /// - Parameter identifier: The notification identifier to remove
    func removePendingNotification(identifier: String) {
        notificationCenter?.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    /// Removes all pending notifications.
    func removeAllPendingNotifications() {
        notificationCenter?.removeAllPendingNotificationRequests()
    }

    /// Removes a delivered notification by its identifier.
    /// - Parameter identifier: The notification identifier to remove
    func removeDeliveredNotification(identifier: String) {
        notificationCenter?.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Removes all delivered notifications.
    func removeAllDeliveredNotifications() {
        notificationCenter?.removeAllDeliveredNotifications()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Handles notification presentation when the app is in the foreground.
    /// Shows notifications as banners with sound even when the app is active.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handles notification interaction when the user taps on it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
