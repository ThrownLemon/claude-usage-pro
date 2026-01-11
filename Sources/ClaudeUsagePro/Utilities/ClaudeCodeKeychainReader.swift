import Foundation
import Security

/// Reads Claude Code's OAuth token from the system Keychain.
/// Claude Code stores its authentication token in the macOS Keychain.
///
/// This allows AI Usage Pro to automatically detect and use existing
/// Claude Code authentication without requiring manual token entry.
struct ClaudeCodeKeychainReader {
    /// Errors that can occur when reading Claude Code credentials
    enum Error: LocalizedError {
        case notFound
        case accessDenied(OSStatus)
        case invalidData
        case unexpectedError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Claude Code credentials not found in Keychain"
            case .accessDenied(let status):
                return "Access denied to Claude Code credentials (status: \(status))"
            case .invalidData:
                return "Claude Code credentials data is invalid"
            case .unexpectedError(let status):
                return "Unexpected Keychain error (status: \(status))"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .notFound:
                return "Make sure Claude Code is installed and you've signed in at least once."
            case .accessDenied:
                return "You may need to allow access to Claude Code's keychain item in Keychain Access."
            default:
                return nil
            }
        }
    }

    /// The primary keychain service name used by Claude Code CLI
    private static let primaryService = "Claude Code-credentials"

    /// JSON structure for Claude Code credentials
    private struct ClaudeCredentials: Codable {
        struct OAuthData: Codable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Int64?
        }
        let claudeAiOauth: OAuthData?
    }

    /// Attempts to read the OAuth token from Claude Code's Keychain storage.
    /// - Returns: The OAuth token if found
    /// - Throws: Error if the token cannot be retrieved
    static func readOAuthToken() throws -> String {
        // Read from Claude Code's keychain storage (JSON format with accessToken)
        let token = try readClaudeCodeCredentials()
        Log.debug(Log.Category.keychain, "Found Claude Code token in '\(primaryService)'")
        return token
    }

    /// Reads Claude Code credentials from the primary keychain location.
    /// The credentials are stored as JSON with an accessToken field.
    private static func readClaudeCodeCredentials() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: primaryService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            throw Error.notFound
        }

        // Parse the JSON to extract the access token
        do {
            let credentials = try JSONDecoder().decode(ClaudeCredentials.self, from: data)
            if let token = credentials.claudeAiOauth?.accessToken, isValidToken(token) {
                return token
            }
        } catch {
            // Try parsing as plain string if JSON fails
            if let plainToken = String(data: data, encoding: .utf8), isValidToken(plainToken) {
                return plainToken
            }
        }

        throw Error.invalidData
    }

    /// Checks if Claude Code credentials are available without retrieving them.
    /// - Returns: true if credentials appear to be available
    static func hasCredentials() -> Bool {
        (try? readClaudeCodeCredentials()) != nil
    }

    /// Validates that a token has the expected format.
    private static func isValidToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)

        // OAuth tokens start with sk-ant-oat
        // Session IDs start with sk-ant-sid01
        // API keys start with sk-ant-api
        return trimmed.hasPrefix("sk-ant-") && trimmed.count > 20
    }

    /// Returns information about which credential source was used.
    static func credentialSource() -> String? {
        hasCredentials() ? primaryService : nil
    }
}

// MARK: - Convenience Extension

extension ClaudeCodeKeychainReader {
    /// Attempts to create a UsageData fetch using Claude Code's stored credentials.
    /// This is the recommended way to get usage data if the user has Claude Code installed.
    ///
    /// Usage:
    /// ```swift
    /// if let token = try? ClaudeCodeKeychainReader.readOAuthToken() {
    ///     let service = AnthropicOAuthService()
    ///     let usage = try await service.fetchUsage(token: token)
    /// }
    /// ```
    static func description() -> String {
        if hasCredentials() {
            if let source = credentialSource() {
                return "Claude Code credentials found in '\(source)'"
            }
            return "Claude Code credentials available"
        }
        return "No Claude Code credentials found"
    }
}
