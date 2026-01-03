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
    private var apiService: ClaudeAPIService
    private var timer: Timer?
    var onRefreshTick: (() -> Void)?
    
    init(account: ClaudeAccount) {
        self.id = account.id
        self.account = account
        self.tracker = TrackerService()
        self.apiService = ClaudeAPIService()
        
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
    
    func ping(isAuto: Bool = false) {
        if isAuto && !UserDefaults.standard.bool(forKey: "autoWakeUp") {
            print("[DEBUG] Session: Auto-ping cancelled (setting disabled).")
            return
        }

        guard let usageData = account.usageData,
              usageData.sessionPercentage == 0,
              usageData.sessionReset == "Ready" else {
            print("[DEBUG] Session: Ping skipped (session not ready).")
            return
        }
        print("[DEBUG] Session: \(isAuto ? "Auto" : "Manual") ping requested.")
        tracker?.onPingComplete = { [weak self] success in
            if success {
                print("[DEBUG] Session: Ping finished, refreshing data...")
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
        
        apiService.fetchUsage(cookies: account.cookies) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isFetching = false
                switch result {
                case .success(let usageData):
                    self.updateWithUsageData(usageData)
                case .failure(let error):
                    print("[ERROR] Session API: Fetch failed for \(self.account.name): \(error). Falling back to WebKit...")
                    self.isFetching = true
                    self.tracker?.fetchUsage(cookies: self.account.cookies)
                }
            }
        }
    }
    
    private func updateWithUsageData(_ usageData: UsageData) {
        if self.hasReceivedFirstUpdate {
            self.previousSessionPercentage = self.account.usageData?.sessionPercentage
            self.previousWeeklyPercentage = self.account.usageData?.weeklyPercentage
        } else {
            self.hasReceivedFirstUpdate = true
        }

        self.account.usageData = usageData

        print("[DEBUG] UsageData \(self.account.name): session=\(Int(usageData.sessionPercentage * 100))% reset=\(usageData.sessionReset) weekly=\(Int(usageData.weeklyPercentage * 100))% reset=\(usageData.weeklyReset)")

        self.checkThresholdCrossingsAndNotify(usageData: usageData)

        if self.didTransitionToReady(previousPercentage: self.previousSessionPercentage, currentPercentage: usageData.sessionPercentage, currentReset: usageData.sessionReset) {
            if UserDefaults.standard.bool(forKey: "autoWakeUp") {
                print("[DEBUG] Session: Auto-waking up \(self.account.name)...")
                self.ping(isAuto: true)
            }
        }

        if let email = usageData.email, self.account.name.starts(with: "Account ") {
            self.account.name = email
        }

        self.objectWillChange.send()
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
        for config in ThresholdDefinitions.sessionThresholds
        where didCrossThreshold(previous: previousSessionPercentage, current: usageData.sessionPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName, thresholdPercent: thresholdPercent)
        }

        // Check weekly thresholds using centralized configuration
        for config in ThresholdDefinitions.weeklyThresholds
        where didCrossThreshold(previous: previousWeeklyPercentage, current: usageData.weeklyPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName, thresholdPercent: thresholdPercent)
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
                self.updateWithUsageData(usageData)
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
