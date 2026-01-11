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
    /// Creates and registers a new Claude account using the provided HTTP cookies.
    /// - Parameters:
    ///   - cookies: HTTP cookies used as authentication credentials for the new account; these are saved to the keychain.
    /// This function persists the account list, appends a monitoring session for the new account, and starts that session's monitoring.
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
    /// Adds a Claude OAuth account, persists its credentials to the keychain, and begins monitoring the new session.
    /// - Parameters:
    ///   - oauthToken: The OAuth access token for the account.
    ///   - refreshToken: An optional OAuth refresh token.
    /// - Returns: `true` if the account was added and monitoring started, `false` if an existing account with the same OAuth token prevented addition.
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
    /// Update stored OAuth credentials for the specified account, persist them to the keychain, trigger an immediate refresh for that account, and clear any outstanding reauthentication notification.
    /// 
    /// If no account with `accountId` exists, the function does nothing.
    /// - Parameters:
    ///   - accountId: The UUID of the account whose credentials should be updated.
    ///   - oauthToken: The new OAuth access token to store for the account.
    ///   - refreshToken: An optional OAuth refresh token to store for the account.
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

    /// Checks whether any registered account uses the given OAuth token.
    /// - Parameters:
    ///   - token: The OAuth token to look for among stored account sessions.
    /// - Returns: `true` if a session's account has the provided OAuth token, `false` otherwise.
    func hasOAuthAccount(token: String) -> Bool {
        sessions.contains { $0.account.oauthToken == token }
    }

    /// Adds a new "Cursor Monitoring" account, persists it, subscribes to its session changes, and starts monitoring.
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
    /// Adds a GLM Coding Plan account using the provided API token and begins monitoring it.
    /// 
    /// Creates a new account with the given token, attempts to persist the token to the Keychain (logs a warning if saving fails), stores a monitoring session, saves account state, subscribes to session changes, and starts monitoring.
    /// - Parameter apiToken: The GLM API token to associate with the new account; persisted to the Keychain for future use.
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
    /// Checks whether a GLM API token is valid by fetching its usage information.
    /// - Parameter token: The GLM API token to validate.
    /// - Returns: `true` if the token corresponds to an account with a session limit greater than 0 or a monthly limit greater than 0, `false` otherwise.
    /// - Throws: Any error thrown while fetching usage information (for example network or authentication errors).
    @MainActor
    static func validateGLMToken(_ token: String) async throws -> Bool {
        let tracker = GLMTrackerService()
        let info = try await tracker.fetchGLMUsage(apiToken: token)
        // If we get here without throwing, the token is valid
        return info.sessionLimit > 0 || info.monthlyLimit > 0
    }

    /// Registers a session callback that updates the app state's `nextRefresh` to now plus the configured refresh interval whenever the session signals a refresh tick.
    /// - Parameter session: The `AccountSession` whose `onRefreshTick` will trigger updating `nextRefresh`.
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
    /// Removes the account with the given identifier, deletes its stored credentials, and persists the updated account list.
    /// 
    /// Attempts to delete the account's credentials from the keychain; any keychain deletion failure is logged but does not prevent removing the account from in-memory state and persisted storage.
    /// - Parameter id: The UUID of the account to remove.
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

    /// Triggers an immediate refresh for every account session and updates the scheduled next refresh time.
    /// 
    /// The method instructs each active session to fetch data now and sets `nextRefresh` to the current time plus the configured refresh interval.
    func refreshAll() {
        let nextInterval = refreshIntervalSeconds()
        Log.debug(Log.Category.appState, "Refreshing all accounts... Next in \(Int(nextInterval))s")
        for session in sessions {
            session.fetchNow()
        }
        nextRefresh = Date().addingTimeInterval(nextInterval)
    }

    /// Reschedules each account session's refresh timer and updates the nextRefresh timestamp.
    /// 
    /// Updates `nextRefresh` to the current time plus the configured refresh interval.
    func rescheduleAllSessions() {
        for session in sessions {
            session.scheduleRefreshTimer()
        }
        nextRefresh = Date().addingTimeInterval(refreshIntervalSeconds())
    }

    /// Returns the configured refresh interval in seconds.
    /// Returns the configured refresh interval in seconds from user defaults, or the default interval if none is set or the stored value is not greater than zero.
    /// - Returns: The refresh interval in seconds from settings, or `Constants.Timeouts.defaultRefreshInterval` when the stored value is missing or invalid.
    func refreshIntervalSeconds() -> TimeInterval {
        let interval = defaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        return interval > 0 ? interval : Constants.Timeouts.defaultRefreshInterval
    }

    /// Persists the current accounts (extracted from `sessions`) to UserDefaults by JSON-encoding them and saving under `accountsKey`.
    /// 
    /// If encoding fails the method returns without modifying UserDefaults.
    private func saveAccounts() {
        let accounts = sessions.map { $0.account }
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: accountsKey)
        }
    }

    /// Loads persisted accounts into memory and starts their monitoring lifecycle.
    /// 
    /// This performs a one-time migration of legacy credential storage, reads saved `ClaudeAccount`
    /// objects from UserDefaults, clears any in-memory usage data, restores credentials from the
    /// keychain, and creates `AccountSession` instances for each account. Each session is subscribed
    /// for state changes and starts its monitoring/fetch cycle. If no saved accounts are found,
    /// a log entry is written and no sessions are created.
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
    /// Migrate legacy credential data stored in UserDefaults into the Keychain.
    /// 
    /// If migration has already been marked complete, this method returns immediately. It reads legacy account entries from the persisted accounts key and transfers any embedded cookies and API tokens into Keychain entries keyed by each account's identifier. The original UserDefaults data is not removed to allow manual recovery. The migration-complete flag is set only when all credential migrations succeed; otherwise the migration is left incomplete so it can be retried on a subsequent launch. Logs success and failure details.
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
    /// Resets the application to a clean state by stopping session monitoring and removing all stored credentials and settings.
    /// 
    /// Stops all active AccountSession monitoring, clears in-memory sessions, deletes all credentials from the Keychain, and removes the app's known UserDefaults keys (accounts, migration flag, refresh/settings, and notification preferences).
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