import AppKit
import Combine
import SwiftUI

// MARK: - Appearance Manager

/// Observable class that tracks system appearance and user color scheme preferences.
/// Uses AppKit to reliably detect system appearance changes for MenuBarExtra windows.
@MainActor
class AppearanceManager: ObservableObject {
    @Published var systemColorScheme: ColorScheme = .dark
    @Published var colorSchemeMode: String {
        didSet {
            UserDefaults.standard.set(colorSchemeMode, forKey: ThemeManager.colorSchemeModeKey)
        }
    }

    private var appearanceObserver: NSKeyValueObservation?
    private var userDefaultsObserver: NSObjectProtocol?

    init() {
        // Load initial color scheme mode from UserDefaults
        self.colorSchemeMode =
            UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
            ?? ColorSchemeMode.system.rawValue

        // Detect initial system appearance
        updateSystemColorScheme()

        // Observe system appearance changes via NSApp
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor in
                self?.updateSystemColorScheme()
            }
        }

        // Observe UserDefaults changes (from SettingsView's @AppStorage)
        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                let newMode =
                    UserDefaults.standard.string(forKey: ThemeManager.colorSchemeModeKey)
                    ?? ColorSchemeMode.system.rawValue
                if self.colorSchemeMode != newMode {
                    self.colorSchemeMode = newMode
                }
            }
        }
    }

    deinit {
        if let observer = userDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func updateSystemColorScheme() {
        let appearance = NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        systemColorScheme = isDark ? .dark : .light
    }

    /// The effective color scheme combining user preference with system setting
    var effectiveColorScheme: ColorScheme {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.effectiveColorScheme(systemScheme: systemColorScheme)
    }

    /// The color scheme preference to pass to SwiftUI (nil means follow system)
    var preferredColorScheme: ColorScheme? {
        let mode = ColorSchemeMode(rawValue: colorSchemeMode) ?? .system
        return mode.colorScheme
    }
}

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

/// A styled button for selecting an account type during account creation.
struct AccountTypeButton: View {
    /// The button's primary label
    let title: String
    /// Secondary description text
    let subtitle: String
    /// SF Symbol name for the icon
    let icon: String
    /// Accent color for hover state
    let color: Color
    /// Action to perform when tapped
    let action: () -> Void

    @State private var isHovering = false
    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isHovering ? color : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isHovering ? color.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                isHovering ? color.opacity(0.3) : Color.secondary.opacity(0.1),
                                lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: theme.fontDesign.design).bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovering ? color : .secondary.opacity(0.5))
            }
            .padding(16)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovering ? color.opacity(0.3) : theme.cardBorder(for: colorScheme),
                        lineWidth: 1)
            )
            .themeOverlay(theme)
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// Steps in the add account flow
enum AddAccountStep {
    /// Showing the account type selection menu
    case menu
    /// Showing Claude account type options (OAuth vs WebView)
    case claudeOptions
    /// Entering Claude OAuth token manually
    case claudeOAuthToken
    /// Entering GLM API token
    case glmToken
}

// MARK: - OAuth Code Entry View

/// View for entering the OAuth authorization code copied from the browser.
struct OAuthCodeEntryView: View {
    @ObservedObject var oauthLogin: AnthropicOAuthLogin
    @State private var codeInput = ""
    @FocusState private var isInputFocused: Bool

    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Icon and title
            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.accentColor)

                Text("Enter Authorization Code")
                    .font(.system(.title2, design: .rounded).bold())
            }

            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 14))
                    Text("Copy the code from the browser")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("After authorizing in your browser, copy the authorization code and paste it below")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )

            // Code input field with paste button
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Paste authorization code here", text: $codeInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .focused($isInputFocused)
                        .onSubmit {
                            submitCode()
                        }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            codeInput = clipboardString
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }

                if let error = oauthLogin.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
            }

            // Buttons
            HStack(spacing: 16) {
                Button("Cancel") {
                    oauthLogin.cancelLogin()
                }
                .buttonStyle(.bordered)

                Button("Submit") {
                    submitCode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if oauthLogin.isAuthenticating {
                ProgressView("Exchanging code...")
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(20)
        .onAppear {
            isInputFocused = true
        }
    }

    private func submitCode() {
        oauthLogin.submitCode(codeInput)
    }
}

// MARK: - Add Account View

/// View for adding new accounts with multi-step flow.
struct AddAccountView: View {
    /// Current step in the add account flow
    @Binding var step: AddAccountStep
    /// Input field for GLM API token
    @Binding var glmTokenInput: String
    /// Input field for Claude OAuth token
    @Binding var claudeOAuthTokenInput: String
    /// Callback when Claude OAuth Sign In is selected (PKCE flow)
    let onClaudeOAuthSignIn: () -> Void
    /// Callback when Claude WebView login is selected
    let onClaudeWebView: () -> Void
    /// Callback when Claude OAuth account is confirmed with token - returns true if added, false if duplicate
    let onClaudeOAuth: (String) -> Bool
    /// Callback when Cursor account is selected
    let onCursor: () -> Void
    /// Callback when GLM account is confirmed with token
    let onGLM: (String) -> Void

    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var isCheckingKeychain = false

    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if step == .menu {
                        accountTypeMenu
                    } else if step == .claudeOptions {
                        claudeOptionsMenu
                    } else if step == .claudeOAuthToken {
                        claudeOAuthTokenEntry
                    } else if step == .glmToken {
                        glmTokenEntry
                    }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var accountTypeMenu: some View {
        VStack(spacing: 12) {
            AccountTypeButton(
                title: "Claude",
                subtitle: "Claude.ai or Claude Code",
                icon: "sparkles",
                color: .orange
            ) {
                step = .claudeOptions
            }

            AccountTypeButton(
                title: "Cursor",
                subtitle: "Monitor local Cursor installation",
                icon: "arrow.triangle.turn.up.right.diamond",
                color: .blue
            ) {
                onCursor()
            }

            AccountTypeButton(
                title: "GLM Coding Plan",
                subtitle: "Zhipu AI GLM Coding Plan",
                icon: "chart.bar.doc.horizontal",
                color: .green
            ) {
                step = .glmToken
            }
        }
    }

    private var claudeOptionsMenu: some View {
        VStack(spacing: 12) {
            // OAuth Sign In (PKCE flow) - Recommended
            AccountTypeButton(
                title: "Sign in with Claude",
                subtitle: "Secure OAuth login (Recommended)",
                icon: "person.badge.key.fill",
                color: .orange
            ) {
                onClaudeOAuthSignIn()
            }

            // Import from Claude Code button
            if isCheckingKeychain {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Importing from keychain...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .background(theme.cardBackground(for: colorScheme))
                .cornerRadius(12)
            } else {
                AccountTypeButton(
                    title: "Import from Claude Code",
                    subtitle: errorMessage ?? "Auto-detect token from keychain",
                    icon: errorMessage != nil ? "xmark.circle" : "arrow.down.circle",
                    color: errorMessage != nil ? .red : .purple
                ) {
                    errorMessage = nil
                    checkForClaudeCodeToken()
                }
            }

            AccountTypeButton(
                title: "Paste OAuth Token",
                subtitle: "Enter session key manually",
                icon: "key.fill",
                color: .gray
            ) {
                step = .claudeOAuthToken
            }

            AccountTypeButton(
                title: "Browser Login",
                subtitle: "Login via claude.ai WebView",
                icon: "globe",
                color: .blue
            ) {
                onClaudeWebView()
            }
        }
    }

    private func checkForClaudeCodeToken() {
        isCheckingKeychain = true

        Task {
            do {
                let token = try ClaudeCodeKeychainReader.readOAuthToken()
                await MainActor.run {
                    isCheckingKeychain = false
                    // Add account directly when token is found
                    if !onClaudeOAuth(token) {
                        errorMessage = "This account has already been added"
                    }
                }
            } catch {
                await MainActor.run {
                    isCheckingKeychain = false
                    errorMessage = "No Claude Code credentials found"
                }
            }
        }
    }

    private var claudeOAuthTokenEntry: some View {
        VStack(spacing: 16) {
            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 14))
                    Text("How to get your session key:")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("Check browser DevTools on claude.ai")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Text("Network tab →")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("api.anthropic.com")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("→ Auth header")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text("Token starts with sk-ant-sid01-...")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
            )

            // Token input with paste button
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your OAuth token here", text: $claudeOAuthTokenInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: claudeOAuthTokenInput) {
                            errorMessage = nil
                        }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            claudeOAuthTokenInput = clipboardString
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
            }

            Button {
                Task {
                    await validateAndSubmitOAuthToken()
                }
            } label: {
                if isValidating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Validating...")
                    }
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                claudeOAuthTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isValidating)

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmitOAuthToken() async {
        let token = claudeOAuthTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidating = true
        errorMessage = nil

        do {
            let service = AnthropicOAuthService()
            _ = try await service.fetchUsage(token: token)

            // Check for cancellation before updating state
            guard !Task.isCancelled else { return }

            if onClaudeOAuth(token) {
                claudeOAuthTokenInput = ""
            } else {
                errorMessage = "This account has already been added"
            }
        } catch {
            // Check for cancellation before updating state
            guard !Task.isCancelled else { return }

            errorMessage = "Could not validate token. Please check and try again."
        }

        isValidating = false
    }

    private var glmTokenEntry: some View {
        VStack(spacing: 16) {
            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text("How to get your API token:")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("1. Visit z.ai and sign in")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("2. Go to API Keys section")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("3. Create or copy an existing API key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Button to open the API page
                Button {
                    if let url = URL(string: "https://z.ai/manage-apikey/apikey-list") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("Open API Keys Page")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.link)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.green.opacity(0.2), lineWidth: 1)
            )

            // API token input with paste button
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your API token here", text: $glmTokenInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: glmTokenInput) {
                            errorMessage = nil
                        }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            glmTokenInput = clipboardString
                        }
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .help("Paste from clipboard")
                }

                if let error = errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                    }
                    .transition(.opacity)
                }
            }

            Button {
                Task {
                    await validateAndSubmit()
                }
            } label: {
                if isValidating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Validating...")
                    }
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                glmTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || isValidating)

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmit() async {
        let token = glmTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidating = true
        errorMessage = nil

        do {
            let isValid = try await AppState.validateGLMToken(token)

            // Check for cancellation before updating state
            guard !Task.isCancelled else { return }

            if isValid {
                onGLM(token)
                glmTokenInput = ""
            } else {
                errorMessage = "Invalid API token. Please check and try again."
            }
        } catch {
            // Check for cancellation before updating state
            guard !Task.isCancelled else { return }

            // Distinguish GLMTrackerError types for better error messages
            if let glmError = error as? GLMTrackerError {
                errorMessage = glmError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isValidating = false
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
        .frame(width: 405, height: 660)
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
                    appState.addClaudeOAuthAccount(oauthToken: accessToken, refreshToken: refreshToken)
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

/// A button with an SF Symbol icon that responds to hover state.
struct HoverIconButton: View {
    /// SF Symbol name for the icon
    let image: String
    /// Tooltip text shown on hover
    let helpText: String
    /// Color to use when hovered
    var color: Color = .primary
    /// Action to perform when tapped
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .medium))  // Slightly larger icon
                .foregroundColor(isHovering ? color : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())  // Ensures entire 32x32 area is clickable
        .help(helpText)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// A styled quit button that terminates the application.
struct QuitButton: View {
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isHovering ? .red : .secondary)  // Red on hover to indicate destructive/quit
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.red.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isHovering ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1),
                            lineWidth: 1)
                )
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Quit Application")
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// A card with a dashed border for adding new accounts.
struct AddAccountCardView: View {
    /// Action to perform when the card is tapped
    let action: () -> Void
    @State private var isHovering = false

    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(theme.accentPrimary.opacity(0.8))
                    Text("Add Account")
                        .font(.system(.body, design: theme.fontDesign.design).bold())
                        .foregroundColor(theme.accentPrimary.opacity(0.8))
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        isHovering ? theme.accentPrimary : theme.accentPrimary.opacity(0.5),
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: theme.addAccountBorderStyle == .dashed ? [8, 4] : []
                        )
                    )
            )
            .themeOverlay(theme)
            .shadow(
                color: theme.cardHasShadow ? theme.cardShadowColor : .clear,
                radius: theme.cardShadowRadius
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// Central application state managing all account sessions and persistence.
/// Handles account lifecycle, session monitoring, and data storage.
@Observable
@MainActor
class AppState {
    /// All active account monitoring sessions
    var sessions: [AccountSession] = []
    /// When the next automatic refresh will occur
    var nextRefresh: Date = Date()
    /// Trigger for refreshing the menu bar icon
    var iconRefreshTrigger = UUID()

    private let defaults = UserDefaults.standard
    private let accountsKey = Constants.UserDefaultsKeys.savedAccounts

    init() {
        loadAccounts()
    }

    /// Adds a new Claude account with the given authentication cookies.
    /// - Parameter cookies: Authentication cookies from the login session
    func addAccount(cookies: [HTTPCookie]) {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Account \(sessions.count + 1)",
            cookies: cookies,
            usageData: nil,
            type: .claude
        )
        // Save cookies to Keychain
        newAccount.saveCredentialsToKeychain()

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    /// Adds a new Claude account with an OAuth token.
    /// - Parameters:
    ///   - oauthToken: The OAuth token from Claude Code or manual entry
    ///   - refreshToken: Optional refresh token for obtaining new access tokens
    /// - Returns: true if account was added, false if duplicate
    @discardableResult
    func addClaudeOAuthAccount(oauthToken: String, refreshToken: String? = nil) -> Bool {
        // Check for duplicate OAuth token
        for session in sessions {
            if session.account.oauthToken == oauthToken {
                Log.warning(Log.Category.app, "Duplicate OAuth account not added")
                return false
            }
        }

        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Claude Code",
            oauthToken: oauthToken,
            refreshToken: refreshToken,
            usageData: nil
        )
        // Save OAuth token and refresh token to Keychain
        newAccount.saveCredentialsToKeychain()

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Re-authenticates an existing account with new OAuth tokens.
    /// - Parameters:
    ///   - accountId: The ID of the account to re-authenticate
    ///   - oauthToken: The new OAuth access token
    ///   - refreshToken: Optional new refresh token
    func reAuthenticateAccount(accountId: UUID, oauthToken: String, refreshToken: String? = nil) {
        guard let sessionIndex = sessions.firstIndex(where: { $0.account.id == accountId }) else {
            Log.warning(Log.Category.app, "Cannot re-authenticate: account not found")
            return
        }

        Log.info(Log.Category.app, "Re-authenticating account \(sessions[sessionIndex].account.name)")

        // Update the account's tokens
        sessions[sessionIndex].account.oauthToken = oauthToken
        sessions[sessionIndex].account.oauthRefreshToken = refreshToken
        sessions[sessionIndex].account.needsReauth = false

        // Save new credentials to Keychain
        sessions[sessionIndex].account.saveCredentialsToKeychain()

        // Save accounts and trigger a fetch
        saveAccounts()
        sessions[sessionIndex].fetchNow()
    }

    /// Checks if an OAuth token is already registered
    func hasOAuthAccount(token: String) -> Bool {
        sessions.contains { $0.account.oauthToken == token }
    }

    /// Adds a new Cursor IDE monitoring account.
    func addCursorAccount() {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Cursor Monitoring",
            cookies: [],
            usageData: nil,
            type: .cursor
        )
        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    /// Adds a new GLM Coding Plan account with the given API token.
    /// - Parameter apiToken: The GLM API token for authentication
    func addGLMAccount(apiToken: String) {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "GLM Coding Plan",
            apiToken: apiToken,
            usageData: nil
        )
        // Save API token to Keychain
        newAccount.saveCredentialsToKeychain()

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    /// Validates a GLM API token by attempting to fetch usage data.
    /// - Parameter token: The API token to validate
    /// - Returns: True if the token is valid and can fetch usage data
    /// - Throws: GLMTrackerError if the validation fails
    static func validateGLMToken(_ token: String) async throws -> Bool {
        let tracker = GLMTrackerService()
        let info = try await tracker.fetchGLMUsage(apiToken: token)
        return info.sessionLimit > 0 || info.monthlyLimit > 0 || info.sessionPercentage >= 0
    }

    private func subscribeToSessionChanges(_ session: AccountSession) {
        // With @Observable, SwiftUI automatically tracks changes to session properties
        // We just need to set up the refresh tick callback
        session.onRefreshTick = { [weak self] in
            Task { @MainActor in
                self?.nextRefresh = Date().addingTimeInterval(
                    self?.refreshIntervalSeconds() ?? Constants.Timeouts.defaultRefreshInterval)
            }
        }
    }

    /// Removes an account and its associated credentials.
    /// - Parameter id: The UUID of the account to remove
    func removeAccount(id: UUID) {
        // Find the account and delete its credentials from Keychain
        if let session = sessions.first(where: { $0.account.id == id }) {
            session.account.deleteCredentialsFromKeychain()
        }
        sessions.removeAll { $0.account.id == id }
        saveAccounts()
    }

    /// Triggers an immediate refresh of all account usage data.
    func refreshAll() {
        let nextInterval = refreshIntervalSeconds()
        Log.debug(Log.Category.appState, "Refreshing all accounts... Next in \(Int(nextInterval))s")
        for session in sessions {
            session.fetchNow()
        }
        nextRefresh = Date().addingTimeInterval(nextInterval)
    }

    /// Reschedules refresh timers for all sessions based on current settings.
    func rescheduleAllSessions() {
        for session in sessions {
            session.scheduleRefreshTimer()
        }
        nextRefresh = Date().addingTimeInterval(refreshIntervalSeconds())
    }

    /// Returns the configured refresh interval in seconds.
    /// - Returns: The refresh interval, or default if not configured
    func refreshIntervalSeconds() -> TimeInterval {
        let interval = defaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        return interval > 0 ? interval : Constants.Timeouts.defaultRefreshInterval
    }

    private func saveAccounts() {
        let accounts = sessions.map { $0.account }
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: accountsKey)
        }
    }

    private func loadAccounts() {
        // First, try to migrate any legacy data from UserDefaults
        migrateCredentialsFromUserDefaults()

        if let data = defaults.data(forKey: accountsKey),
            var accounts = try? JSONDecoder().decode([ClaudeAccount].self, from: data)
        {
            Log.info(Log.Category.app, "Loading \(accounts.count) saved accounts")
            for i in accounts.indices {
                accounts[i].usageData = nil
                // Load credentials from Keychain
                accounts[i].loadCredentialsFromKeychain()
                Log.debug(
                    Log.Category.app,
                    "Account[\(i)]: \(accounts[i].name), type=\(accounts[i].type), hasCredentials=\(accounts[i].hasCredentials)"
                )
            }

            self.sessions = accounts.map { AccountSession(account: $0) }

            for session in self.sessions {
                subscribeToSessionChanges(session)
                session.startMonitoring()
            }
        } else {
            Log.info(Log.Category.app, "No saved accounts found")
        }
    }

    /// Migrate credentials from old UserDefaults storage to Keychain (one-time migration)
    /// Only marks migration complete if ALL credentials are successfully migrated.
    /// If any migration fails, it will be retried on subsequent launches.
    private func migrateCredentialsFromUserDefaults() {
        let migrationKey = Constants.UserDefaultsKeys.keychainMigrationComplete
        guard !defaults.bool(forKey: migrationKey) else { return }

        Log.info(Log.Category.keychain, "Starting migration from UserDefaults to Keychain...")

        var allMigrationsSucceeded = true

        // Try to load old-format accounts that included credentials
        if let data = defaults.data(forKey: accountsKey) {
            // Decode with a temporary struct that includes the old fields
            struct LegacyAccount: Codable {
                var id: UUID
                var name: String
                var type: AccountType?
                var cookieProps: [[String: String]]?
                var apiToken: String?
            }

            do {
                let legacyAccounts = try JSONDecoder().decode([LegacyAccount].self, from: data)
                for legacy in legacyAccounts {
                    // Migrate cookies if present
                    if let cookies = legacy.cookieProps, !cookies.isEmpty {
                        do {
                            try KeychainService.save(
                                cookies, forKey: KeychainService.cookiesKey(for: legacy.id))
                            Log.info(
                                Log.Category.keychain, "Migrated cookies for account \(legacy.id)")
                        } catch {
                            Log.error(
                                Log.Category.keychain,
                                "Failed to migrate cookies for \(legacy.id): \(error)")
                            allMigrationsSucceeded = false
                        }
                    }

                    // Migrate API token if present
                    if let token = legacy.apiToken {
                        do {
                            try KeychainService.save(
                                token, forKey: KeychainService.apiTokenKey(for: legacy.id))
                            Log.info(
                                Log.Category.keychain, "Migrated API token for account \(legacy.id)"
                            )
                        } catch {
                            Log.error(
                                Log.Category.keychain,
                                "Failed to migrate API token for \(legacy.id): \(error)")
                            allMigrationsSucceeded = false
                        }
                    }
                }
            } catch {
                Log.error(Log.Category.keychain, "Failed to decode legacy accounts: \(error)")
                allMigrationsSucceeded = false
            }
        }

        // Only mark migration complete if ALL credentials migrated successfully
        // This allows retry on subsequent launches if Keychain was temporarily unavailable
        if allMigrationsSucceeded {
            defaults.set(true, forKey: migrationKey)
            Log.info(Log.Category.keychain, "Migration complete")
        } else {
            Log.warning(Log.Category.keychain, "Migration incomplete - will retry on next launch")
        }
    }

    /// Computes the current menu bar icon state based on account statuses.
    var menuBarIconState: MenuBarIconState {
        guard !sessions.isEmpty else { return .noAccounts }

        if sessions.contains(where: { $0.isFetching }) {
            return .loading
        }

        let accountsWithData = sessions.compactMap { $0.account.usageData }

        if accountsWithData.isEmpty {
            return .noData
        }

        let maxSessionPercentage = accountsWithData.map { $0.sessionPercentage }.max() ?? 0

        let hasReadyState = accountsWithData.contains {
            $0.sessionPercentage == 0 && $0.sessionReset == "Ready"
        }

        if hasReadyState && maxSessionPercentage == 0 {
            return .ready
        } else if maxSessionPercentage < 0.5 {
            return .lowUsage
        } else if maxSessionPercentage < 0.75 {
            return .mediumUsage
        } else {
            return .highUsage
        }
    }

    /// Reset all app data to factory state
    /// Clears UserDefaults, Keychain, and in-memory sessions
    func resetAllData() {
        Log.info(Log.Category.app, "Resetting all app data...")

        // Stop all session monitors
        for session in sessions {
            session.stopMonitoring()
        }

        // Clear in-memory sessions
        sessions.removeAll()

        // Clear Keychain (credentials)
        KeychainService.deleteAll()

        // Clear UserDefaults - explicitly remove all known keys
        // (removePersistentDomain is unreliable with @AppStorage)
        let keysToRemove = [
            // Account data
            Constants.UserDefaultsKeys.savedAccounts,
            Constants.UserDefaultsKeys.keychainMigrationComplete,
            // Settings
            Constants.UserDefaultsKeys.refreshInterval,
            Constants.UserDefaultsKeys.autoWakeUp,
            Constants.UserDefaultsKeys.debugModeEnabled,
            // Notification settings
            NotificationSettings.enabledKey,
            NotificationSettings.sessionReadyEnabledKey,
            NotificationSettings.sessionThreshold1EnabledKey,
            NotificationSettings.sessionThreshold2EnabledKey,
            NotificationSettings.weeklyThreshold1EnabledKey,
            NotificationSettings.weeklyThreshold2EnabledKey,
            NotificationSettings.threshold1ValueKey,
            NotificationSettings.threshold2ValueKey,
        ]

        for key in keysToRemove {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()

        Log.info(Log.Category.app, "All app data has been reset")
    }
}

/// Displays a countdown timer to the next automatic refresh.
struct CountdownView: View {
    /// The target date/time for the countdown
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let diff = target.timeIntervalSince(context.date)
            if diff > 0 {
                Text("Refresh: \(timeString(from: diff))")
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            } else {
                Text("Refreshing...")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }

    func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Represents the visual state of the menu bar icon based on usage.
enum MenuBarIconState {
    /// No accounts configured
    case noAccounts
    /// Data is being fetched
    case loading
    /// No usage data available
    case noData
    /// Session is ready to use (0% usage)
    case ready
    /// Usage below 50%
    case lowUsage
    /// Usage between 50-75%
    case mediumUsage
    /// Usage above 75%
    case highUsage

    /// The SF Symbol name for this state
    var iconName: String {
        switch self {
        case .noAccounts: return "xmark.circle"
        case .loading: return "circle.dotted"
        case .noData: return "questionmark.circle"
        case .ready: return "play.circle.fill"
        case .lowUsage, .mediumUsage, .highUsage: return "checkmark.circle"
        }
    }

    /// The color associated with this state
    var iconColor: Color {
        switch self {
        case .noAccounts: return .secondary
        case .loading: return .blue
        case .noData: return .gray
        case .ready: return .green
        case .lowUsage: return .green
        case .mediumUsage: return .orange
        case .highUsage: return .red
        }
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
