import Foundation
import Combine
import SwiftUI

class AccountSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var account: ClaudeAccount
    @Published var isFetching: Bool = false
    
    private var tracker: TrackerService?
    private var timer: Timer?
    
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
        
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        let time = interval > 0 ? interval : 300
        
        // Timer for background refresh
        timer = Timer.scheduledTimer(withTimeInterval: time, repeats: true) { [weak self] _ in
            self?.fetchNow()
        }
    }
    
    func ping() {
        print("[DEBUG] Session: Manual ping requested.")
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
                
                // Update internal account data
                self.account.usageData = usageData
                
                // Auto-Ping Logic
                if usageData.sessionPercentage == 0, usageData.sessionReset == "Ready" {
                    if UserDefaults.standard.bool(forKey: "autoWakeUp") {
                        print("[DEBUG] Session: Auto-waking up \(self.account.name)...")
                        // Debounce: only ping if we haven't just pinged (tracker logic handles concurrency but let's be safe)
                        self.tracker?.pingSession()
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
