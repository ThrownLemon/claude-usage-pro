import Foundation
import SwiftUI
import os

/// Manages a single account's usage monitoring session.
/// Handles periodic fetching, threshold notifications, and auto-wake functionality.
@Observable
@MainActor
class AccountSession: Identifiable {
    private let category = Log.Category.session
    /// Unique identifier matching the associated account's ID
    let id: UUID
    /// The account being monitored
    var account: ClaudeAccount
    /// Whether a fetch operation is currently in progress
    var isFetching: Bool = false
    /// The most recent error encountered during fetching, if any
    var lastError: Error?

    private var previousSessionPercentage: Double?
    private var previousWeeklyPercentage: Double?
    private var hasReceivedFirstUpdate: Bool = false

    private var tracker: TrackerService?
    private var cursorTracker: CursorTrackerService?
    private var glmTracker: GLMTrackerService?
    // These properties need to be accessible from deinit (which is nonisolated).
    // Timer.invalidate() and Task.cancel() are thread-safe operations.
    // Using @ObservationIgnored to prevent the @Observable macro from transforming them.
    @ObservationIgnored private nonisolated(unsafe) var timer: Timer?
    @ObservationIgnored private nonisolated(unsafe) var fetchTask: Task<Void, Never>?
    var onRefreshTick: (() -> Void)?

    /// Creates a new session for monitoring an account's usage.
    /// - Parameter account: The account to monitor
    init(account: ClaudeAccount) {
        self.id = account.id
        self.account = account

        switch account.type {
        case .claude:
            self.tracker = TrackerService()
        case .cursor:
            self.cursorTracker = CursorTrackerService()
        case .glm:
            self.glmTracker = GLMTrackerService()
        }

        setupTracker()
    }
    
    deinit {
        fetchTask?.cancel()
        timer?.invalidate()
    }
    
    /// Starts monitoring the account's usage with periodic refreshes.
    /// Performs an immediate fetch and schedules recurring updates.
    func startMonitoring() {
        Log.debug(category, "Starting monitoring for \(account.name)")
        fetchNow()
        scheduleRefreshTimer()
    }

    /// Stops monitoring and cancels all pending operations.
    /// Safe to call multiple times.
    func stopMonitoring() {
        Log.debug(category, "Stopping monitoring for \(account.name)")
        fetchTask?.cancel()
        fetchTask = nil
        timer?.invalidate()
        timer = nil
    }

    /// Schedules or reschedules the refresh timer based on user settings.
    func scheduleRefreshTimer() {
        timer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        let time = interval > 0 ? interval : Constants.Timeouts.defaultRefreshInterval
        
        timer = Timer.scheduledTimer(withTimeInterval: time, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchNow()
                self?.onRefreshTick?()
            }
        }
    }
    
    /// Sends a ping to wake up a ready session.
    /// - Parameter isAuto: Whether this is an automatic ping (respects auto-wake setting)
    func ping(isAuto: Bool = false) {
        if isAuto && !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoWakeUp) {
            Log.debug(category, "Auto-ping cancelled (setting disabled)")
            return
        }

        guard let usageData = account.usageData,
              usageData.sessionPercentage == 0,
              usageData.sessionReset == "Ready" else {
            Log.debug(category, "Ping skipped (session not ready)")
            return
        }
        Log.debug(category, "\(isAuto ? "Auto" : "Manual") ping requested")
        tracker?.onPingComplete = { [weak self] success in
            guard let self = self else { return }
            if success {
                Log.debug(self.category, "Ping finished, refreshing data...")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    self?.fetchNow()
                }
            } else {
                Log.error(self.category, "Ping failed")
            }
        }
        tracker?.pingSession()
    }
    
    /// Immediately fetches usage data for the account.
    /// Cancels any in-progress fetch and starts a new one.
    func fetchNow() {
        guard !isFetching else { return }
        isFetching = true

        // Cancel any previous fetch task
        fetchTask?.cancel()

        switch account.type {
        case .claude:
            tracker?.fetchUsage(cookies: account.cookies)
        case .cursor:
            fetchTask = Task { [weak self] in
                guard let self = self else { return }
                do {
                    let info = try await self.cursorTracker?.fetchCursorUsage()
                    guard !Task.isCancelled else { return }
                    if let info = info {
                        self.handleCursorUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.handleCursorUsageResult(.failure(error))
                }
            }
        case .glm:
            fetchTask = Task { [weak self] in
                guard let self = self else { return }
                guard let apiToken = self.account.apiToken else {
                    self.handleGLMUsageResult(.failure(GLMTrackerError.tokenNotFound))
                    return
                }
                do {
                    let info = try await self.glmTracker?.fetchGLMUsage(apiToken: apiToken)
                    guard !Task.isCancelled else { return }
                    if let info = info {
                        self.handleGLMUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self.handleGLMUsageResult(.failure(error))
                }
            }
        }
    }
    
    private func handleCursorUsageResult(_ result: Result<CursorUsageInfo, Error>) {
        // Already on @MainActor, no need for DispatchQueue.main
        self.isFetching = false
        switch result {
        case .success(let info):
            let sessionPercentage = info.planLimit > 0 ? Double(info.planUsed) / Double(info.planLimit) : 0.0

            let usageData = UsageData(
                sessionPercentage: sessionPercentage,
                sessionReset: "Ready",
                sessionResetDisplay: "\(info.planUsed) / \(info.planLimit)",
                weeklyPercentage: 0,
                weeklyReset: "Ready",
                weeklyResetDisplay: "\(info.planUsed) / \(info.planLimit)",
                tier: info.planType ?? "Pro",
                email: info.email,
                fullName: nil,
                orgName: "Cursor",
                planType: info.planType,
                cursorUsed: info.planUsed,
                cursorLimit: info.planLimit
            )
            self.updateWithUsageData(usageData)

            if let email = info.email, self.account.name.starts(with: "Account ") || self.account.name.starts(with: "Cursor") {
                self.account.name = "Cursor (\(email))"
            }
        case .failure(let error):
            self.lastError = error
            Log.error(Log.Category.cursorTracker, "Fetch failed: \(error)")
        }
    }

    private func handleGLMUsageResult(_ result: Result<GLMUsageInfo, Error>) {
        // Already on @MainActor, no need for DispatchQueue.main
        self.isFetching = false
        switch result {
        case .success(let info):
            // Use shared helper methods for consistent formatting
            let sessionResetDisplay = GLMUsageInfo.formatSessionResetDisplay(sessionPercentage: info.sessionPercentage)
            let weeklyResetDisplay = GLMUsageInfo.formatMonthlyResetDisplay(
                monthlyUsed: info.monthlyUsed,
                monthlyLimit: info.monthlyLimit,
                monthlyPercentage: info.monthlyPercentage
            )

            let usageData = UsageData(
                sessionPercentage: info.sessionPercentage,
                sessionReset: "Ready",
                sessionResetDisplay: sessionResetDisplay,
                weeklyPercentage: info.monthlyPercentage,
                weeklyReset: "Ready",
                weeklyResetDisplay: weeklyResetDisplay,
                tier: "GLM Coding Plan",
                email: nil,
                fullName: nil,
                orgName: "GLM",
                planType: "Coding Plan",
                glmSessionUsed: info.sessionUsed,
                glmSessionLimit: info.sessionLimit,
                glmMonthlyUsed: info.monthlyUsed,
                glmMonthlyLimit: info.monthlyLimit
            )
            self.updateWithUsageData(usageData)

            if self.account.name.starts(with: "Account ") || self.account.name.starts(with: "GLM") {
                self.account.name = "GLM Coding Plan"
            }
        case .failure(let error):
            self.lastError = error
            Log.error(Log.Category.glmTracker, "Fetch failed: \(error)")
        }
    }

    private func updateWithUsageData(_ usageData: UsageData) {
        // Clear any previous error on successful update
        self.lastError = nil

        if self.hasReceivedFirstUpdate {
            self.previousSessionPercentage = self.account.usageData?.sessionPercentage
            self.previousWeeklyPercentage = self.account.usageData?.weeklyPercentage
        } else {
            self.hasReceivedFirstUpdate = true
        }

        self.account.usageData = usageData

        // Log formatted provider stats
        Log.providerStats(accountName: self.account.name, accountType: self.account.type, usageData: usageData)

        self.checkThresholdCrossingsAndNotify(usageData: usageData)

        if self.didTransitionToReady(previousPercentage: self.previousSessionPercentage, currentPercentage: usageData.sessionPercentage, currentReset: usageData.sessionReset) {
            if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoWakeUp) {
                Log.debug(category, "Auto-waking up \(self.account.name)...")
                self.ping(isAuto: true)
            }
        }

        if let email = usageData.email, self.account.name.starts(with: "Account ") {
            self.account.name = email
        }
    }
    
    private func didCrossThreshold(previous: Double?, current: Double, threshold: Double) -> Bool {
        guard let prev = previous else { return false }
        return prev < threshold && current >= threshold
    }

    private func didTransitionToReady(previousPercentage: Double?, currentPercentage: Double, currentReset: String) -> Bool {
        guard let prev = previousPercentage else { return false }
        return prev > 0 && currentPercentage == 0 && currentReset == "Ready"
    }

    private func checkThresholdCrossingsAndNotify(usageData: UsageData) {
        let accountId = account.id
        let accountName = account.name

        for config in ThresholdDefinitions.sessionThresholds
        where didCrossThreshold(previous: previousSessionPercentage, current: usageData.sessionPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountId: accountId, accountName: accountName, thresholdPercent: thresholdPercent)
        }

        for config in ThresholdDefinitions.weeklyThresholds
        where didCrossThreshold(previous: previousWeeklyPercentage, current: usageData.weeklyPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountId: accountId, accountName: accountName, thresholdPercent: thresholdPercent)
        }

        if didTransitionToReady(previousPercentage: previousSessionPercentage, currentPercentage: usageData.sessionPercentage, currentReset: usageData.sessionReset) {
            if NotificationSettings.shouldSend(type: .sessionReady) {
                NotificationManager.shared.sendNotification(type: .sessionReady, accountId: accountId, accountName: accountName)
            }
        }
    }

    private func setupTracker() {
        tracker?.onUpdate = { [weak self] usageData in
            guard let self = self else { return }
            Task { @MainActor in
                self.isFetching = false
                var data = usageData
                data.sessionResetDisplay = usageData.sessionReset
                self.updateWithUsageData(data)
            }
        }

        tracker?.onError = { [weak self] error in
            guard let self = self else { return }
            Task { @MainActor in
                self.isFetching = false
                self.lastError = error
                Log.error(self.category, "Fetch failed for \(self.account.name): \(error)")
            }
        }
    }
}
