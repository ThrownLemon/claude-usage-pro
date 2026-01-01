import Foundation
import WebKit
import Combine


class TrackerService: NSObject, ObservableObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var currentTask: AnyCancellable?
    
    // Result callback
    var onUpdate: ((UsageData) -> Void)?
    var onError: ((Error) -> Void)?
    
    // Actions
    func pingSession() {
        print("[DEBUG] TrackerService: Pinging session...")
        // We need to inject JS to send a message
        let script = """
            async function ping() {
                try {
                    const orgRes = await fetch('/api/organizations');
                    const orgs = await orgRes.json();
                    const orgId = orgs[0].uuid || orgs[0].id;
                    
                    // Create a new conversation
                    const chatRes = await fetch(`/api/organizations/${orgId}/chat_conversations`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            uuid: crypto.randomUUID(),
                            name: ''
                        })
                    });
                    const chat = await chatRes.json();
                    const chatId = chat.uuid;
                    
                    // Send message to haiku
                    await fetch(`/api/organizations/${orgId}/chat_conversations/${chatId}/completion`, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            prompt: "hi",
                            timezone: "America/New_York",
                            model: "claude-3-haiku-20240307"
                        })
                    });
                    
                    // Delete conversation to clean up (optional, but polite)
                    // await fetch(`/api/organizations/${orgId}/chat_conversations/${chatId}`, { method: 'DELETE' });
                    
                    return { success: true };
                } catch (e) {
                    return { error: e.toString() };
                }
            }
            await ping();
        """
        
        webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
             print("[DEBUG] TrackerService: Ping result: \(result)")
        }
    }
    
    func fetchUsage(cookies: [HTTPCookie]) {
        print("[DEBUG] TrackerService: Starting fetch for \(cookies.count) cookies.")
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                config.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                print("[DEBUG] TrackerService: Cookies injected, starting hidden browser.")
                self.startHiddenBrowser(config: config)
            }
        }
    }
    
    private func startHiddenBrowser(config: WKWebViewConfiguration) {
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        
        let urlString = "https://claude.ai/chats"
        if let url = URL(string: urlString) {
             print("[DEBUG] TrackerService: Loading \(urlString)...")
            webView.load(URLRequest(url: url))
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // JS to find usage limits
        print("[DEBUG] TrackerService: Page finished loading. Injecting JS...")
        
        let script = """
            try {
                 // Step 1: Fetch Organizations
                 const orgResponse = await fetch('/api/organizations');
                 if (!orgResponse.ok) return { error: "Failed to fetch orgs: " + orgResponse.status };
                 
                 const orgs = await orgResponse.json();
                 if (!orgs || orgs.length === 0) return { error: "No organizations found" };
                 
                 // Just take the first one or look for 'personal' capabilities
                 const orgId = orgs[0].uuid || orgs[0].id; // usage often depends on UUID
                 
                 // Step 2: Fetch Usage Data
                 const usageResponse = await fetch(`/api/organizations/${orgId}/usage`);
                 let usageData = {};
                 if (usageResponse.ok) {
                    usageData = await usageResponse.json();
                 }
                 
                 // Step 3: Fetch Statsig for Tier
                 const statsResponse = await fetch(`/api/bootstrap/${orgId}/statsig`);
                 let statsData = {};
                 if (statsResponse.ok) {
                    statsData = await statsResponse.json();
                 }
                 
                 // Step 4: Fetch User Me (Retry)
                 const meResponse = await fetch('/api/users/me'); 
                 let meData = {};
                 if (meResponse.ok) {
                    meData = await meResponse.json();
                 }
                 
                 // Step 5: Global Scope Fallback
                 const intercom = window.intercomSettings || {};
                 const globalUser = window.user || window.__USER__ || {};
                 
                 return {
                    tier: statsData?.user?.custom?.isPro ? "Pro" : "Free",
                    email: meData?.email_address || meData?.email || intercom?.email || globalUser?.email,
                    orgId: orgId,
                    debugMe: meData,
                    debugIntercom: intercom,
                    usage: usageData
                 };
            } catch (e) {
                return { error: e.toString() };
            }
        """
        
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
             print("[DEBUG] TrackerService: JS Evaluation completed.")
            
            switch result {
            case .success(let value):
                 // print("[DEBUG] TrackerService: JS Result: \(value)")
                
                if let dict = value as? [String: Any] {
                    let tier = dict["tier"] as? String ?? "Unknown"
                    let email = dict["email"] as? String
                    
                    // Metadata extraction
                    var fullName: String?
                    var orgName: String?
                    var planType: String?
                    
                    if let intercom = dict["debugIntercom"] as? [String: Any] {
                        fullName = intercom["name"] as? String
                        
                        // Companies array
                        if let companies = intercom["companies"] as? [[String: Any]], let first = companies.first {
                            orgName = first["name"] as? String
                            planType = first["plan"] as? String
                        }
                    }
                    
                    print("[DEBUG] Parsed - Tier: \(tier), Email: \(email ?? "nil"), Name: \(fullName ?? "nil"), Plan: \(planType ?? "nil")")
                    
                    var sessionPct = 0.0
                    var sessionReset = "Ready" // Default to Ready if nil
                    var weeklyPct = 0.0
                    var weeklyReset = "Ready"
                    
                    if let usage = dict["usage"] as? [String: Any] {
                        // Parse Session (5-hour)
                        if let fiveHour = usage["five_hour"] as? [String: Any] {
                            if let util = fiveHour["utilization"] as? Double {
                                sessionPct = util / 100.0
                            }
                            if let resetDateStr = fiveHour["resets_at"] as? String {
                                sessionReset = self.formatResetTime(isoDate: resetDateStr)
                            } else if sessionPct > 0 {
                                // If utilized but no reset date? Weird, but assume unknown.
                                // If 0% utilized, "Ready" is correct.
                                sessionReset = "Ready"
                            }
                        }
                        
                        // Parse Weekly (7-day)
                        if let sevenDay = usage["seven_day"] as? [String: Any] {
                            if let util = sevenDay["utilization"] as? Double {
                                weeklyPct = util / 100.0
                            }
                            if let resetDateStr = sevenDay["resets_at"] as? String {
                                weeklyReset = self.formatResetDate(isoDate: resetDateStr)
                            }
                        }
                    }
                    
                    let data = UsageData(
                        sessionPercentage: sessionPct,
                        sessionReset: sessionReset,
                        weeklyPercentage: weeklyPct,
                        weeklyReset: weeklyReset,
                        tier: tier,
                        email: email,
                        fullName: fullName,
                        orgName: orgName,
                        planType: planType
                    )
                    self.onUpdate?(data)
                }
            case .failure(let error):
                print("[DEBUG] TrackerService: JS Error: \(error.localizedDescription)")
            }
        }
    }
    
    // Helpers for date formatting
    private func formatResetTime(isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Ready" }
        
        // Format as "3 hr 21 min"
        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)h \(mins)m"
    }
    
    private func formatResetDate(isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "E h:mm a" // e.g., Thu 8:59 PM
        return displayFormatter.string(from: date)
    }
}
