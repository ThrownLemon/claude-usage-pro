import AppKit
import SwiftUI

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
    /// Showing Gemini account options (CLI auto-detect vs manual token)
    case geminiOptions
    /// Entering Gemini token manually
    case geminiToken
    /// Detecting Antigravity IDE
    case antigravityDetect
    /// Entering OpenAI Admin API key
    case openaiApiKey
    /// Showing Codex account options (CLI auto-detect vs manual token)
    case codexOptions
    /// Entering Codex token manually
    case codexToken
}

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

/// View for adding new accounts with multi-step flow.
struct AddAccountView: View {
    /// Current step in the add account flow
    @Binding var step: AddAccountStep
    /// Input field for GLM API token
    @Binding var glmTokenInput: String
    /// Input field for Claude OAuth token
    @Binding var claudeOAuthTokenInput: String
    /// Input field for Gemini token
    @Binding var geminiTokenInput: String
    /// Input field for OpenAI Admin API key
    @Binding var openaiApiKeyInput: String
    /// Input field for Codex token
    @Binding var codexTokenInput: String
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
    /// Callback when Gemini account is added - returns true if added, false if duplicate
    let onGemini: () -> Bool
    /// Callback when Antigravity account is added - returns true if added, false if not running
    let onAntigravity: () -> Bool
    /// Callback when OpenAI account is confirmed with Admin API key - returns true if added
    let onOpenAI: (String) -> Bool
    /// Callback when Codex account is added from CLI - returns true if added
    let onCodexCLI: () -> Bool
    /// Callback when Codex account is confirmed with token - returns true if added
    let onCodex: (String) -> Bool

    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var isCheckingKeychain = false
    @State private var isCheckingGemini = false
    @State private var isCheckingAntigravity = false
    @State private var isCheckingCodex = false
    /// Tracks the current OAuth validation task for cancellation
    @State private var oauthValidationTask: Task<Void, Never>?
    /// Tracks the current GLM validation task for cancellation
    @State private var glmValidationTask: Task<Void, Never>?
    /// Tracks the current keychain check task for cancellation
    @State private var keychainTask: Task<Void, Never>?
    /// Tracks the current Gemini validation task for cancellation
    @State private var geminiValidationTask: Task<Void, Never>?
    /// Tracks the current Antigravity detection task for cancellation
    @State private var antigravityTask: Task<Void, Never>?
    /// Tracks the current OpenAI validation task for cancellation
    @State private var openaiValidationTask: Task<Void, Never>?
    /// Tracks the current Codex validation task for cancellation
    @State private var codexValidationTask: Task<Void, Never>?

    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard.rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    switch step {
                    case .menu:
                        accountTypeMenu
                    case .claudeOptions:
                        claudeOptionsMenu
                    case .claudeOAuthToken:
                        claudeOAuthTokenEntry
                    case .glmToken:
                        glmTokenEntry
                    case .geminiOptions:
                        geminiOptionsMenu
                    case .geminiToken:
                        geminiTokenEntry
                    case .antigravityDetect:
                        antigravityDetectView
                    case .openaiApiKey:
                        openaiApiKeyEntry
                    case .codexOptions:
                        codexOptionsMenu
                    case .codexToken:
                        codexTokenEntry
                    }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
        .onDisappear {
            // Cancel any in-flight tasks when view disappears
            oauthValidationTask?.cancel()
            glmValidationTask?.cancel()
            keychainTask?.cancel()
            geminiValidationTask?.cancel()
            antigravityTask?.cancel()
            openaiValidationTask?.cancel()
            codexValidationTask?.cancel()
        }
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

            AccountTypeButton(
                title: "Google Gemini CLI",
                subtitle: "Gemini CLI quota tracking",
                icon: "wand.and.stars",
                color: .purple
            ) {
                step = .geminiOptions
            }

            AccountTypeButton(
                title: "Google Antigravity",
                subtitle: "Antigravity IDE (must be running)",
                icon: "atom",
                color: .cyan
            ) {
                step = .antigravityDetect
            }

            AccountTypeButton(
                title: "OpenAI API",
                subtitle: "Pay-per-token usage tracking",
                icon: "brain",
                color: .teal
            ) {
                step = .openaiApiKey
            }

            AccountTypeButton(
                title: "OpenAI Codex CLI",
                subtitle: "ChatGPT Plus/Pro subscription",
                icon: "terminal",
                color: .indigo
            ) {
                step = .codexOptions
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
        // Cancel any existing keychain task
        keychainTask?.cancel()
        isCheckingKeychain = true

        keychainTask = Task {
            do {
                let token = try ClaudeCodeKeychainReader.readOAuthToken()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isCheckingKeychain = false
                    keychainTask = nil
                    // Add account directly when token is found
                    if !onClaudeOAuth(token) {
                        errorMessage = "This account has already been added"
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    isCheckingKeychain = false
                    keychainTask = nil
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
                // Cancel any existing validation task before starting a new one
                oauthValidationTask?.cancel()
                oauthValidationTask = Task {
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
        defer { isValidating = false }
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
                // Cancel any existing validation task before starting a new one
                glmValidationTask?.cancel()
                glmValidationTask = Task {
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
        defer { isValidating = false }
        errorMessage = nil

        do {
            // validateGLMToken returns true or throws - no else branch needed
            _ = try await AppState.validateGLMToken(token)

            // Check for cancellation before updating state
            guard !Task.isCancelled else { return }

            onGLM(token)
            glmTokenInput = ""
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
    }

    // MARK: - Gemini Views

    private var geminiOptionsMenu: some View {
        VStack(spacing: 12) {
            // Auto-detect from CLI
            if isCheckingGemini {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Detecting Gemini CLI...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .background(theme.cardBackground(for: colorScheme))
                .cornerRadius(12)
            } else {
                AccountTypeButton(
                    title: "Import from Gemini CLI",
                    subtitle: errorMessage ?? "Auto-detect from ~/.gemini",
                    icon: errorMessage != nil ? "xmark.circle" : "arrow.down.circle",
                    color: errorMessage != nil ? .red : .purple
                ) {
                    errorMessage = nil
                    detectGeminiCLI()
                }
            }

            AccountTypeButton(
                title: "Enter Token Manually",
                subtitle: "Paste OAuth token",
                icon: "key.fill",
                color: .gray
            ) {
                step = .geminiToken
            }
        }
    }

    /// Shared helper to detect CLI credentials and add account
    /// - Parameters:
    ///   - taskRef: Reference to the task to cancel and update
    ///   - isChecking: Binding to the loading state
    ///   - onDetect: Callback that returns true if account was added
    ///   - failureMessage: Error message to show if detection fails
    private func detectCLICredentials(
        cancelTask: inout Task<Void, Never>?,
        setChecking: @escaping (Bool) -> Void,
        onDetect: @escaping () -> Bool,
        failureMessage: String
    ) {
        cancelTask?.cancel()
        setChecking(true)

        let task = Task {
            await MainActor.run {
                let success = onDetect()
                setChecking(false)
                if !success {
                    errorMessage = failureMessage
                }
            }
        }
        cancelTask = task
    }

    private func detectGeminiCLI() {
        detectCLICredentials(
            cancelTask: &geminiValidationTask,
            setChecking: { self.isCheckingGemini = $0 },
            onDetect: onGemini,
            failureMessage: "Gemini CLI not found or already added"
        )
    }

    private var geminiTokenEntry: some View {
        VStack(spacing: 16) {
            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))
                    Text("How to get your OAuth token:")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("1. Run 'gemini auth login' in terminal")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("2. Find ~/.gemini/oauth_creds.json")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("3. Copy the access_token value")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )

            // Token input
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your access token here", text: $geminiTokenInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: geminiTokenInput) { errorMessage = nil }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            geminiTokenInput = clipboardString
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
                }
            }

            Button {
                geminiValidationTask?.cancel()
                geminiValidationTask = Task {
                    await validateAndSubmitGeminiToken()
                }
            } label: {
                if isValidating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Validating...")
                    }
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(geminiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmitGeminiToken() async {
        let token = geminiTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidating = true
        defer { isValidating = false }
        errorMessage = nil

        do {
            _ = try await AppState.validateGeminiToken(token)
            guard !Task.isCancelled else { return }
            // Token is valid but manual entry doesn't have a refresh token.
            // We can still add the account - it will work until the token expires.
            // The user will need to re-import from CLI when that happens.
            // Note: We pass empty string for refresh token since manual tokens don't include it
            errorMessage = "Token validated. Note: Manual tokens cannot auto-refresh. " +
                "For automatic token renewal, use 'Import from Gemini CLI' instead."
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Antigravity Views

    private var antigravityDetectView: some View {
        VStack(spacing: 16) {
            // Info card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.cyan)
                        .font(.system(size: 14))
                    Text("Antigravity IDE Detection")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("Antigravity IDE must be running to detect and monitor usage.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("The app will connect to the local language server.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
            )

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
            }

            Button {
                antigravityTask?.cancel()
                antigravityTask = Task {
                    await detectAntigravity()
                }
            } label: {
                if isCheckingAntigravity {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Detecting Antigravity...")
                    }
                } else {
                    Text("Detect Antigravity IDE")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isCheckingAntigravity)

            Spacer()
        }
    }

    @MainActor
    private func detectAntigravity() async {
        isCheckingAntigravity = true
        defer { isCheckingAntigravity = false }
        errorMessage = nil

        if onAntigravity() {
            // Success - view will dismiss
        } else {
            errorMessage = "Antigravity IDE not running or already added"
        }
    }

    // MARK: - OpenAI Views

    private var openaiApiKeyEntry: some View {
        VStack(spacing: 16) {
            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.teal)
                        .font(.system(size: 14))
                    Text("OpenAI Admin API Key Required")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("Usage tracking requires an Admin API key.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Only Organization Owners can create Admin keys.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Key format: sk-admin-...")
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundColor(.teal)

                Button {
                    if let url = URL(string: "https://platform.openai.com/settings/organization/api-keys") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.square")
                        Text("Open OpenAI API Keys")
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
                    .stroke(Color.teal.opacity(0.2), lineWidth: 1)
            )

            // API key input
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your Admin API key here", text: $openaiApiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openaiApiKeyInput) { errorMessage = nil }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            openaiApiKeyInput = clipboardString
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
                }
            }

            Button {
                openaiValidationTask?.cancel()
                openaiValidationTask = Task {
                    await validateAndSubmitOpenAIKey()
                }
            } label: {
                if isValidating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Validating...")
                    }
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(openaiApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmitOpenAIKey() async {
        let key = openaiApiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }

        isValidating = true
        defer { isValidating = false }
        errorMessage = nil

        do {
            _ = try await AppState.validateOpenAIAdminKey(key)
            guard !Task.isCancelled else { return }

            if onOpenAI(key) {
                openaiApiKeyInput = ""
            } else {
                errorMessage = "This account has already been added"
            }
        } catch {
            guard !Task.isCancelled else { return }
            if let openaiError = error as? OpenAITrackerError {
                errorMessage = openaiError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Codex Views

    private var codexOptionsMenu: some View {
        VStack(spacing: 12) {
            // Auto-detect from CLI
            if isCheckingCodex {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Detecting Codex CLI...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .background(theme.cardBackground(for: colorScheme))
                .cornerRadius(12)
            } else {
                AccountTypeButton(
                    title: "Import from Codex CLI",
                    subtitle: errorMessage ?? "Auto-detect from ~/.codex",
                    icon: errorMessage != nil ? "xmark.circle" : "arrow.down.circle",
                    color: errorMessage != nil ? .red : .indigo
                ) {
                    errorMessage = nil
                    detectCodexCLI()
                }
            }

            AccountTypeButton(
                title: "Enter Token Manually",
                subtitle: "Paste auth token",
                icon: "key.fill",
                color: .gray
            ) {
                step = .codexToken
            }
        }
    }

    private func detectCodexCLI() {
        detectCLICredentials(
            cancelTask: &codexValidationTask,
            setChecking: { self.isCheckingCodex = $0 },
            onDetect: onCodexCLI,
            failureMessage: "Codex CLI not found or already added"
        )
    }

    private var codexTokenEntry: some View {
        VStack(spacing: 16) {
            // Instructions card
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.indigo)
                        .font(.system(size: 14))
                    Text("How to get your Codex token:")
                        .font(.subheadline.bold())
                        .foregroundColor(.primary)
                }

                Text("1. Run 'codex auth' in terminal")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("2. Find ~/.codex/auth.json")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("3. Copy the access_token value")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.indigo.opacity(0.2), lineWidth: 1)
            )

            // Token input
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    SecureField("Paste your auth token here", text: $codexTokenInput)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codexTokenInput) { errorMessage = nil }

                    Button {
                        if let clipboardString = NSPasteboard.general.string(forType: .string) {
                            codexTokenInput = clipboardString
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
                }
            }

            Button {
                codexValidationTask?.cancel()
                codexValidationTask = Task {
                    await validateAndSubmitCodexToken()
                }
            } label: {
                if isValidating {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Validating...")
                    }
                } else {
                    Text("Add Account")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(codexTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmitCodexToken() async {
        let token = codexTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidating = true
        defer { isValidating = false }
        errorMessage = nil

        do {
            _ = try await AppState.validateCodexToken(token)
            guard !Task.isCancelled else { return }

            if onCodex(token) {
                codexTokenInput = ""
            } else {
                errorMessage = "This account has already been added"
            }
        } catch {
            guard !Task.isCancelled else { return }
            if let codexError = error as? CodexTrackerError {
                errorMessage = codexError.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }
}
