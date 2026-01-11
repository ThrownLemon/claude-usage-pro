import Foundation
import WebKit
import SwiftUI
import Combine
import os

/// Manages authentication flow for Claude.ai accounts.
/// Opens a WebKit browser window for login and captures session cookies on success.
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
        if let observer = windowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        webView?.configuration.userContentController.removeAllUserScripts()
    }
    
    func startLogin() {
        Log.debug(category, "Starting login process...")
        DispatchQueue.main.async {
            if self.loginWindow != nil {
                Log.debug(self.category, "Login window already exists, bringing to front")
                self.loginWindow?.makeKeyAndOrderFront(nil)
                return
            }

            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()

            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView

            Log.debug(self.category, "Creating login window")
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            // ... (rest of setup)
            window.title = "Login to Claude.ai"
            window.center()
            window.contentView = webView
            window.isReleasedWhenClosed = false
            
            self.windowCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleWindowClosed()
            }
            
            self.loginWindow = window
            self.isLoginWindowOpen = true
            
            NSApp.setActivationPolicy(.regular)
            
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            let url = Constants.URLs.claudeLogin
            Log.debug(self.category, "Loading URL: \(url)")
            webView.load(URLRequest(url: url))
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
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
            DispatchQueue.main.async {
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

        self.loginWindow = nil
        self.webView = nil
        self.isLoginWindowOpen = false
    }
    
    // Called programmatically on success or cancel
    private func closeLoginWindow() {
        loginWindow?.close()
        // The close() call will trigger the notification, which will call handleWindowClosed to clean up refs.
    }
}
