import Combine
import Foundation
import os
import WebKit

/// Service for fetching Claude.ai usage data using a hidden WKWebView.
/// Injects JavaScript to call Claude's internal APIs and parse responses.
@MainActor
class TrackerService: NSObject, ObservableObject, WKNavigationDelegate {
    private let category = Log.Category.tracker
    /// The hidden WebView used for API calls
    private var webView: WKWebView?
    private var currentTask: AnyCancellable?
    /// Stored cookies for ping operations
    private var storedCookies: [HTTPCookie] = []
    /// Whether a ping operation is pending
    private var pendingPing = false
    /// Work item for ping timeout handling
    private var pingTimeoutWorkItem: DispatchWorkItem?

    /// Called when usage data is successfully fetched
    var onUpdate: ((UsageData) -> Void)?
    /// Called when an error occurs during fetching
    var onError: ((Error) -> Void)?
    /// Called when a ping operation completes (with success status)
    var onPingComplete: ((Bool) -> Void)?

    deinit {
        // deinit runs on the main actor for @MainActor classes on macOS 14+
        MainActor.assumeIsolated {
            cleanup()
        }
    }

    /// Clean up WKWebView resources to prevent memory leaks
    private func cleanup() {
        pingTimeoutWorkItem?.cancel()
        pingTimeoutWorkItem = nil
        cleanupExistingWebView()
        webView = nil
    }

    /// Tear down the current webView (stopLoading, clear delegate, remove scripts)
    private func cleanupExistingWebView() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.configuration.userContentController.removeAllUserScripts()
    }

    /// Pings the session to wake it up and start a new usage window.
    /// Creates a temporary chat conversation, sends a minimal message, then deletes it.
    func pingSession() {
        Log.debug(category, "Pinging session...")
        guard !storedCookies.isEmpty else {
            Log.error(category, "No cookies stored for ping")
            onPingComplete?(false)
            return
        }
        pendingPing = true

        pingTimeoutWorkItem?.cancel()
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self, pendingPing else { return }
            Log.error(category, "Ping timed out")
            pendingPing = false
            onPingComplete?(false)
        }
        pingTimeoutWorkItem = timeoutWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.Timeouts.pingTimeout, execute: timeoutWorkItem)

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
            Log.debug(self.category, "Cookies injected for ping, loading page...")

            // Clean up existing webView before creating a new one
            self.cleanupExistingWebView()

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView

            let url = Constants.URLs.claudeChats
            webView.load(URLRequest(url: url))
        }
    }

    /// Executes the JavaScript ping script that creates a temporary conversation.
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

        Log.debug(category, "Executing ping script...")
        webView?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [self] result in
            var success = false
            switch result {
            case let .success(value):
                if let dict = value as? [String: Any] {
                    Log.debug(category, "Ping completed: \(dict)")
                    if dict["success"] != nil {
                        success = true
                    }
                } else {
                    Log.debug(category, "Ping result: \(String(describing: value))")
                }
            case let .failure(error):
                Log.error(category, "Ping FAILED: \(error)")
            }
            if pendingPing {
                onPingComplete?(success)
            }
            pendingPing = false
            pingTimeoutWorkItem?.cancel()
            pingTimeoutWorkItem = nil
        }
    }

    /// Fetches usage data by loading Claude.ai in a hidden WebView.
    /// - Parameter cookies: Authentication cookies from the login session
    func fetchUsage(cookies: [HTTPCookie]) {
        Log.debug(category, "Starting fetch for \(cookies.count) cookies")
        storedCookies = cookies // Store for later ping use
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
                Log.debug(self.category, "Cookies injected, starting hidden browser")
                self.startHiddenBrowser(config: config)
            }
        }
    }

    /// Creates and starts the hidden WebView browser for fetching usage data.
    /// - Parameter config: The WebView configuration with injected cookies
    private func startHiddenBrowser(config: WKWebViewConfiguration) {
        // Clean up existing webView before creating a new one
        cleanupExistingWebView()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let url = Constants.URLs.claudeChats
        Log.debug(category, "Loading \(url)")
        webView.load(URLRequest(url: url))
    }

    /// Allowed domains for the tracker WebView.
    /// Only Claude.ai is allowed for API scraping.
    private static let allowedDomains: Set<String> = ["claude.ai"]

    /// Check if a host is in the allowed domains list (including subdomains)
    private func isAllowedDomain(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return Self.allowedDomains.contains { allowedDomain in
            host == allowedDomain || host.hasSuffix("." + allowedDomain)
        }
    }

    /// Validates navigation requests to ensure only trusted domains are accessed.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Allow navigation only to Claude.ai
        if isAllowedDomain(url.host) {
            decisionHandler(.allow)
        } else {
            Log.warning(category, "Blocked navigation to untrusted domain: \(url.host ?? "unknown")")
            decisionHandler(.cancel)
        }
    }

    /// Called when the WebView finishes loading a page.
    /// Injects JavaScript to fetch usage data or execute ping.
    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        Log.debug(category, "Page finished loading, injecting JS...")

        // If ping is pending, execute ping script instead of usage script
        if pendingPing {
            executePingScript()
            return
        }

        // Otherwise run usage script

        let script = """
            try {
                 const orgResponse = await fetch('/api/organizations');
                 if (!orgResponse.ok) return { error: "Failed to fetch orgs: " + orgResponse.status };
                 
                 const orgs = await orgResponse.json();
                 if (!orgs || orgs.length === 0) return { error: "No organizations found" };
                 
                 const orgId = orgs[0].uuid || orgs[0].id;
                 
                 const usageResponse = await fetch(`/api/organizations/${orgId}/usage`);
                 let usageData = {};
                 let usageStatus = usageResponse.status;
                 let usageError = null;
                 if (usageResponse.ok) {
                    usageData = await usageResponse.json();
                 } else {
                    usageError = await usageResponse.text();
                 }
                 
                 let settingsData = {};
                 let settingsStatus = null;
                 const settingsResponse = await fetch(`/api/organizations/${orgId}/settings`);
                 settingsStatus = settingsResponse.status;
                 if (settingsResponse.ok) {
                    settingsData = await settingsResponse.json();
                 }
                 
                 let rateLimitData = {};
                 let rateLimitStatus = null;
                 const rateLimitResponse = await fetch(`/api/organizations/${orgId}/rate_limit`);
                 rateLimitStatus = rateLimitResponse.status;
                 if (rateLimitResponse.ok) {
                    rateLimitData = await rateLimitResponse.json();
                 }
                 
                 let bootstrapData = {};
                 const bootstrapResponse = await fetch(`/api/bootstrap/${orgId}`);
                 if (bootstrapResponse.ok) {
                    bootstrapData = await bootstrapResponse.json();
                 }
                 
                 const statsResponse = await fetch(`/api/bootstrap/${orgId}/statsig`);
                 let statsData = {};
                 if (statsResponse.ok) {
                    statsData = await statsResponse.json();
                 }
                 
                 const meResponse = await fetch('/api/users/me'); 
                 let meData = {};
                 if (meResponse.ok) {
                    meData = await meResponse.json();
                 }
                 
                 const intercom = window.intercomSettings || {};
                 const globalUser = window.user || window.__USER__ || {};
                 
                 // Determine tier - check multiple sources for Max/Pro status
                 let tierFromStatsig = (() => {
                    const custom = statsData?.user?.custom;
                    if (custom?.isMax) return "Max";
                    if (custom?.isPro) return "Pro";
                    // Check tier field directly
                    if (custom?.tier) return custom.tier;
                    return null;
                 })();

                 // Check intercom companies for plan info
                 const intercomPlan = intercom?.companies?.[0]?.plan;

                 // Check bootstrap for subscription info
                 const bootstrapPlan = bootstrapData?.account?.subscription?.plan ||
                                       bootstrapData?.subscription?.plan ||
                                       bootstrapData?.account?.plan;

                 // Priority: statsig > intercom > bootstrap > default to Free
                 let tier = "Free";
                 if (tierFromStatsig) {
                    tier = tierFromStatsig;
                 } else if (intercomPlan) {
                    // Normalize plan name
                    const planLower = intercomPlan.toLowerCase();
                    if (planLower.includes("max")) tier = "Max";
                    else if (planLower.includes("pro")) tier = "Pro";
                    else tier = intercomPlan;
                 } else if (bootstrapPlan) {
                    const planLower = (typeof bootstrapPlan === 'string' ? bootstrapPlan : '').toLowerCase();
                    if (planLower.includes("max")) tier = "Max";
                    else if (planLower.includes("pro")) tier = "Pro";
                    else if (typeof bootstrapPlan === 'string') tier = bootstrapPlan;
                 }

                 return {
                    tier: tier,
                    email: meData?.email_address || meData?.email || intercom?.email || globalUser?.email,
                    orgId: orgId,
                    debugMe: meData,
                    debugIntercom: intercom,
                    debugTierSources: {
                       statsig: tierFromStatsig,
                       intercom: intercomPlan,
                       bootstrap: bootstrapPlan,
                       statsigCustom: statsData?.user?.custom
                    },
                    usage: usageData,
                    usageStatus: usageStatus,
                    usageError: usageError,
                    settings: settingsData,
                    settingsStatus: settingsStatus,
                    rateLimit: rateLimitData,
                    rateLimitStatus: rateLimitStatus,
                    bootstrap: bootstrapData
                 };
            } catch (e) {
                return { error: e.toString() };
            }
        """

        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [self] result in
            Log.debug(category, "JS Evaluation completed")

            switch result {
            case let .success(value):
                Log.debug(category, "RAW JS Result: \(String(describing: value))")

                if let dict = value as? [String: Any] {
                    if let usageStatus = dict["usageStatus"] as? Int {
                        Log.debug(category, "Usage API status: \(usageStatus)")
                    }
                    if let usageError = dict["usageError"] as? String {
                        Log.error(category, "Usage API error: \(usageError)")
                    }

                    if let settings = dict["settings"] as? [String: Any] {
                        Log.debug(category, "RAW settings: \(settings)")
                    }
                    if let settingsStatus = dict["settingsStatus"] as? Int {
                        Log.debug(category, "Settings API status: \(settingsStatus)")
                    }

                    if let rateLimit = dict["rateLimit"] as? [String: Any] {
                        Log.debug(category, "RAW rateLimit: \(rateLimit)")
                    }
                    if let rateLimitStatus = dict["rateLimitStatus"] as? Int {
                        Log.debug(category, "RateLimit API status: \(rateLimitStatus)")
                    }

                    if let bootstrap = dict["bootstrap"] as? [String: Any] {
                        Log.debug(category, "RAW bootstrap: \(bootstrap)")
                    }

                    if let tierSources = dict["debugTierSources"] as? [String: Any] {
                        Log.debug(category, "Tier detection sources: \(tierSources)")
                    }

                    if let usage = dict["usage"] as? [String: Any] {
                        Log.debug(category, "RAW usage data: \(usage)")
                        if let fiveHour = usage["five_hour"] as? [String: Any] {
                            Log.debug(category, "RAW five_hour: \(fiveHour)")
                        } else {
                            Log.warning(category, "NO five_hour in usage!")
                        }
                        if let sevenDay = usage["seven_day"] as? [String: Any] {
                            Log.debug(category, "RAW seven_day: \(sevenDay)")
                        } else {
                            Log.warning(category, "NO seven_day in usage!")
                        }
                    } else {
                        Log.warning(category, "NO usage data in response! Keys present: \(dict.keys)")
                    }
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

                    Log.debug(
                        category,
                        "Parsed metadata - Tier: \(tier), Email: \(email ?? "nil"), Name: \(fullName ?? "nil"), Plan: \(planType ?? "nil")"
                    )

                    var sessionPct = 0.0
                    var sessionReset = Constants.Status.ready // Default to Ready if nil
                    var weeklyPct = 0.0
                    var weeklyReset = Constants.Status.ready

                    // Model-specific weekly quotas (for Max plan)
                    var sonnetPct: Double?
                    var sonnetReset: String?
                    var opusPct: Double?
                    var opusReset: String?

                    if let usage = dict["usage"] as? [String: Any] {
                        // Parse Session (5-hour)
                        if let fiveHour = usage["five_hour"] as? [String: Any] {
                            if let util = fiveHour["utilization"] as? Double {
                                sessionPct = util / 100.0
                            }
                            if let resetDateStr = fiveHour["resets_at"] as? String {
                                sessionReset = DateFormattingHelper.formatResetTime(isoDate: resetDateStr)
                            } else if sessionPct > 0 {
                                // If utilized but no reset date, assume unknown.
                                sessionReset = Constants.Status.unknown
                            }
                            // If 0% utilized and no reset date, sessionReset stays as "Ready"
                        }

                        // Parse Weekly (7-day)
                        if let sevenDay = usage["seven_day"] as? [String: Any] {
                            if let util = sevenDay["utilization"] as? Double {
                                weeklyPct = util / 100.0
                            }
                            if let resetDateStr = sevenDay["resets_at"] as? String {
                                weeklyReset = DateFormattingHelper.formatResetDate(isoDate: resetDateStr)
                            }
                        }

                        // Parse Sonnet-specific weekly quota (Max plan)
                        if let sevenDaySonnet = usage["seven_day_sonnet"] as? [String: Any] {
                            if let util = sevenDaySonnet["utilization"] as? Double {
                                sonnetPct = util / 100.0
                            }
                            if let resetDateStr = sevenDaySonnet["resets_at"] as? String {
                                sonnetReset = DateFormattingHelper.formatResetDate(isoDate: resetDateStr)
                            }
                        }

                        // Parse Opus-specific weekly quota (Max plan)
                        if let sevenDayOpus = usage["seven_day_opus"] as? [String: Any] {
                            if let util = sevenDayOpus["utilization"] as? Double {
                                opusPct = util / 100.0
                            }
                            if let resetDateStr = sevenDayOpus["resets_at"] as? String {
                                opusReset = DateFormattingHelper.formatResetDate(isoDate: resetDateStr)
                            }
                        }
                    }

                    Log.info(
                        category,
                        "FINAL PARSED - sessionPct=\(sessionPct) sessionReset=\(sessionReset) weeklyPct=\(weeklyPct) weeklyReset=\(weeklyReset) sonnetPct=\(String(describing: sonnetPct)) opusPct=\(String(describing: opusPct))"
                    )

                    let data = UsageData(
                        sessionPercentage: sessionPct,
                        sessionReset: sessionReset,
                        sessionResetDisplay: UsageData.formatSessionResetDisplay(sessionReset),
                        weeklyPercentage: weeklyPct,
                        weeklyReset: weeklyReset,
                        weeklyResetDisplay: weeklyReset,
                        tier: tier,
                        email: email,
                        fullName: fullName,
                        orgName: orgName,
                        planType: planType,
                        opusPercentage: opusPct,
                        opusReset: opusReset,
                        sonnetPercentage: sonnetPct,
                        sonnetReset: sonnetReset
                    )
                    onUpdate?(data)
                }
            case let .failure(error):
                Log.error(category, "JS Error: \(error.localizedDescription)")
                onError?(error)
            }
        }
    }
}
