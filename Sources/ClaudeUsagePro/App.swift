import AppKit
import Combine
import SwiftUI

// MARK: - App Entry Point

/// The main entry point for the AI Usage Pro application.
/// Creates a menu bar app that displays usage statistics for AI service accounts.
@main
struct ClaudeUsageProApp: App {
    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()
    @StateObject private var oauthLogin = AnthropicOAuthLogin()
    @StateObject private var appearanceManager = AppearanceManager()

    init() {
        // Enable debug logging for terminal output
        Log.isDebugEnabled = true
        Log.info(Log.Category.app, "App starting...")
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState, authManager: authManager, oauthLogin: oauthLogin)
                .environment(appState)
                .environment(\.colorScheme, appearanceManager.effectiveColorScheme)
                .environmentObject(appearanceManager)
        } label: {
            MenuBarUsageView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}
