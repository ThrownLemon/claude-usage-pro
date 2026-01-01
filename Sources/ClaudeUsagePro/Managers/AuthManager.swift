import Foundation
import WebKit
import SwiftUI
import Combine

class AuthManager: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var isLoginWindowOpen = false
    private var loginWindow: NSWindow?
    private var webView: WKWebView?
    
    // Callback when login is successful (returns cookies and potentially org info)
    var onLoginSuccess: (([HTTPCookie]) -> Void)?
    
    override init() {
        super.init()
    }
    
    func startLogin() {
        print("[DEBUG] AuthManager: Starting login process...")
        DispatchQueue.main.async {
            if self.loginWindow != nil {
                print("[DEBUG] AuthManager: Login window already exists, bringing to front.")
                self.loginWindow?.makeKeyAndOrderFront(nil)
                return
            }
            // ... (rest of window creation)
            
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            self.webView = webView
            //Info: creating window...
            
            print("[DEBUG] AuthManager: Creating login window.")
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
            
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                self?.handleWindowClosed()
            }
            
            self.loginWindow = window
            self.isLoginWindowOpen = true
            
            NSApp.setActivationPolicy(.regular)
            
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            
            if let url = URL(string: "https://claude.ai/login") {
                print("[DEBUG] AuthManager: Loading URL: \(url)")
                webView.load(URLRequest(url: url))
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Log navigation
        if let url = navigationResponse.response.url {
            print("[DEBUG] AuthManager: Navigated to \(url.absoluteString)")
        }
        
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            self?.checkForSessionKey(cookies: cookies)
        }
        decisionHandler(.allow)
    }
    
    private func checkForSessionKey(cookies: [HTTPCookie]) {
        // print("[DEBUG] Checking cookies: \(cookies.map { $0.name })") // Too verbose maybe, but good for deep debug
        let hasSession = cookies.contains { $0.name.contains("sessionKey") || $0.name.contains("session-token") }
        
        if hasSession {
            print("[DEBUG] AuthManager: Session cookie found! Triggering success.")
            DispatchQueue.main.async {
                self.onLoginSuccess?(cookies)
                self.closeLoginWindow()
            }
        }
    }
    
    // Called when user clicks X
    private func handleWindowClosed() {
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
