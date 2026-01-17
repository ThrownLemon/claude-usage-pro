import Combine
import Foundation
import os
import SwiftUI
import WebKit

/// Manages authentication flow for Claude.ai accounts.
/// Opens a WebKit browser window for login and captures session cookies on success.
@MainActor
class AuthManager: NSObject, ObservableObject, WKNavigationDelegate {
    private let category = Log.Category.auth
    /// Whether the login window is currently displayed
    @Published var isLoginWindowOpen = false
    private var loginWindow: NSWindow?
    private var webView: WKWebView?
    private var windowCloseObserver: NSObjectProtocol?

    /// Called when login succeeds with the captured session cookies
    var onLoginSuccess: (([HTTPCookie]) -> Void)?

    override init() {
        super.init()
    }

    deinit {
        // deinit runs on the main actor for @MainActor classes
        MainActor.assumeIsolated {
            if let observer = windowCloseObserver {
                NotificationCenter.default.removeObserver(observer)
            }
            webView?.configuration.userContentController.removeAllUserScripts()
        }
    }

    func startLogin() {
        Log.debug(category, "Starting login process...")

        if loginWindow != nil {
            Log.debug(category, "Login window already exists, bringing to front")
            loginWindow?.makeKeyAndOrderFront(nil)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        Log.debug(category, "Creating login window")
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to Claude.ai"
        window.center()
        window.contentView = webView
        window.isReleasedWhenClosed = false

        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWindowClosed()
            }
        }

        loginWindow = window
        isLoginWindowOpen = true

        NSApp.setActivationPolicy(.regular)

        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let url = Constants.URLs.claudeLogin
        Log.debug(category, "Loading URL: \(url)")
        webView.load(URLRequest(url: url))
    }

    /// Allowed domains for the login flow.
    /// Includes Claude.ai and common OAuth providers that may be used during authentication.
    private static let allowedDomains: Set<String> = [
        "claude.ai",
        "anthropic.com",
        "accounts.google.com",
        "appleid.apple.com",
        "login.microsoftonline.com",
    ]

    /// Check if a host is in the allowed domains list (including subdomains)
    private func isAllowedDomain(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return Self.allowedDomains.contains { allowedDomain in
            host == allowedDomain || host.hasSuffix("." + allowedDomain)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        // Allow navigation only to trusted domains
        if isAllowedDomain(url.host) {
            Log.debug(category, "Allowing navigation to: \(url.host ?? "unknown")")
            decisionHandler(.allow)
        } else {
            Log.warning(category, "Blocked navigation to untrusted domain: \(url.host ?? "unknown")")
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let url = navigationResponse.response.url {
            Log.debug(category, "Navigated to \(url.absoluteString)")
        }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            self?.checkForSessionKey(cookies: cookies)
        }
        decisionHandler(.allow)
    }

    private func checkForSessionKey(cookies: [HTTPCookie]) {
        let hasSession = cookies.contains { $0.name.contains("sessionKey") || $0.name.contains("session-token") }

        if hasSession {
            Log.info(category, "Session cookie found! Triggering success")
            Task { @MainActor in
                self.onLoginSuccess?(cookies)
                self.closeLoginWindow()
            }
        }
    }

    // Called when user clicks X
    private func handleWindowClosed() {
        // Remove observer to prevent memory leak
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            windowCloseObserver = nil
        }

        // Clean up WKWebView resources
        webView?.configuration.userContentController.removeAllUserScripts()

        // Switch back to accessory (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        loginWindow = nil
        webView = nil
        isLoginWindowOpen = false
    }

    // Called programmatically on success or cancel
    private func closeLoginWindow() {
        loginWindow?.close()
        // The close() call will trigger the notification, which will call handleWindowClosed to clean up refs.
    }
}
