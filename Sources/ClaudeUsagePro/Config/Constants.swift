import Foundation

/// Centralized constants for the application
enum Constants {

    // MARK: - URLs

    /// URL constants for API endpoints
    enum URLs {
        /// Claude.ai login page
        static let claudeLogin: URL = {
            guard let url = URL(string: "https://claude.ai/login") else {
                fatalError("Invalid URL constant: https://claude.ai/login")
            }
            return url
        }()

        /// Claude.ai chats page (used to detect successful login)
        static let claudeChats: URL = {
            guard let url = URL(string: "https://claude.ai/chats") else {
                fatalError("Invalid URL constant: https://claude.ai/chats")
            }
            return url
        }()

        /// Cursor API base URL
        static let cursorAPI: URL = {
            guard let url = URL(string: "https://api2.cursor.sh") else {
                fatalError("Invalid URL constant: https://api2.cursor.sh")
            }
            return url
        }()
    }

    // MARK: - UserDefaults Keys

    /// Keys for UserDefaults storage
    enum UserDefaultsKeys {
        /// Refresh interval in seconds
        static let refreshInterval = "refreshInterval"
        /// Whether to auto-wake sessions when ready
        static let autoWakeUp = "autoWakeUp"
        /// Encoded array of saved accounts
        static let savedAccounts = "savedAccounts"
        /// Whether debug logging is enabled
        static let debugModeEnabled = "debugModeEnabled"
        /// Whether keychain migration has been completed
        static let keychainMigrationComplete = "keychainMigrationComplete"
        /// Selected app theme
        static let selectedTheme = "selectedTheme"
        /// Color scheme mode (light/dark/system)
        static let colorSchemeMode = "colorSchemeMode"
    }

    // MARK: - Timeouts

    /// Timeout constants for various operations
    enum Timeouts {
        /// Timeout for ping operations (seconds)
        static let pingTimeout: TimeInterval = 15
        /// Default refresh interval (seconds)
        static let defaultRefreshInterval: TimeInterval = 300
        /// Delay after ping before fetching data (seconds)
        static let pingRefreshDelay: TimeInterval = 2.0
        /// Network request timeout (seconds)
        static let networkRequestTimeout: TimeInterval = 30
    }

    // MARK: - Notifications

    /// Constants for notification behavior
    enum Notifications {
        /// Cooldown period between same notification type (seconds)
        static let cooldownInterval: TimeInterval = 300 // 5 minutes
    }

    // MARK: - Usage Thresholds

    /// Default threshold values for gauge color transitions.
    /// User-configurable thresholds are stored in NotificationSettings.
    enum UsageThresholds {
        /// Low usage threshold (gauge transitions from green to yellow)
        static let low: Double = 0.50
        /// Medium usage threshold (default for user-configurable lower alert)
        static let medium: Double = 0.75
        /// High usage threshold (default for user-configurable higher alert)
        static let high: Double = 0.90
    }

    // MARK: - OAuth Configuration

    /// OAuth constants for Anthropic/Claude authentication
    enum OAuth {
        /// The OAuth client ID for Claude
        static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        /// Authorization URL
        static let authURL = "https://claude.ai/oauth/authorize"
        /// Token exchange endpoint
        static let tokenURL = "https://console.anthropic.com/v1/oauth/token"
        /// The redirect URI Anthropic expects
        static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
        /// OAuth scopes to request
        static let scopes = "org:create_api_key user:profile user:inference"
    }

    // MARK: - Anthropic API

    /// Constants for the Anthropic API
    enum AnthropicAPI {
        /// Base URL for API requests
        static let baseURL = "https://api.anthropic.com"
        /// Path to usage endpoint
        static let usagePath = "/api/oauth/usage"
        /// Path to profile endpoint
        static let profilePath = "/api/oauth/profile"
        /// Beta header value for OAuth features
        static let betaHeader = "oauth-2025-04-20"
        /// User agent string for API requests
        static let userAgent = "claude-code/2.0.32"
        /// Maximum number of retry attempts
        static let maxRetries = 3
        /// Base backoff duration for retries (seconds)
        static let baseBackoffSeconds: Double = 1.0
        /// Backoff duration for rate limit errors (seconds)
        static let rateLimitBackoffSeconds: Double = 5.0
    }

    // MARK: - GLM

    /// Constants specific to GLM Coding Plan accounts
    enum GLM {
        /// Rolling window for session limits (hours)
        static let sessionWindowHours: Double = 5.0
        /// Display label for the session window
        static let sessionWindowLabel = "Session usage"
    }

    // MARK: - Status Strings

    /// Common status string constants used throughout the app
    enum Status {
        /// Status indicating a session is ready to use (no active usage)
        static let ready = "Ready"
        /// Prefix for reset time display
        static let resetsInPrefix = "Resets in"
        /// Status when data is being fetched
        static let fetching = "Fetching..."
        /// Unknown status placeholder
        static let unknown = "Unknown"
    }

    // MARK: - Window Dimensions

    /// Window size constants
    enum WindowSize {
        /// Main window width
        static let width: CGFloat = 405
        /// Main window height
        static let height: CGFloat = 660
    }

    // MARK: - Bundle Identifiers

    /// Bundle identifier constants
    enum BundleIdentifiers {
        /// Fallback identifier if Bundle.main.bundleIdentifier is nil
        static let fallback = "com.claudeusagepro"

        /// Current app's bundle identifier
        static var current: String {
            Bundle.main.bundleIdentifier ?? fallback
        }
    }
}
