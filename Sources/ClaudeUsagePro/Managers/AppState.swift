import Foundation
import Observation

/// Represents the visual state of the menu bar icon based on usage.
/// Note: Color mapping is handled in the UI layer to keep this enum UI-agnostic.
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
        case .noAccounts: "xmark.circle"
        case .loading: "circle.dotted"
        case .noData: "questionmark.circle"
        case .ready: "play.circle.fill"
        case .lowUsage, .mediumUsage, .highUsage: "checkmark.circle"
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
    var nextRefresh: Date = .init()
    /// Trigger for refreshing the menu bar icon
    var iconRefreshTrigger = UUID()

    private let defaults = UserDefaults.standard
    private let accountsKey = Constants.UserDefaultsKeys.savedAccounts

    /// Track whether monitoring has been started to avoid duplicate starts
    private var hasStartedMonitoring = false

    init() {
        loadAccounts()
    }

    /// Starts monitoring for all loaded sessions.
    /// Safe to call multiple times - will only start monitoring once.
    /// Call this after app UI is ready (e.g., from onAppear).
    func startMonitoringAll() {
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true

        Log.debug(Log.Category.app, "Starting monitoring for \(sessions.count) sessions")
        for session in sessions {
            session.startMonitoring()
        }
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
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(
                Log.Category.app,
                "Failed to save credentials to Keychain for new account - credentials may not persist"
            )
        }

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
        for session in sessions where session.account.oauthToken == oauthToken {
            Log.warning(Log.Category.app, "Duplicate OAuth account not added")
            return false
        }

        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Claude Code",
            oauthToken: oauthToken,
            refreshToken: refreshToken,
            usageData: nil
        )
        // Save OAuth token and refresh token to Keychain
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save OAuth credentials to Keychain - credentials may not persist")
        }

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
        if !sessions[sessionIndex].account.saveCredentialsToKeychain() {
            Log.warning(
                Log.Category.app,
                "Failed to save re-auth credentials to Keychain - credentials may not persist"
            )
        }

        // Save accounts and trigger a fetch
        saveAccounts()
        sessions[sessionIndex].fetchNow()

        // Clear any delivered re-auth notifications for this account
        let notificationKey = NotificationManager.shared.cooldownKey(
            accountId: accountId,
            type: .needsReauthentication
        )
        NotificationManager.shared.removeDeliveredNotification(identifier: notificationKey)
    }

    /// Checks if an OAuth token is already registered
    func hasOAuthAccount(token: String) -> Bool {
        sessions.contains { $0.account.oauthToken == token }
    }

    /// Adds a new Cursor IDE monitoring account.
    /// - Returns: True if account was added, false if a Cursor account already exists
    @discardableResult
    func addCursorAccount() -> Bool {
        // Check for existing Cursor account
        if sessions.contains(where: { $0.account.type == .cursor }) {
            Log.warning(Log.Category.app, "Cursor account already exists")
            return false
        }

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
        return true
    }

    /// Adds a new GLM Coding Plan account with the given API token.
    /// - Parameter apiToken: The GLM API token for authentication
    /// - Returns: True if account was added, false if a GLM account with this token already exists
    @discardableResult
    func addGLMAccount(apiToken: String) -> Bool {
        // Check for existing GLM account with same token
        if sessions.contains(where: { $0.account.type == .glm && $0.account.apiToken == apiToken }) {
            Log.warning(Log.Category.app, "GLM account with this token already exists")
            return false
        }

        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "GLM Coding Plan",
            apiToken: apiToken,
            usageData: nil
        )
        // Save API token to Keychain
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save GLM API token to Keychain - credentials may not persist")
        }

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Validates a GLM API token by attempting to fetch usage data.
    /// - Parameter token: The API token to validate
    /// - Returns: True if the token is valid (successful fetch)
    /// - Throws: GLMTrackerError if the validation fails
    static func validateGLMToken(_ token: String) async throws -> Bool {
        let tracker = GLMTrackerService()
        // A successful fetch proves the token is valid, regardless of limit values
        _ = try await tracker.fetchGLMUsage(apiToken: token)
        return true
    }

    // MARK: - Gemini Account Management

    /// Adds a new Google Gemini account with OAuth tokens.
    /// - Parameters:
    ///   - accessToken: The OAuth access token
    ///   - refreshToken: The OAuth refresh token
    ///   - idToken: Optional ID token
    ///   - tokenExpiry: Optional token expiry date
    /// - Returns: True if account was added, false if a duplicate exists
    @discardableResult
    func addGeminiAccount(
        accessToken: String,
        refreshToken: String,
        idToken: String? = nil,
        tokenExpiry: Date? = nil
    ) -> Bool {
        // Check for existing Gemini account with same access token
        if sessions.contains(where: { $0.account.type == .gemini && $0.account.geminiAccessToken == accessToken }) {
            Log.warning(Log.Category.app, "Gemini account with this token already exists")
            return false
        }

        let newAccount = ClaudeAccount(
            name: "Gemini",
            geminiAccessToken: accessToken,
            geminiRefreshToken: refreshToken,
            geminiIdToken: idToken,
            geminiTokenExpiry: tokenExpiry
        )

        // Save tokens to Keychain
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save Gemini tokens to Keychain - credentials may not persist")
        }

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Adds a Gemini account by auto-detecting credentials from ~/.gemini/oauth_creds.json.
    /// - Returns: True if account was added, false if detection failed or duplicate exists
    @discardableResult
    func addGeminiAccountFromCLI() -> Bool {
        let tracker = GeminiTrackerService()

        guard let tokens = tracker.detectGeminiCLI() else {
            Log.warning(Log.Category.app, "Gemini CLI credentials not found")
            return false
        }

        let tokenExpiry: Date?
        if let expiry = tokens.expiryDate {
            tokenExpiry = Date(timeIntervalSince1970: Double(expiry) / 1000.0)
        } else {
            tokenExpiry = nil
        }

        return addGeminiAccount(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            idToken: tokens.idToken,
            tokenExpiry: tokenExpiry
        )
    }

    /// Validates Gemini OAuth tokens by attempting to fetch usage data.
    /// - Parameter accessToken: The OAuth access token to validate
    /// - Returns: True if the token is valid (successful fetch)
    /// - Throws: GeminiTrackerError if the validation fails
    static func validateGeminiToken(_ accessToken: String) async throws -> Bool {
        let tracker = GeminiTrackerService()
        _ = try await tracker.fetchUsage(accessToken: accessToken)
        return true
    }

    // MARK: - Antigravity Account Management

    /// Adds a new Google Antigravity account.
    /// Antigravity doesn't require stored credentials - it auto-detects from the running IDE process.
    /// - Returns: True if account was added, false if Antigravity isn't running or duplicate exists
    @discardableResult
    func addAntigravityAccount() -> Bool {
        // Check for existing Antigravity account
        if sessions.contains(where: { $0.account.type == .antigravity }) {
            Log.warning(Log.Category.app, "Antigravity account already exists")
            return false
        }

        // Verify Antigravity is running
        let tracker = AntigravityTrackerService()
        guard tracker.isRunning else {
            Log.warning(Log.Category.app, "Antigravity IDE is not running")
            return false
        }

        let newAccount = ClaudeAccount(name: "Antigravity", isAntigravity: true)

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Validates that Antigravity IDE is running and can be connected to.
    /// - Returns: True if Antigravity is running and responding
    /// - Throws: AntigravityTrackerError if the validation fails
    static func validateAntigravityRunning() async throws -> Bool {
        let tracker = AntigravityTrackerService()
        _ = try await tracker.fetchUsage()
        return true
    }

    // MARK: - OpenAI Account Management

    /// Adds a new OpenAI API account with an Admin API key.
    /// - Parameter adminApiKey: The OpenAI Admin API key (sk-admin-xxx format)
    /// - Returns: True if account was added, false if duplicate exists or key is invalid
    @discardableResult
    func addOpenAIAccount(adminApiKey: String) -> Bool {
        // Check for existing OpenAI account with same key
        if sessions.contains(where: { $0.account.type == .openai && $0.account.openaiAdminApiKey == adminApiKey }) {
            Log.warning(Log.Category.app, "OpenAI account with this key already exists")
            return false
        }

        // Validate key format
        let tracker = OpenAITrackerService()
        guard tracker.isValidAdminKeyFormat(adminApiKey) else {
            Log.warning(Log.Category.app, "Invalid OpenAI Admin API key format")
            return false
        }

        let newAccount = ClaudeAccount(name: "OpenAI API", openaiAdminApiKey: adminApiKey)

        // Save API key to Keychain
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save OpenAI API key to Keychain - credentials may not persist")
        }

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Validates an OpenAI Admin API key by attempting to fetch usage data.
    /// - Parameter adminApiKey: The Admin API key to validate
    /// - Returns: True if the key is valid (successful fetch)
    /// - Throws: OpenAITrackerError if the validation fails
    static func validateOpenAIAdminKey(_ adminApiKey: String) async throws -> Bool {
        let tracker = OpenAITrackerService()
        _ = try await tracker.fetchUsage(adminApiKey: adminApiKey)
        return true
    }

    // MARK: - Codex Account Management

    /// Adds a new Codex CLI account with an auth token.
    /// - Parameter authToken: The Codex authentication token
    /// - Returns: True if account was added, false if duplicate exists
    @discardableResult
    func addCodexAccount(authToken: String) -> Bool {
        // Check for existing Codex account with same token
        if sessions.contains(where: { $0.account.type == .codex && $0.account.codexAuthToken == authToken }) {
            Log.warning(Log.Category.app, "Codex account with this token already exists")
            return false
        }

        let newAccount = ClaudeAccount(name: "Codex", codexAuthToken: authToken)

        // Save auth token to Keychain
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save Codex auth token to Keychain - credentials may not persist")
        }

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
        return true
    }

    /// Adds a Codex account by auto-detecting credentials from ~/.codex/auth.json.
    /// - Returns: True if account was added, false if detection failed or duplicate exists
    @discardableResult
    func addCodexAccountFromCLI() -> Bool {
        let tracker = CodexTrackerService()

        guard let credentials = tracker.detectCodexCLI() else {
            Log.warning(Log.Category.app, "Codex CLI credentials not found")
            return false
        }

        guard let accessToken = credentials.accessToken else {
            Log.warning(Log.Category.app, "Codex access token not found in credentials")
            return false
        }

        return addCodexAccount(authToken: accessToken)
    }

    /// Validates a Codex auth token by attempting to fetch usage data.
    /// - Parameter authToken: The auth token to validate
    /// - Returns: True if the token is valid (successful fetch)
    /// - Throws: CodexTrackerError if the validation fails
    static func validateCodexToken(_ authToken: String) async throws -> Bool {
        let tracker = CodexTrackerService()
        _ = try await tracker.fetchUsage(authToken: authToken)
        return true
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
        guard let session = sessions.first(where: { $0.account.id == id }) else {
            Log.warning(Log.Category.app, "Cannot remove account: not found \(id)")
            return
        }

        do {
            try session.account.deleteCredentialsFromKeychain()
            Log.info(Log.Category.app, "Deleted credentials for account \(session.account.name)")
        } catch {
            // Log error but proceed with removal to avoid orphaned UI state
            // Keychain items may be cleaned up on app reinstall or manually
            Log.error(Log.Category.app, "Failed to delete credentials for \(id): \(error.localizedDescription)")
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
        let accounts = sessions.map(\.account)
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: accountsKey)
        }
    }

    private func loadAccounts() {
        // First, try to migrate any legacy data from UserDefaults
        migrateCredentialsFromUserDefaults()

        guard let data = defaults.data(forKey: accountsKey) else {
            Log.info(Log.Category.app, "No saved accounts found")
            return
        }

        do {
            var accounts = try JSONDecoder().decode([ClaudeAccount].self, from: data)
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

            sessions = accounts.map { AccountSession(account: $0) }

            for session in sessions {
                subscribeToSessionChanges(session)
                // Note: startMonitoring() is called separately via startMonitoringAll()
                // to avoid side effects during init
            }
        } catch {
            Log.error(
                Log.Category.app,
                "Failed to decode saved accounts from '\(accountsKey)': \(error.localizedDescription). Data size: \(data.count) bytes"
            )
        }
    }

    /// Migrate credentials from old UserDefaults storage to Keychain (one-time migration)
    /// Only marks migration complete if ALL credentials are successfully migrated.
    /// If any migration fails, it will be retried on subsequent launches.
    /// After successful migration, legacy credential fields are cleared from UserDefaults for security.
    private func migrateCredentialsFromUserDefaults() {
        let migrationKey = Constants.UserDefaultsKeys.keychainMigrationComplete
        guard !defaults.bool(forKey: migrationKey) else { return }

        Log.info(Log.Category.keychain, "Starting migration from UserDefaults to Keychain...")

        var allMigrationsSucceeded = true

        // Try to load old-format accounts that included credentials
        guard let data = defaults.data(forKey: accountsKey) else { return }

        // Decode with a temporary struct that includes the old fields
        // Preserves all fields from the original ClaudeAccount for complete migration
        struct LegacyAccount: Codable {
            var id: UUID
            var name: String
            var type: AccountType?
            var usageData: UsageData?
            var cookieProps: [[String: String]]?
            var apiToken: String?
            var oauthToken: String?
            var oauthRefreshToken: String?
            var geminiAccessToken: String?
            var geminiRefreshToken: String?
            var geminiIdToken: String?
            var geminiTokenExpiry: Double? // TimeInterval
            var openaiAdminApiKey: String?
            var codexAuthToken: String?
        }

        do {
            var legacyAccounts = try JSONDecoder().decode([LegacyAccount].self, from: data)
            for legacy in legacyAccounts {
                // Migrate cookies if present
                if let cookies = legacy.cookieProps, !cookies.isEmpty {
                    do {
                        try KeychainService.save(
                            cookies, forKey: KeychainService.cookiesKey(for: legacy.id)
                        )
                        Log.info(
                            Log.Category.keychain, "Migrated cookies for account \(legacy.id)"
                        )
                    } catch {
                        Log.error(
                            Log.Category.keychain,
                            "Failed to migrate cookies for \(legacy.id): \(error)"
                        )
                        allMigrationsSucceeded = false
                    }
                }

                // Migrate API token if present
                if let token = legacy.apiToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.apiTokenKey(for: legacy.id)
                        )
                        Log.info(
                            Log.Category.keychain, "Migrated API token for account \(legacy.id)"
                        )
                    } catch {
                        Log.error(
                            Log.Category.keychain,
                            "Failed to migrate API token for \(legacy.id): \(error)"
                        )
                        allMigrationsSucceeded = false
                    }
                }

                // Migrate OAuth tokens if present
                if let token = legacy.oauthToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.oauthTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated OAuth token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate OAuth token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                if let token = legacy.oauthRefreshToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.oauthRefreshTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated OAuth refresh token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate OAuth refresh token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                // Migrate Gemini tokens if present
                if let token = legacy.geminiAccessToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.geminiAccessTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated Gemini access token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate Gemini access token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                if let token = legacy.geminiRefreshToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.geminiRefreshTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated Gemini refresh token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate Gemini refresh token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                if let token = legacy.geminiIdToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.geminiIdTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated Gemini ID token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate Gemini ID token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                if let expiry = legacy.geminiTokenExpiry {
                    do {
                        try KeychainService.save(
                            String(expiry), forKey: KeychainService.geminiTokenExpiryKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated Gemini token expiry for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate Gemini token expiry for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                // Migrate OpenAI Admin API key if present
                if let key = legacy.openaiAdminApiKey {
                    do {
                        try KeychainService.save(
                            key, forKey: KeychainService.openaiAdminApiKeyKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated OpenAI Admin API key for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate OpenAI Admin API key for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }

                // Migrate Codex auth token if present
                if let token = legacy.codexAuthToken {
                    do {
                        try KeychainService.save(
                            token, forKey: KeychainService.codexAuthTokenKey(for: legacy.id)
                        )
                        Log.info(Log.Category.keychain, "Migrated Codex auth token for account \(legacy.id)")
                    } catch {
                        Log.error(Log.Category.keychain, "Failed to migrate Codex auth token for \(legacy.id): \(error)")
                        allMigrationsSucceeded = false
                    }
                }
            }

            // Only mark migration complete and clear legacy data if ALL credentials migrated successfully
            // This allows retry on subsequent launches if Keychain was temporarily unavailable
            if allMigrationsSucceeded {
                // Clear sensitive credential fields from legacy accounts in UserDefaults
                // Keep non-sensitive metadata (id, name, type, usageData) for account loading
                for i in legacyAccounts.indices {
                    legacyAccounts[i].cookieProps = nil
                    legacyAccounts[i].apiToken = nil
                    legacyAccounts[i].oauthToken = nil
                    legacyAccounts[i].oauthRefreshToken = nil
                    legacyAccounts[i].geminiAccessToken = nil
                    legacyAccounts[i].geminiRefreshToken = nil
                    legacyAccounts[i].geminiIdToken = nil
                    legacyAccounts[i].geminiTokenExpiry = nil
                    legacyAccounts[i].openaiAdminApiKey = nil
                    legacyAccounts[i].codexAuthToken = nil
                }

                // Re-save accounts without credential fields
                if let cleanedData = try? JSONEncoder().encode(legacyAccounts) {
                    defaults.set(cleanedData, forKey: accountsKey)
                    Log.info(Log.Category.keychain, "Cleared legacy credentials from UserDefaults")
                }

                defaults.set(true, forKey: migrationKey)
                Log.info(Log.Category.keychain, "Migration complete")
            } else {
                Log.warning(Log.Category.keychain, "Migration incomplete - will retry on next launch")
            }
        } catch {
            // Log non-sensitive diagnostics for decoding failures
            let dataSize = data.count
            Log.error(
                Log.Category.keychain,
                "Failed to decode legacy accounts from '\(accountsKey)': \(error.localizedDescription). " +
                    "Data size: \(dataSize) bytes"
            )
        }
    }

    /// Computes the current menu bar icon state based on account statuses.
    var menuBarIconState: MenuBarIconState {
        guard !sessions.isEmpty else { return .noAccounts }

        if sessions.contains(where: \.isFetching) {
            return .loading
        }

        let accountsWithData = sessions.compactMap(\.account.usageData)

        if accountsWithData.isEmpty {
            return .noData
        }

        let maxSessionPercentage = accountsWithData.map(\.sessionPercentage).max() ?? 0

        let hasReadyState = accountsWithData.contains {
            $0.sessionPercentage == 0 && $0.sessionReset == Constants.Status.ready
        }

        if hasReadyState, maxSessionPercentage == 0 {
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

        // Clear in-memory sessions and reset observable state
        sessions.removeAll()
        nextRefresh = Date()
        iconRefreshTrigger = UUID()

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
        // Note: defaults.synchronize() is deprecated and unnecessary on modern macOS

        Log.info(Log.Category.app, "All app data has been reset")
    }
}
