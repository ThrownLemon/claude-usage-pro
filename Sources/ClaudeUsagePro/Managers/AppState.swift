import Foundation
import SwiftUI

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
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save credentials to Keychain for new account - credentials may not persist")
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
            Log.warning(Log.Category.app, "Failed to save re-auth credentials to Keychain - credentials may not persist")
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
        if !newAccount.saveCredentialsToKeychain() {
            Log.warning(Log.Category.app, "Failed to save GLM API token to Keychain - credentials may not persist")
        }

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
    /// - Note: Explicitly marked @MainActor to ensure callers resume on main thread after await
    @MainActor
    static func validateGLMToken(_ token: String) async throws -> Bool {
        let tracker = GLMTrackerService()
        let info = try await tracker.fetchGLMUsage(apiToken: token)
        // If we get here without throwing, the token is valid
        return info.sessionLimit > 0 || info.monthlyLimit > 0
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
    /// Note: Legacy UserDefaults data is intentionally preserved for manual recovery.
    private func migrateCredentialsFromUserDefaults() {
        // Note: migrationKey tracks whether migration has completed successfully.
        // Legacy data in accountsKey is intentionally NOT deleted to allow manual recovery.
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
                // Log detailed diagnostics for decoding failures to help diagnose format mismatches
                let dataSize = data.count
                let dataPreview = data.prefix(100).base64EncodedString()
                Log.error(
                    Log.Category.keychain,
                    "Failed to decode legacy accounts from '\(accountsKey)': \(error.localizedDescription). " +
                    "Data size: \(dataSize) bytes, preview (base64): \(dataPreview)..."
                )
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
            $0.sessionPercentage == 0 && $0.sessionReset == Constants.Status.ready
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
        // Note: defaults.synchronize() is deprecated and unnecessary on modern macOS

        Log.info(Log.Category.app, "All app data has been reset")
    }
}
