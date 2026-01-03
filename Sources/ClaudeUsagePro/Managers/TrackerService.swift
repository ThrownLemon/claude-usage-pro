import Foundation
import WebKit
import Combine


class TrackerService: NSObject, ObservableObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var currentTask: AnyCancellable?
    private var storedCookies: [HTTPCookie] = []
    private var pendingPing = false
    private var pingTimeoutWorkItem: DispatchWorkItem?
    
    // Result callback
    var onUpdate: ((UsageData) -> Void)?
    var onError: ((Error) -> Void)?
    var onPingComplete: ((Bool) -> Void)?
    
    // Ping session by loading page with cookies and sending a message
    func pingSession() {
        print("[DEBUG] TrackerService: Pinging session...")
        guard !storedCookies.isEmpty else {
            print("[ERROR] TrackerService: No cookies stored for ping")
            onPingComplete?(false)
            return
        }
        pendingPing = true
        
        pingTimeoutWorkItem?.cancel()
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self = self, self.pendingPing else { return }
            print("[ERROR] TrackerService: Ping timed out")
            self.pendingPing = false
            self.onPingComplete?(false)
        }
        pingTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15.0, execute: timeoutWorkItem)
        
        // Create fresh webView with stored cookies
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        
        let group = DispatchGroup()
        for cookie in storedCookies {
            group.enter()
            config.websiteDataStore.httpCookieStore.setCookie(cookie) {
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            print("[DEBUG] TrackerService: Cookies injected for ping, loading page...")
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView
            
            if let url = URL(string: "https://claude.ai/chats") {
                webView.load(URLRequest(url: url))
            } else {
                print("[ERROR] TrackerService: Invalid ping URL")
                self.pendingPing = false
                self.onPingComplete?(false)
            }
        }
    }
    
    private func executePingScript() {
        let script = """
            let result = { error: 'not started' };
            try {
                console.log('[PING] Starting ping...');
                
                const orgRes = await fetch('/api/organizations');
                console.log('[PING] Orgs response status:', orgRes.status);
                if (!orgRes.ok) throw new Error('orgs status ' + orgRes.status);
                const orgs = await orgRes.json();
                console.log('[PING] Orgs count:', orgs.length);
                if (!orgs || orgs.length === 0) throw new Error('no orgs');
                const orgId = orgs[0].uuid || orgs[0].id;
                if (!orgId) throw new Error('missing orgId');
                console.log('[PING] Using orgId:', orgId);
                
                console.log('[PING] Creating conversation...');
                const chatRes = await fetch('/api/organizations/' + orgId + '/chat_conversations', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        uuid: crypto.randomUUID(),
                        name: ''
                    })
                });
                console.log('[PING] Chat create status:', chatRes.status);
                if (!chatRes.ok) throw new Error('chat create status ' + chatRes.status);
                const chat = await chatRes.json();
                console.log('[PING] Chat UUID:', chat.uuid);
                const chatId = chat.uuid;
                if (!chatId) throw new Error('missing chatId');
                
                console.log('[PING] Sending message...');
                const modelEndpoints = [
                    '/api/organizations/' + orgId + '/models',
                    '/api/models',
                    '/api/organizations/' + orgId + '/available_models'
                ];
                let models = [];
                let modelSource = null;
                const modelDiagnostics = [];
                for (const endpoint of modelEndpoints) {
                    try {
                        const modelRes = await fetch(endpoint);
                        modelDiagnostics.push({ endpoint: endpoint, status: modelRes.status });
                        if (!modelRes.ok) {
                            console.log('[PING] Model endpoint status:', modelRes.status, endpoint);
                            continue;
                        }
                        const modelData = await modelRes.json();
                        let rawModels = [];
                        if (Array.isArray(modelData)) {
                            rawModels = modelData;
                        } else if (Array.isArray(modelData.models)) {
                            rawModels = modelData.models;
                        } else if (Array.isArray(modelData.model_names)) {
                            rawModels = modelData.model_names;
                        } else if (Array.isArray(modelData.available_models)) {
                            rawModels = modelData.available_models;
                        }
                        const extracted = rawModels
                            .map((item) => (typeof item === 'string' ? item : (item.name || item.model || item.id)))
                            .filter(Boolean);
                        if (extracted.length > 0) {
                            models = extracted;
                            modelSource = endpoint;
                            break;
                        }
                    } catch (e) {
                        console.log('[PING] Model fetch error:', e.toString());
                        modelDiagnostics.push({ endpoint: endpoint, error: e.toString() });
                    }
                }
                if (models.length === 0) {
                    models = ["claude-3-haiku-20240307", "claude-3-5-haiku-20241022"];
                }
                const modelScore = (name) => {
                    const lower = (name || '').toLowerCase();
                    if (lower.includes('haiku')) return 0;
                    if (lower.includes('sonnet')) return 1;
                    if (lower.includes('opus')) return 2;
                    return 3;
                };
                models.sort((a, b) => modelScore(a) - modelScore(b));
                console.log('[PING] Models:', models, 'source:', modelSource);
                
                const clientHeaders = {
                    'Content-Type': 'application/json',
                    'Accept': 'text/event-stream'
                };
                const clientVersion = window.__BOOTSTRAP__?.version || window.__APP_VERSION__ || window.appVersion;
                const clientSha = window.__BOOTSTRAP__?.sha || window.__APP_SHA__ || window.appSha;
                const clientPlatform = window.__BOOTSTRAP__?.platform || 'web_claude_ai';
                if (clientVersion) clientHeaders['anthropic-client-version'] = clientVersion;
                if (clientSha) clientHeaders['anthropic-client-sha'] = clientSha;
                if (clientPlatform) clientHeaders['anthropic-client-platform'] = clientPlatform;
                
                let msgRes = null;
                let msgError = null;
                let modelUsed = null;
                const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
                const baseBody = {
                    prompt: "hi",
                    timezone: timezone,
                    rendering_mode: "default",
                    attachments: [],
                    files: []
                };
                msgRes = await fetch('/api/organizations/' + orgId + '/chat_conversations/' + chatId + '/completion', {
                    method: 'POST',
                    headers: clientHeaders,
                    body: JSON.stringify(baseBody)
                });
                console.log('[PING] Message status:', msgRes.status, 'model: default');
                if (msgRes.ok) {
                    modelUsed = 'default';
                } else {
                    msgError = await msgRes.text();
                }
                if (!msgRes.ok) {
                    for (const model of models) {
                        msgRes = await fetch('/api/organizations/' + orgId + '/chat_conversations/' + chatId + '/completion', {
                            method: 'POST',
                            headers: clientHeaders,
                            body: JSON.stringify({
                                ...baseBody,
                                model: model
                            })
                        });
                        console.log('[PING] Message status:', msgRes.status, 'model:', model);
                        if (msgRes.ok) {
                            msgError = null;
                            modelUsed = model;
                            break;
                        }
                        msgError = await msgRes.text();
                    }
                }
                if (!msgRes || !msgRes.ok) throw new Error('message status ' + (msgRes?.status || 'unknown') + ' body ' + msgError + ' modelSource ' + modelSource + ' modelDiagnostics ' + JSON.stringify(modelDiagnostics) + ' models ' + JSON.stringify(models));
                
                console.log('[PING] Deleting ping chat...');
                const deleteRes = await fetch('/api/organizations/' + orgId + '/chat_conversations/' + chatId, {
                    method: 'DELETE'
                });
                console.log('[PING] Delete status:', deleteRes.status);
                
                result = { success: true, chatId: chatId, status: msgRes.status, deleteStatus: deleteRes.status, model: modelUsed, modelSource: modelSource, modelDiagnostics: modelDiagnostics, clientHeaders: clientHeaders };
                console.log('[PING] SUCCESS!');
            } catch (e) {
                console.log('[PING] ERROR:', e.toString());
                result = { error: e.toString() };
            }
            return result;
        """
        
        print("[DEBUG] TrackerService: Executing ping script...")
        webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            var success = false
            switch result {
            case .success(let value):
                if let dict = value as? [String: Any] {
                    print("[DEBUG] TrackerService: Ping completed: \(dict)")
                    if dict["success"] != nil {
                        success = true
                    }
                } else {
                    print("[DEBUG] TrackerService: Ping result: \(String(describing: value))")
                }
            case .failure(let error):
                print("[DEBUG] TrackerService: Ping FAILED with error: \(error)")
            }
            if self.pendingPing {
                self.onPingComplete?(success)
            }
            self.pendingPing = false
            self.pingTimeoutWorkItem?.cancel()
            self.pingTimeoutWorkItem = nil
        }
    }
    
    func fetchUsage(cookies: [HTTPCookie]) {
        print("[DEBUG] TrackerService: Starting fetch for \(cookies.count) cookies.")
        self.storedCookies = cookies // Store for later ping use
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
        print("[DEBUG] TrackerService: Page finished loading. Injecting JS...")
        
        // If ping is pending, execute ping script instead of usage script
        if pendingPing {
            executePingScript()
            return
        }
        
        // Otherwise run usage script
        
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
                        sessionResetDisplay: sessionReset,
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
