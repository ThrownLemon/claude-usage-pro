import Foundation
import Combine
import SwiftUI

class AccountSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var account: ClaudeAccount
    @Published var isFetching: Bool = false

    private var previousSessionPercentage: Double?
    private var previousWeeklyPercentage: Double?
    private var hasReceivedFirstUpdate: Bool = false

    private var tracker: TrackerService?
    private var cursorTracker: CursorTrackerService?
    private var timer: Timer?
    var onRefreshTick: (() -> Void)?
    
    init(account: ClaudeAccount) {
        self.id = account.id
        self.account = account
        
        if account.type == .claude {
            self.tracker = TrackerService()
        } else {
            self.cursorTracker = CursorTrackerService()
        }
        
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
        
        if account.type == .claude {
            tracker?.fetchUsage(cookies: account.cookies)
        } else {
            Task {
                do {
                    let info = try await cursorTracker?.fetchCursorUsage()
                    if let info = info {
                        self.handleCursorUsageResult(.success(info))
                    }
                } catch {
                    self.handleCursorUsageResult(.failure(error))
                }
            }
        }
    }
    
    private func handleCursorUsageResult(_ result: Result<CursorUsageInfo, Error>) {
        DispatchQueue.main.async {
            self.isFetching = false
            switch result {
            case .success(let info):
                let percentage = info.planLimit > 0 ? Double(info.planUsed) / Double(info.planLimit) : 0
                let usageData = UsageData(
                    sessionPercentage: percentage,
                    sessionReset: "Ready",
                    sessionResetDisplay: "\(info.planUsed) / \(info.planLimit)",
                    weeklyPercentage: 0,
                    weeklyReset: "Ready",
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
                print("[ERROR] Cursor Session: Fetch failed: \(error)")
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
        let accountName = account.name

        for config in ThresholdDefinitions.sessionThresholds
        where didCrossThreshold(previous: previousSessionPercentage, current: usageData.sessionPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName, thresholdPercent: thresholdPercent)
        }

        for config in ThresholdDefinitions.weeklyThresholds
        where didCrossThreshold(previous: previousWeeklyPercentage, current: usageData.weeklyPercentage, threshold: config.threshold)
            && NotificationSettings.shouldSend(type: config.notificationType) {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(type: config.notificationType, accountName: accountName, thresholdPercent: thresholdPercent)
        }

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
                var data = usageData
                data.sessionResetDisplay = usageData.sessionReset
                self.updateWithUsageData(data)
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
