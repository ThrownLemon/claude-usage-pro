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
    
    private func setupTracker() {
        tracker?.onUpdate = { [weak self] usageData in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isFetching = false

                // Store previous values before updating (for threshold crossing detection)
                self.previousSessionPercentage = self.account.usageData?.sessionPercentage
                self.previousWeeklyPercentage = self.account.usageData?.weeklyPercentage

                // Update internal account data
                self.account.usageData = usageData
                
                print("[DEBUG] UsageData \(self.account.name): session=\(Int(usageData.sessionPercentage * 100))% reset=\(usageData.sessionReset) weekly=\(Int(usageData.weeklyPercentage * 100))% reset=\(usageData.weeklyReset)")
                
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
