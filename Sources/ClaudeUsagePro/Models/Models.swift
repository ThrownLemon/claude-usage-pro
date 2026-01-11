import Foundation
import WebKit

/// Types of accounts supported by the application.
enum AccountType: String, Codable {
    /// Claude.ai account
    case claude
    /// Cursor IDE account
    case cursor
    /// GLM Coding Plan account
    case glm
}

/// Usage statistics for an account, normalized across different provider types.
struct UsageData: Hashable, Codable {
    var sessionPercentage: Double
    var sessionReset: String
    var sessionResetDisplay: String
    var weeklyPercentage: Double
    var weeklyReset: String
    var weeklyResetDisplay: String
    var tier: String
    var email: String?

    var fullName: String?
    var orgName: String?
    var planType: String?

    var cursorUsed: Int?
    var cursorLimit: Int?

    // GLM-specific fields
    var glmSessionUsed: Double?
    var glmSessionLimit: Double?
    var glmMonthlyUsed: Double?
    var glmMonthlyLimit: Double?

    // OAuth API extended fields (model-specific usage)
    /// Opus model 7-day usage percentage (0.0-1.0), nil if not available
    var opusPercentage: Double?
    /// Opus model reset time display string
    var opusReset: String?
    /// Sonnet model 7-day usage percentage (0.0-1.0), nil if not available
    var sonnetPercentage: Double?
    /// Sonnet model reset time display string
    var sonnetReset: String?

    /// Formats a session reset string with "Resets in" prefix for consistency with GLM display.
    /// - Parameter sessionReset: The raw reset string (e.g., "3h 45m" or "Ready")
    /// - Returns: Formatted display string (e.g., "Resets in 3h 45m" or "Ready")
    static func formatSessionResetDisplay(_ sessionReset: String) -> String {
        if sessionReset == Constants.Status.ready || sessionReset.isEmpty {
            return sessionReset
        }
        return "\(Constants.Status.resetsInPrefix) \(sessionReset)"
    }
}

/// Represents a user account with credentials and usage data.
/// Credentials are stored in Keychain, not UserDefaults.
struct ClaudeAccount: Identifiable, Hashable, Codable {
    /// Unique identifier for this account
    var id = UUID()
    /// Display name for the account
    var name: String
    /// Type of account (claude, cursor, or glm)
    var type: AccountType = .claude
    /// Current usage statistics, if fetched
    var usageData: UsageData?

    // Sensitive data - stored in Keychain, not UserDefaults
    // These are transient properties that load from Keychain on-demand
    /// Cookie properties for Claude accounts (loaded from Keychain)
    var cookieProps: [[String: String]] = []
    /// API token for GLM accounts (loaded from Keychain)
    var apiToken: String?
    /// OAuth token for Claude accounts using the official Anthropic API (loaded from Keychain)
    var oauthToken: String?
    /// OAuth refresh token for obtaining new access tokens (loaded from Keychain)
    var oauthRefreshToken: String?

    // Transient state (not persisted)
    /// Indicates the account needs re-authentication (token expired and refresh failed)
    var needsReauth: Bool = false

    // CodingKeys excludes sensitive data (cookieProps, apiToken)
    // These are stored separately in Keychain
    enum CodingKeys: String, CodingKey {
        case id, name, type, usageData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(AccountType.self, forKey: .type) ?? .claude
        usageData = try container.decodeIfPresent(UsageData.self, forKey: .usageData)
        // Sensitive data loaded separately from Keychain
        cookieProps = []
        apiToken = nil
        oauthToken = nil
        oauthRefreshToken = nil
        needsReauth = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(usageData, forKey: .usageData)
        // Sensitive data (cookieProps, apiToken) saved separately to Keychain
    }

    // MARK: - Keychain Integration

    /// Save sensitive credentials to Keychain.
    /// Errors are logged as warnings. Keychain failures are rare but may occur due to:
    /// - Keychain access restrictions
    /// - Disk full
    /// - System permissions issues
    /// - Returns: true if all credentials were saved successfully, false on any error
    /// - Note: Failures are non-fatal; credentials will be retried on next app launch or can be re-entered by user
    @discardableResult
    func saveCredentialsToKeychain() -> Bool {
        var savedCookies = false
        var savedApiToken = false
        var savedOAuthToken = false

        // Save cookies
        do {
            if !cookieProps.isEmpty {
                try KeychainService.save(cookieProps, forKey: KeychainService.cookiesKey(for: id))
                savedCookies = true
                Log.debug(Log.Category.keychain, "Saved \(cookieProps.count) cookies for account \(id)")
            }
        } catch {
            Log.warning(Log.Category.keychain, "⚠️ Failed to save cookies for account \(id): \(error.localizedDescription)")
            return false
        }

        // Save API token
        do {
            if let token = apiToken {
                try KeychainService.save(token, forKey: KeychainService.apiTokenKey(for: id))
                savedApiToken = true
                Log.debug(Log.Category.keychain, "Saved API token for account \(id)")
            }
        } catch {
            Log.warning(Log.Category.keychain, "⚠️ Failed to save API token for account \(id): \(error.localizedDescription)")
            // Rollback cookies if they were saved
            if savedCookies {
                try? KeychainService.delete(forKey: KeychainService.cookiesKey(for: id))
            }
            return false
        }

        // Save OAuth token
        do {
            if let token = oauthToken {
                try KeychainService.save(token, forKey: KeychainService.oauthTokenKey(for: id))
                savedOAuthToken = true
                Log.debug(Log.Category.keychain, "Saved OAuth token for account \(id)")
            }
        } catch {
            Log.warning(Log.Category.keychain, "⚠️ Failed to save OAuth token for account \(id): \(error.localizedDescription)")
            // Rollback previous saves
            if savedCookies {
                try? KeychainService.delete(forKey: KeychainService.cookiesKey(for: id))
            }
            if savedApiToken {
                try? KeychainService.delete(forKey: KeychainService.apiTokenKey(for: id))
            }
            return false
        }

        // Save OAuth refresh token
        do {
            if let refreshToken = oauthRefreshToken {
                try KeychainService.save(refreshToken, forKey: KeychainService.oauthRefreshTokenKey(for: id))
                Log.debug(Log.Category.keychain, "Saved OAuth refresh token for account \(id)")
            }
        } catch {
            Log.warning(Log.Category.keychain, "⚠️ Failed to save OAuth refresh token for account \(id): \(error.localizedDescription)")
            // Rollback all previous saves
            if savedCookies {
                try? KeychainService.delete(forKey: KeychainService.cookiesKey(for: id))
            }
            if savedApiToken {
                try? KeychainService.delete(forKey: KeychainService.apiTokenKey(for: id))
            }
            if savedOAuthToken {
                try? KeychainService.delete(forKey: KeychainService.oauthTokenKey(for: id))
            }
            return false
        }

        return true
    }

    /// Load sensitive credentials from Keychain
    mutating func loadCredentialsFromKeychain() {
        Log.debug(Log.Category.keychain, "Loading credentials for account \(id) (\(name))")
        do {
            if let cookies: [[String: String]] = try KeychainService.load(forKey: KeychainService.cookiesKey(for: id)) {
                cookieProps = cookies
                Log.debug(Log.Category.keychain, "  Loaded \(cookies.count) cookies")
            }
            if let token = try KeychainService.loadString(forKey: KeychainService.apiTokenKey(for: id)) {
                apiToken = token
                Log.debug(Log.Category.keychain, "  Loaded API token")
            }
            if let token = try KeychainService.loadString(forKey: KeychainService.oauthTokenKey(for: id)) {
                oauthToken = token
                Log.debug(Log.Category.keychain, "  Loaded OAuth token (prefix: \(token.prefix(8))...)")
            }
            if let refreshToken = try KeychainService.loadString(forKey: KeychainService.oauthRefreshTokenKey(for: id)) {
                oauthRefreshToken = refreshToken
                Log.debug(Log.Category.keychain, "  Loaded OAuth refresh token")
            }
            if cookieProps.isEmpty && apiToken == nil && oauthToken == nil {
                Log.warning(Log.Category.keychain, "  No credentials found in keychain for account \(id)")
            }
        } catch {
            Log.error(Log.Category.keychain, "Failed to load credentials for \(id): \(error)")
        }
    }

    /// Delete credentials from Keychain (call when removing account).
    /// - Throws: KeychainError if deletion fails for reasons other than item not found
    func deleteCredentialsFromKeychain() throws {
        try KeychainService.delete(forKey: KeychainService.cookiesKey(for: id))
        try KeychainService.delete(forKey: KeychainService.apiTokenKey(for: id))
        try KeychainService.delete(forKey: KeychainService.oauthTokenKey(for: id))
        try KeychainService.delete(forKey: KeychainService.oauthRefreshTokenKey(for: id))
    }
    
    /// Display string for the account's tier/plan
    var limitDetails: String {
        return usageData?.tier ?? Constants.Status.fetching
    }

    /// Converts stored cookie properties back to HTTPCookie objects
    var cookies: [HTTPCookie] {
        HTTPCookie.fromCodable(cookieProps)
    }
    
    /// Creates a new Claude or Cursor account with cookies.
    /// - Parameters:
    ///   - name: Display name for the account
    ///   - cookies: Authentication cookies
    ///   - type: Account type (defaults to .claude)
    init(name: String, cookies: [HTTPCookie], type: AccountType = .claude) {
        self.name = name
        self.type = type
        self.cookieProps = cookies.compactMap { $0.toCodable() }
    }

    /// Creates an account with a specific ID, cookies, and optional usage data.
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Display name
    ///   - cookies: Authentication cookies
    ///   - usageData: Pre-existing usage data
    ///   - type: Account type (defaults to .claude)
    init(id: UUID, name: String, cookies: [HTTPCookie], usageData: UsageData?, type: AccountType = .claude) {
        self.id = id
        self.name = name
        self.type = type
        self.cookieProps = cookies.compactMap { $0.toCodable() }
        self.usageData = usageData
    }

    /// Creates a new GLM account with an API token.
    /// - Parameters:
    ///   - name: Display name for the account
    ///   - apiToken: GLM API token
    init(name: String, apiToken: String) {
        self.name = name
        self.type = .glm
        self.apiToken = apiToken
        self.cookieProps = []
    }

    /// Creates a GLM account with a specific ID, token, and optional usage data.
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Display name
    ///   - apiToken: GLM API token
    ///   - usageData: Pre-existing usage data
    init(id: UUID, name: String, apiToken: String, usageData: UsageData?) {
        self.id = id
        self.name = name
        self.type = .glm
        self.apiToken = apiToken
        self.usageData = usageData
        self.cookieProps = []
    }

    /// Creates a new Claude account with an OAuth token (uses official Anthropic API).
    /// - Parameters:
    ///   - name: Display name for the account
    ///   - oauthToken: OAuth token from Claude Code or manual entry
    ///   - refreshToken: Optional refresh token for obtaining new access tokens
    init(name: String, oauthToken: String, refreshToken: String? = nil) {
        self.name = name
        self.type = .claude
        self.oauthToken = oauthToken
        self.oauthRefreshToken = refreshToken
        self.cookieProps = []
    }

    /// Creates a Claude OAuth account with a specific ID, token, and optional usage data.
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - name: Display name
    ///   - oauthToken: OAuth token
    ///   - refreshToken: Optional refresh token for obtaining new access tokens
    ///   - usageData: Pre-existing usage data
    init(id: UUID, name: String, oauthToken: String, refreshToken: String? = nil, usageData: UsageData?) {
        self.id = id
        self.name = name
        self.type = .claude
        self.oauthToken = oauthToken
        self.oauthRefreshToken = refreshToken
        self.usageData = usageData
        self.cookieProps = []
    }

    // MARK: - Convenience Properties

    /// Whether this account uses OAuth authentication (preferred method)
    var usesOAuth: Bool {
        oauthToken?.isEmpty == false
    }

    /// Whether this account has any valid credentials
    var hasCredentials: Bool {
        switch type {
        case .claude:
            return usesOAuth || !cookieProps.isEmpty
        case .cursor:
            return !cookieProps.isEmpty
        case .glm:
            return apiToken?.isEmpty == false
        }
    }

    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: ClaudeAccount, rhs: ClaudeAccount) -> Bool {
        lhs.id == rhs.id
    }
}
