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
    /// Tracks the current OAuth validation task for cancellation
    @State private var oauthValidationTask: Task<Void, Never>?
    /// Tracks the current GLM validation task for cancellation
    @State private var glmValidationTask: Task<Void, Never>?

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
                    }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
        .onDisappear {
            // Cancel any in-flight validation tasks when view disappears
            oauthValidationTask?.cancel()
            glmValidationTask?.cancel()
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
