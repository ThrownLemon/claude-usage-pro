import AppKit
import SwiftUI

/// Displays usage percentages in the menu bar label.
struct MenuBarUsageView: View {
    /// The app state containing all account sessions
    var appState: AppState

    var body: some View {
        let displaySessions = Array(appState.sessions.prefix(4))
        let labelText = displaySessions.map { session in
            let percent = Int((session.account.usageData?.sessionPercentage ?? 0) * 100)
            return "\(percent)%"
        }.joined(separator: "  ")
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text(labelText.isEmpty ? "Claude" : labelText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .fontWidth(.condensed)
                .foregroundColor(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

/// Displays a single account session's usage data in a row format.
struct AccountRowSessionView: View {
    /// The session to display
    var session: AccountSession
    /// Callback to trigger re-authentication for this account
    var onReauthenticate: (() -> Void)?

    var body: some View {
        UsageView(
            account: session.account,
            isFetching: session.isFetching,
            lastError: session.lastError,
            onPing: {
                Log.debug(Log.Category.app, "Ping clicked for \(session.account.name)")
                session.ping()
            },
            onRetry: {
                Log.debug(Log.Category.app, "Retry clicked for \(session.account.name)")
                session.fetchNow()
            },
            onReauthenticate: onReauthenticate
        )
        .padding(.vertical, 4)
    }
}

/// The main content view displayed in the menu bar popover.
/// Shows account usage cards, settings, or add account flow based on state.
struct ContentView: View {
    /// The global app state
    var appState: AppState
    /// The authentication manager for handling login
    @ObservedObject var authManager: AuthManager
    /// The OAuth login manager for PKCE flow
    @ObservedObject var oauthLogin: AnthropicOAuthLogin
    /// The appearance manager for handling color scheme
    @EnvironmentObject var appearanceManager: AppearanceManager

    @State private var showSettings = false
    @State private var showAddAccount = false
    @State private var addAccountStep = AddAccountStep.menu
    @State private var glmTokenInput = ""
    @State private var claudeOAuthTokenInput = ""
    /// Account ID being re-authenticated (nil if adding new account)
    @State private var reAuthAccountId: UUID?

    /// Current theme selection
    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue

    /// Current color scheme from environment
    @Environment(\.colorScheme) private var colorScheme

    /// Current theme colors
    private var theme: ThemeColors {
        let appTheme = AppTheme(rawValue: selectedTheme) ?? .standard
        return ThemeManager.colors(for: appTheme)
    }

    /// Title for the current navigation state
    private var headerTitle: String {
        if showSettings {
            return "Settings"
        } else if showAddAccount {
            switch addAccountStep {
            case .menu:
                return "Add Account"
            case .claudeOptions:
                return "Add Claude Account"
            case .claudeOAuthToken:
                return "OAuth Token"
            case .glmToken:
                return "GLM Coding Plan"
            }
        } else {
            return "AI Usage Pro"
        }
    }

    /// Icon for the current navigation state
    private var headerIcon: String {
        if showSettings {
            return "gearshape.fill"
        } else if showAddAccount {
            return "plus.circle.fill"
        } else {
            return "sparkles"
        }
    }

    /// Whether back navigation is available
    private var canGoBack: Bool {
        showSettings || showAddAccount
    }

    /// Handle back navigation
    private func goBack() {
        withAnimation {
            if showSettings {
                showSettings = false
            } else if showAddAccount {
                switch addAccountStep {
                case .menu:
                    showAddAccount = false
                case .claudeOptions:
                    addAccountStep = .menu
                case .claudeOAuthToken:
                    addAccountStep = .claudeOptions
                case .glmToken:
                    addAccountStep = .menu
                }
            }
        }
    }

    /// Current appearance mode
    private var currentAppearanceMode: ColorSchemeMode {
        ColorSchemeMode(rawValue: appearanceManager.colorSchemeMode) ?? .system
    }

    /// Icon for appearance mode toggle
    private var appearanceModeIcon: String {
        switch currentAppearanceMode {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.fill"
        }
    }

    /// Help text for appearance mode toggle
    private var appearanceModeHelpText: String {
        switch currentAppearanceMode {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    /// Cycle through appearance modes: system -> light -> dark -> system
    private func cycleAppearanceMode() {
        let nextMode: ColorSchemeMode
        switch currentAppearanceMode {
        case .system:
            nextMode = .light
        case .light:
            nextMode = .dark
        case .dark:
            nextMode = .system
        }
        appearanceManager.colorSchemeMode = nextMode.rawValue
    }

    /// Current app theme
    private var currentTheme: AppTheme {
        AppTheme(rawValue: selectedTheme) ?? .standard
    }

    /// Icon for theme toggle button
    private var themeIcon: String {
        switch currentTheme {
        case .standard:
            return "circle.grid.2x2"
        case .minimal:
            return "minus.circle"
        case .unified:
            return "circle.circle"
        case .premium:
            return "star.circle"
        case .nature:
            return "leaf.circle"
        case .vibrant:
            return "sparkle"
        case .ocean:
            return "drop.circle"
        case .sunset:
            return "sun.horizon.circle"
        case .midnight:
            return "moon.stars"
        case .roseGold:
            return "heart.circle"
        case .terminal:
            return "terminal"
        }
    }

    /// Cycle through available themes
    private func cycleTheme() {
        let allThemes = AppTheme.allCases
        guard let currentIndex = allThemes.firstIndex(of: currentTheme) else { return }
        let nextIndex = (currentIndex + 1) % allThemes.count
        selectedTheme = allThemes[nextIndex].rawValue
    }

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack(spacing: 8) {
                Image(systemName: headerIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(headerTitle)
                    .font(.system(.headline, design: theme.fontDesign.design))
                    .foregroundColor(.primary)
                Spacer()

                // Theme toggle (cycles through all themes)
                HoverIconButton(
                    image: themeIcon,
                    helpText: currentTheme.rawValue
                ) {
                    cycleTheme()
                }

                // Appearance mode toggle (cycles: system -> light -> dark)
                HoverIconButton(
                    image: appearanceModeIcon,
                    helpText: appearanceModeHelpText
                ) {
                    cycleAppearanceMode()
                }

                if canGoBack {
                    HoverIconButton(
                        image: "chevron.left",
                        helpText: "Back"
                    ) {
                        goBack()
                    }
                } else {
                    HoverIconButton(
                        image: "gearshape.fill",
                        helpText: "Settings"
                    ) {
                        withAnimation {
                            showSettings = true
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(theme.headerBackground(for: colorScheme))

            if theme.cardBorderStyle != .solid {
                Divider()
            }

            // Main Content Area
            if oauthLogin.awaitingCode {
                OAuthCodeEntryView(oauthLogin: oauthLogin)
            } else if showSettings {
                SettingsView()
            } else if showAddAccount {
                AddAccountView(
                    step: $addAccountStep,
                    glmTokenInput: $glmTokenInput,
                    claudeOAuthTokenInput: $claudeOAuthTokenInput,
                    onClaudeOAuthSignIn: {
                        showAddAccount = false
                        oauthLogin.startLogin()
                    },
                    onClaudeWebView: {
                        showAddAccount = false
                        authManager.startLogin()
                    },
                    onClaudeOAuth: { token in
                        let added = appState.addClaudeOAuthAccount(oauthToken: token)
                        if added {
                            showAddAccount = false
                        }
                        return added
                    },
                    onCursor: {
                        showAddAccount = false
                        appState.addCursorAccount()
                    },
                    onGLM: { token in
                        showAddAccount = false
                        if !token.isEmpty {
                            appState.addGLMAccount(apiToken: token)
                        }
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.sessions) { session in
                            AccountRowSessionView(
                                session: session,
                                onReauthenticate: session.account.type == .claude && session.account.usesOAuth ? {
                                    Log.info(Log.Category.app, "Re-authenticate clicked for \(session.account.name)")
                                    reAuthAccountId = session.account.id
                                    oauthLogin.startLogin()
                                } : nil
                            )
                        }

                        AddAccountCardView {
                            showAddAccount = true
                            addAccountStep = .menu
                        }
                    }
                    .padding(20)

                }
            }

            if theme.cardBorderStyle != .solid {
                Divider()
            }

            // Bottom Toolbar
            HStack(spacing: 8) {
                if !showSettings, !showAddAccount, !appState.sessions.isEmpty {
                    HoverIconButton(image: "arrow.clockwise", helpText: "Refresh Data Now") {
                        appState.refreshAll()
                        appState.nextRefresh = Date().addingTimeInterval(
                            appState.refreshIntervalSeconds())
                    }
                }

                Spacer()

                if !showSettings, !showAddAccount, !appState.sessions.isEmpty {
                    CountdownView(target: appState.nextRefresh)
                        .help("Time until next automatic refresh")
                        .id(appState.nextRefresh)
                }

                Spacer()

                QuitButton()
            }
            .padding(12)
            .background(theme.headerBackground(for: colorScheme))
        }
        .frame(width: Constants.WindowSize.width, height: Constants.WindowSize.height)
        .background(
            Group {
                // Use theme background image if available, otherwise fallback to theme solid color/Material default
                if let imageName = theme.backgroundImage(for: colorScheme) {
                    ZStack {
                        // Base color for blending
                        theme.appBackground(for: colorScheme)

                        AssetImage(imageName)
                            .opacity(theme.backgroundOpacity)
                    }
                } else {
                    theme.appBackground(for: colorScheme)
                }
            }
            .ignoresSafeArea()
        )
        .onAppear {
            authManager.onLoginSuccess = { cookies in
                Log.info(Log.Category.app, "Login success (WebView)")
                appState.addAccount(cookies: cookies)
            }
            oauthLogin.onLoginSuccess = { accessToken, refreshToken in
                if let accountId = reAuthAccountId {
                    // Re-authenticating existing account
                    Log.info(Log.Category.app, "Re-authentication success (OAuth)")
                    appState.reAuthenticateAccount(accountId: accountId, oauthToken: accessToken, refreshToken: refreshToken)
                    reAuthAccountId = nil
                } else {
                    // Adding new account
                    Log.info(Log.Category.app, "Login success (OAuth)")
                    if !appState.addClaudeOAuthAccount(oauthToken: accessToken, refreshToken: refreshToken) {
                        Log.warning(Log.Category.app, "Attempted to add duplicate account via OAuth")
                    }
                }
            }
            appState.nextRefresh = Date().addingTimeInterval(appState.refreshIntervalSeconds())

            // Request notification permission on first launch
            requestNotificationPermission()
        }
    }

    // Request notification permission on app launch
    @MainActor
    private func requestNotificationPermission() {
        let notificationManager = NotificationManager.shared

        // Only request if not determined yet
        if notificationManager.authorizationStatus == .notDetermined {
            notificationManager.onPermissionGranted = {
                Log.info(Log.Category.notifications, "Permission granted")
            }

            notificationManager.onPermissionDenied = {
                Log.info(Log.Category.notifications, "Permission denied by user")
            }

            notificationManager.onError = { error in
                Log.error(
                    Log.Category.notifications,
                    "Error requesting permission: \(error.localizedDescription)")
            }

            notificationManager.requestPermission()
        } else {
            Log.debug(
                Log.Category.notifications,
                "Authorization status is \(notificationManager.authorizationStatus.rawValue)")
        }
    }
}
