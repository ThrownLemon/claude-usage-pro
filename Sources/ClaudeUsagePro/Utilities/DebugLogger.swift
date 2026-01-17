import Foundation
import os

/// Centralized logging system using Apple's unified logging (os.Logger).
///
/// Usage:
///   Log.debug("TrackerService", "Starting fetch...")
///   Log.error("AuthManager", "Login failed: \(error)")
///
/// View logs in Console.app with:
///   - Filter by subsystem: "com.claudeusagepro"
///   - Filter by category: "TrackerService", "AuthManager", etc.
///
/// Log levels (color-coded in Console.app):
///   - debug: Gray (only shown when debug mode enabled)
///   - info: Default
///   - error: Yellow
///   - fault: Red (for critical failures)
///
enum Log {
    // MARK: - Configuration

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.claudeusagepro"

    /// UserDefaults key for debug mode toggle
    static let debugModeKey = Constants.UserDefaultsKeys.debugModeEnabled

    /// Check if debug logging is enabled
    static var isDebugEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: debugModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: debugModeKey) }
    }

    // MARK: - Logger Cache

    /// Cache of loggers by category to avoid recreating them
    private static var loggers: [String: Logger] = [:]
    private static let lock = NSLock()

    /// Get or create a logger for a category
    private static func logger(for category: String) -> Logger {
        lock.lock()
        defer { lock.unlock() }

        if let existing = loggers[category] {
            return existing
        }

        let newLogger = Logger(subsystem: subsystem, category: category)
        loggers[category] = newLogger
        return newLogger
    }

    // MARK: - Known Categories

    /// Standard category names for consistency
    enum Category {
        static let app = "App"
        static let appState = "AppState"
        static let auth = "AuthManager"
        static let tracker = "TrackerService"
        static let glmTracker = "GLMTracker"
        static let cursorTracker = "CursorTracker"
        static let session = "AccountSession"
        static let notifications = "Notifications"
        static let settings = "Settings"
        static let api = "ClaudeAPI"
        static let keychain = "Keychain"
        static let usageStats = "UsageStats"
        static let cache = "Cache"
    }

    // MARK: - Credential Sanitization

    /// Sanitize a credential for safe logging.
    /// Shows only the last 4 characters to aid debugging without exposing the full token.
    /// - Parameter credential: The credential string to sanitize
    /// - Returns: A sanitized string showing only the suffix (e.g., "****abc1")
    static func sanitize(_ credential: String?) -> String {
        guard let credential, !credential.isEmpty else {
            return "<none>"
        }
        let suffix = String(credential.suffix(4))
        return "****\(suffix)"
    }

    /// Sanitize a credential showing its length and last 4 characters.
    /// - Parameter credential: The credential string to sanitize
    /// - Returns: A sanitized string with length info (e.g., "[len:45]****abc1")
    static func sanitizeWithLength(_ credential: String?) -> String {
        guard let credential, !credential.isEmpty else {
            return "<none>"
        }
        let suffix = String(credential.suffix(4))
        return "[len:\(credential.count)]****\(suffix)"
    }

    // MARK: - Logging Methods

    /// Log debug message (only when debug mode is enabled)
    /// - Parameters:
    ///   - category: Source category (e.g., "TrackerService")
    ///   - message: Message to log (redacted in release builds to protect sensitive data)
    static func debug(_ category: String, _ message: String) {
        guard isDebugEnabled else { return }
        logger(for: category).debug("[\(category, privacy: .public)] \(message, privacy: .private)")
        printToTerminal("🔍 [\(category)] \(message)")
    }

    /// Log informational message
    /// - Parameters:
    ///   - category: Source category
    ///   - message: Message to log (redacted in release builds to protect sensitive data)
    static func info(_ category: String, _ message: String) {
        logger(for: category).info("[\(category, privacy: .public)] \(message, privacy: .private)")
        printToTerminal("ℹ️ [\(category)] \(message)")
    }

    /// Log warning message
    /// - Parameters:
    ///   - category: Source category
    ///   - message: Message to log (redacted in release builds to protect sensitive data)
    static func warning(_ category: String, _ message: String) {
        logger(for: category).warning("[\(category, privacy: .public)] ⚠️ \(message, privacy: .private)")
        printToTerminal("⚠️ [\(category)] \(message)")
    }

    /// Log error message
    /// - Parameters:
    ///   - category: Source category
    ///   - message: Message to log (redacted in release builds to protect sensitive data)
    static func error(_ category: String, _ message: String) {
        logger(for: category).error("[\(category, privacy: .public)] ❌ \(message, privacy: .private)")
        printToTerminal("❌ [\(category)] \(message)")
    }

    /// Print to terminal (stderr) when running from command line
    private static func printToTerminal(_ message: String) {
        #if DEBUG
            fputs("\(message)\n", stderr)
        #endif
    }

    /// Log critical fault (use sparingly - for unrecoverable errors)
    /// - Parameters:
    ///   - category: Source category
    ///   - message: Message to log (redacted in release builds to protect sensitive data)
    static func fault(_ category: String, _ message: String) {
        logger(for: category).fault("[\(category, privacy: .public)] 🔴 \(message, privacy: .private)")
    }

    // MARK: - Convenience Methods

    /// Toggle debug mode on/off
    /// - Returns: New debug mode state
    @discardableResult
    static func toggleDebugMode() -> Bool {
        isDebugEnabled.toggle()
        let state = isDebugEnabled ? "ENABLED" : "DISABLED"
        // Always log this regardless of debug state
        logger(for: Category.app).notice("Debug mode \(state, privacy: .public)")
        return isDebugEnabled
    }

    // MARK: - Formatted Provider Stats

    /// Log formatted usage stats for a provider account
    /// - Parameters:
    ///   - accountName: Display name of the account
    ///   - accountType: Type of account (claude, cursor, glm)
    ///   - usageData: The usage data to format
    static func providerStats(accountName: String, accountType: AccountType, usageData: UsageData) {
        let log = logger(for: Category.usageStats)

        let icon: String
        let providerName: String

        switch accountType {
        case .claude:
            icon = "✨"
            providerName = "CLAUDE"
        case .cursor:
            icon = "🖥️"
            providerName = "CURSOR"
        case .glm:
            icon = "🤖"
            providerName = "GLM"
        case .gemini:
            icon = "💫"
            providerName = "GEMINI"
        case .antigravity:
            icon = "⚛️"
            providerName = "ANTIGRAVITY"
        case .openai:
            icon = "🧠"
            providerName = "OPENAI"
        case .codex:
            icon = "💻"
            providerName = "CODEX"
        }

        let sessionPct = Int(usageData.sessionPercentage * 100)
        let weeklyPct = Int(usageData.weeklyPercentage * 100)

        // Build the formatted output with fixed-width box (64 inner chars)
        let boxWidth = 64
        let headerContent = " \(icon) \(providerName) │ \(accountName)"
        // Truncate if too long, then pad to fixed width
        let truncatedHeader = headerContent.count > boxWidth
            ? String(headerContent.prefix(boxWidth - 1)) + "…"
            : headerContent
        let paddedHeader = truncatedHeader.padding(toLength: boxWidth, withPad: " ", startingAt: 0)

        var output = """

        ╔════════════════════════════════════════════════════════════════╗
        ║\(paddedHeader)║
        ╠════════════════════════════════════════════════════════════════╣
        """

        switch accountType {
        case .claude:
            let tierDisplay = usageData.planType?.replacingOccurrences(of: "_", with: " ").capitalized ?? usageData.tier
            output += """

            ║ 📊 Session:  \(sessionPct)% │ Reset: \(usageData.sessionResetDisplay)
            ║ 📈 Weekly:   \(weeklyPct)% │ Reset: \(usageData.weeklyResetDisplay)
            ║ 👤 Tier:     \(tierDisplay)
            """
            if usageData.email != nil {
                output += "\n║ 📧 Email:    [redacted]"
            }

        case .cursor:
            let used = usageData.cursorUsed ?? 0
            let limit = usageData.cursorLimit ?? 0
            output += """

            ║ 📊 Requests: \(used) / \(limit) (\(sessionPct)%)
            ║ 👤 Plan:     \(usageData.planType ?? "Pro")
            """
            if usageData.email != nil {
                output += "\n║ 📧 Email:    [redacted]"
            }

        case .glm:
            let sessionUsed = usageData.glmSessionUsed ?? 0
            let sessionLimit = usageData.glmSessionLimit ?? 0
            let monthlyUsed = usageData.glmMonthlyUsed ?? 0
            let monthlyLimit = usageData.glmMonthlyLimit ?? 0
            output += """

            ║ ⏱️ Session:  \(String(format: "%.0f", sessionUsed)) / \(String(
                format: "%.0f",
                sessionLimit
            )) tokens (\(sessionPct)%)
            ║ 📅 Monthly:  \(String(format: "%.0f", monthlyUsed)) / \(String(
                format: "%.0f",
                monthlyLimit
            )) (\(weeklyPct)%)
            ║ 👤 Plan:     GLM Coding Plan
            """

        case .gemini:
            let remaining = usageData.geminiRemainingFraction ?? (1.0 - usageData.sessionPercentage)
            output += """

            ║ 📊 Quota:    \(sessionPct)% used │ \(Int(remaining * 100))% remaining
            ║ 👤 Tier:     \(usageData.tier)
            """
            if let modelId = usageData.geminiModelId {
                output += "\n║ 🤖 Model:    \(modelId)"
            }

        case .antigravity:
            output += """

            ║ 📊 Session:  \(sessionPct)% │ Reset: \(usageData.sessionResetDisplay)
            ║ 📈 Weekly:   \(weeklyPct)% │ Reset: \(usageData.weeklyResetDisplay)
            ║ 👤 Tier:     \(usageData.tier)
            """
            if let modelName = usageData.antigravityModelName {
                output += "\n║ 🤖 Model:    \(modelName)"
            }

        case .openai:
            let tokensUsed = usageData.openaiTokensUsed ?? 0
            let cost = usageData.openaiCost ?? 0
            output += """

            ║ 📊 Tokens:   \(tokensUsed.formatted())
            ║ 💰 Cost:     $\(String(format: "%.4f", cost))
            ║ 👤 Org:      \(usageData.orgName ?? "Unknown")
            """

        case .codex:
            let sessionUsed = usageData.codexSessionUsed ?? 0
            let sessionLimit = usageData.codexSessionLimit ?? 0
            let weeklyUsed = usageData.codexWeeklyUsed ?? 0
            let weeklyLimit = usageData.codexWeeklyLimit ?? 0
            output += """

            ║ ⏱️ Session:  \(sessionUsed) / \(sessionLimit) msgs (\(sessionPct)%)
            ║ 📅 Weekly:   \(weeklyUsed) / \(weeklyLimit) msgs (\(weeklyPct)%)
            ║ 👤 Plan:     \(usageData.planType ?? "Plus")
            """
        }

        output += """

        ╚════════════════════════════════════════════════════════════════╝
        """

        log.info("\(output, privacy: .private)")
    }
}
