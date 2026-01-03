import Foundation
import Combine
import SwiftUI

class AccountSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var account: ClaudeAccount
    @Published var isFetching: Bool = false

    // Track previous usage percentages to detect threshold crossings
    private var previousSessionPercentage: Double?
    private var previousWeeklyPercentage: Double?

    // Track if we've received the first update to prevent notifications on app launch
    private var hasReceivedFirstUpdate: Bool = false

    private var tracker: TrackerService?
    private var timer: Timer?
    var onRefreshTick: (() -> Void)?
    
    init(account: ClaudeAccount) {
        self.id = account.id
        self.account = account
        self.tracker = TrackerService()
        
        setupTracker()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    func startMonitoring() {
        print("[DEBUG] Session: Starting monitoring for \(account.name)")
        fetchNow()
        scheduleRefreshTimer()
    }
    
    func scheduleRefreshTimer() {
        timer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        let time = interval > 0 ? interval : 300
        
        // Timer for background refresh
        timer = Timer.scheduledTimer(withTimeInterval: time, repeats: true) { [weak self] _ in
            self?.fetchNow()
            self?.onRefreshTick?()
        }
    }
    
    func ping() {
        guard let usageData = account.usageData,
              usageData.sessionPercentage == 0,
              usageData.sessionReset == "Ready" else {
            print("[DEBUG] Session: Ping skipped (session not ready).")
            return
        }
        print("[DEBUG] Session: Manual ping requested.")
        tracker?.onPingComplete = { [weak self] success in
            if success {
                print("[DEBUG] Session: Ping finished, refreshing data...")
                // Wait a moment for Claude to process, then refresh
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    self?.fetchNow()
                }
            } else {
                print("[ERROR] Session: Ping failed.")
            }
        }
        tracker?.pingSession()
    }
    
    func fetchNow() {
        guard !isFetching else { return }
        isFetching = true
        tracker?.fetchUsage(cookies: account.cookies)
    }
    
    // MARK: - Threshold Detection

    /// Detects if usage has crossed a threshold (from below to at-or-above)
    /// - Parameters:
    ///   - previous: Previous percentage value (0.0 to 1.0), or nil if no previous value
    ///   - current: Current percentage value (0.0 to 1.0)
    ///   - threshold: Threshold percentage value (0.0 to 1.0)
    /// - Returns: true if threshold was crossed (previous < threshold AND current >= threshold)
    private func didCrossThreshold(previous: Double?, current: Double, threshold: Double) -> Bool {
        // If no previous value, don't trigger (avoid firing on app launch)
        guard let prev = previous else { return false }

        // Crossing occurs when: previous was below threshold AND current is at or above threshold
        return prev < threshold && current >= threshold
    }

    /// Detects if session transitioned to Ready state (from non-zero usage to 0% with "Ready" status)
    /// - Parameters:
    ///   - previousPercentage: Previous session percentage (0.0 to 1.0), or nil if no previous value
    ///   - currentPercentage: Current session percentage (0.0 to 1.0)
    ///   - currentReset: Current session reset status string
    /// - Returns: true if session just became ready (previous > 0, current == 0, status == "Ready")
    private func didTransitionToReady(previousPercentage: Double?, currentPercentage: Double, currentReset: String) -> Bool {
        // If no previous value, don't trigger (avoid firing on app launch)
        guard let prev = previousPercentage else { return false }

        // Ready transition occurs when: previous was non-zero AND current is zero AND status is "Ready"
        return prev > 0 && currentPercentage == 0 && currentReset == "Ready"
    }

    /// Check for threshold crossings and trigger notifications if detected and enabled
    /// - Parameter usageData: The current usage data to check against previous values
    private func checkThresholdCrossingsAndNotify(usageData: UsageData) {
        let accountName = account.name

        // Check session thresholds using centralized configuration
        for config in ThresholdDefinitions.sessionThresholds {
            if didCrossThreshold(previous: previousSessionPercentage, current: usageData.sessionPercentage, threshold: config.threshold) {
                if NotificationSettings.shouldSend(type: config.notificationType) {
                    NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName)
                }
            }
        }

        // Check weekly thresholds using centralized configuration
        for config in ThresholdDefinitions.weeklyThresholds {
            if didCrossThreshold(previous: previousWeeklyPercentage, current: usageData.weeklyPercentage, threshold: config.threshold) {
                if NotificationSettings.shouldSend(type: config.notificationType) {
                    NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName)
                }
            }
        }

        // Check session ready state transition
        if didTransitionToReady(previousPercentage: previousSessionPercentage, currentPercentage: usageData.sessionPercentage, currentReset: usageData.sessionReset) {
            if NotificationSettings.shouldSend(type: .sessionReady) {
                NotificationManager.shared.sendNotification(type: .sessionReady, accountName: accountName)
            }
        }
    }

    private func setupTracker() {
        tracker?.onUpdate = { [weak self] usageData in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isFetching = false

                // Store previous values before updating (for threshold crossing detection)
                // Skip on first update to prevent notifications on app launch with cached data
                if self.hasReceivedFirstUpdate {
                    self.previousSessionPercentage = self.account.usageData?.sessionPercentage
                    self.previousWeeklyPercentage = self.account.usageData?.weeklyPercentage
                } else {
                    // First update - mark as received but don't set previous values
                    // This ensures notifications only fire on actual crossings, not on app launch
                    self.hasReceivedFirstUpdate = true
                }

                // Update internal account data
                self.account.usageData = usageData

                print("[DEBUG] UsageData \(self.account.name): session=\(Int(usageData.sessionPercentage * 100))% reset=\(usageData.sessionReset) weekly=\(Int(usageData.weeklyPercentage * 100))% reset=\(usageData.weeklyReset)")

                // Threshold Detection & Notification Triggering
                self.checkThresholdCrossingsAndNotify(usageData: usageData)

                // Auto-Ping Logic
                if usageData.sessionPercentage == 0, usageData.sessionReset == "Ready" {
                    if UserDefaults.standard.bool(forKey: "autoWakeUp") {
                        print("[DEBUG] Session: Auto-waking up \(self.account.name)...")
                        self.ping()
                    }
                }

                // Auto-update name if email is found and name is still default
                if let email = usageData.email, self.account.name.starts(with: "Account ") {
                    self.account.name = email
                }

                // Propagate changes if needed (observer will see @Published account change)
                self.objectWillChange.send()
            }
        }

        tracker?.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.isFetching = false
                print("[ERROR] Session: Fetch failed for \(self?.account.name ?? "?"): \(error)")
            }
        }
    }
}
