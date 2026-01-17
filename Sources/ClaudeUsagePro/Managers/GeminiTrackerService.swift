import Foundation
import os

/// Errors that can occur when tracking Google Gemini CLI usage.
enum GeminiTrackerError: Error, LocalizedError {
    /// Gemini CLI not installed or credentials not found
    case credentialsNotFound
    /// Client credentials (client_id/client_secret) not found in Gemini CLI binary
    case clientCredentialsNotFound
    /// OAuth token refresh failed
    case tokenRefreshFailed(Error)
    /// Quota fetch failed
    case quotaFetchFailed(Error)
    /// Invalid response from API
    case invalidResponse(String)
    /// Network request failed
    case networkError(Error)
    /// HTTP error with status code
    case httpError(statusCode: Int)
    /// Token expired and no refresh token available
    case tokenExpired

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            "Gemini CLI credentials not found. Please run 'gemini auth login' first."
        case .clientCredentialsNotFound:
            "Could not extract client credentials from Gemini CLI. Try reinstalling the CLI."
        case let .tokenRefreshFailed(error):
            "Failed to refresh OAuth token: \(error.localizedDescription)"
        case let .quotaFetchFailed(error):
            "Failed to fetch quota: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid API response: \(message)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .httpError(statusCode):
            "HTTP error (status \(statusCode))"
        case .tokenExpired:
            "OAuth token expired. Please re-authenticate with Gemini CLI."
        }
    }
}

// MARK: - Gemini OAuth Tokens

/// OAuth tokens stored by Gemini CLI in ~/.gemini/oauth_creds.json
struct GeminiOAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let expiryDate: Int64? // Unix timestamp in milliseconds

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiryDate = "expiry_date"
    }

    /// Check if the access token is expired (with 5 minute buffer)
    var isExpired: Bool {
        guard let expiry = expiryDate else { return false }
        let expiryDate = Date(timeIntervalSince1970: Double(expiry) / 1000.0)
        return expiryDate.addingTimeInterval(-300) < Date() // 5 minute buffer
    }
}

// MARK: - Gemini API Response Models

private struct GeminiQuotaResponse: Codable {
    let quotaBuckets: [QuotaBucket]?

    struct QuotaBucket: Codable {
        let remainingFraction: Double?
        let resetTime: String?
        let modelId: String?
    }
}

private struct GeminiTierResponse: Codable {
    let tier: String?
    let planType: String?
}

private struct TokenRefreshResponse: Codable {
    let accessToken: String
    let expiresIn: Int?
    let tokenType: String?
    let scope: String?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
        case idToken = "id_token"
    }
}

/// Usage information for a Gemini CLI account.
struct GeminiUsageInfo {
    /// Usage percentage (0.0-1.0) calculated from remainingFraction
    let sessionPercentage: Double
    /// Remaining quota fraction (0.0-1.0)
    let remainingFraction: Double
    /// Reset time as ISO-8601 string or formatted display
    let resetTime: String?
    /// Model ID (e.g., "gemini-2.5-flash")
    let modelId: String?
    /// Tier: "Paid", "Workspace", or "Free"
    let tier: String
}

/// Service for fetching Google Gemini CLI usage statistics.
/// Reads OAuth tokens from ~/.gemini/oauth_creds.json and queries the quota API.
///
/// Thread-safety: `clientId` and `clientSecret` are set once during init and never modified.
/// All other properties are immutable. Async methods use URLSession which is internally thread-safe.
final class GeminiTrackerService: @unchecked Sendable {
    private let category = "GeminiTracker"

    // API endpoints (centralized in Constants)
    private let quotaURL = Constants.GeminiAPI.quotaURL
    private let tierURL = Constants.GeminiAPI.tierURL
    private let tokenURL = Constants.GeminiAPI.tokenURL

    // Client credentials (extracted from Gemini CLI binary) - set once in init, never modified
    private var clientId: String?
    private var clientSecret: String?

    init() {
        loadClientCredentials()
    }

    // MARK: - Public Methods

    /// Detect Gemini CLI installation and read OAuth credentials.
    /// - Returns: OAuth tokens if found, nil otherwise
    func detectGeminiCLI() -> GeminiOAuthTokens? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let credsPath = homeDir.appendingPathComponent(".gemini/oauth_creds.json")

        guard FileManager.default.fileExists(atPath: credsPath.path) else {
            Log.debug(category, "Gemini credentials file not found at \(credsPath.path)")
            return nil
        }

        do {
            let data = try Data(contentsOf: credsPath)
            let tokens = try JSONDecoder().decode(GeminiOAuthTokens.self, from: data)
            Log.debug(category, "Found Gemini CLI credentials (token: \(Log.sanitize(tokens.accessToken)))")
            return tokens
        } catch {
            Log.error(category, "Failed to read Gemini credentials: \(error)")
            return nil
        }
    }

    /// Check if Gemini CLI credentials file exists.
    /// This is a lightweight check that only verifies file existence, not validity.
    /// Use `detectGeminiCLI()` for full credential validation.
    var isInstalled: Bool {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let credsPath = homeDir.appendingPathComponent(".gemini/oauth_creds.json")
        return FileManager.default.fileExists(atPath: credsPath.path)
    }

    /// Fetch usage quota from Gemini API.
    /// - Parameter accessToken: OAuth access token
    /// - Returns: Usage information
    /// - Throws: GeminiTrackerError on failure
    func fetchUsage(accessToken: String) async throws -> GeminiUsageInfo {
        guard let url = URL(string: quotaURL) else {
            throw GeminiTrackerError.invalidResponse("Invalid quota URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = "{}".data(using: .utf8) // Empty JSON body for POST

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiTrackerError.invalidResponse("Non-HTTP response")
        }

        if httpResponse.statusCode == 401 {
            throw GeminiTrackerError.tokenExpired
        }

        guard httpResponse.statusCode == 200 else {
            throw GeminiTrackerError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse quota response
        let quotaResponse = try JSONDecoder().decode(GeminiQuotaResponse.self, from: data)

        // Find the bucket with the lowest remaining fraction (most used)
        let bucket = quotaResponse.quotaBuckets?.min(by: {
            ($0.remainingFraction ?? 1.0) < ($1.remainingFraction ?? 1.0)
        })

        let remainingFraction = bucket?.remainingFraction ?? 1.0
        let sessionPercentage = 1.0 - remainingFraction

        // Fetch tier information
        let tier = await fetchTier(accessToken: accessToken)

        // Format reset time
        let resetDisplay: String?
        if let resetTime = bucket?.resetTime {
            resetDisplay = formatResetTime(resetTime)
        } else {
            resetDisplay = nil
        }

        Log.info(
            category,
            "Gemini usage: \(Int(sessionPercentage * 100))% used, tier: \(tier), model: \(bucket?.modelId ?? "unknown")"
        )

        return GeminiUsageInfo(
            sessionPercentage: sessionPercentage,
            remainingFraction: remainingFraction,
            resetTime: resetDisplay,
            modelId: bucket?.modelId,
            tier: tier
        )
    }

    /// Refresh the access token using the refresh token.
    /// - Parameter refreshToken: OAuth refresh token
    /// - Returns: New OAuth tokens with updated access token
    /// - Throws: GeminiTrackerError on failure
    func refreshToken(refreshToken: String) async throws -> GeminiOAuthTokens {
        guard let clientId, let clientSecret else {
            throw GeminiTrackerError.clientCredentialsNotFound
        }

        guard let url = URL(string: tokenURL) else {
            throw GeminiTrackerError.invalidResponse("Invalid token URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build URL-encoded form body with proper percent-encoding for reserved characters
        let bodyParams = [
            ("client_id", clientId),
            ("client_secret", clientSecret),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
        ]

        // Use CharacterSet that allows only unreserved characters per RFC 3986
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))

        let encodedBody = bodyParams.compactMap { key, value -> String? in
            guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
                  let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            else {
                return nil
            }
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")

        request.httpBody = encodedBody.data(using: .utf8)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GeminiTrackerError.tokenRefreshFailed(
                NSError(domain: "GeminiTracker", code: statusCode, userInfo: nil)
            )
        }

        let tokenResponse = try JSONDecoder().decode(TokenRefreshResponse.self, from: data)

        // Calculate new expiry time
        let expiryDate: Int64?
        if let expiresIn = tokenResponse.expiresIn {
            expiryDate = Int64(Date().timeIntervalSince1970 * 1000) + Int64(expiresIn * 1000)
        } else {
            expiryDate = nil
        }

        Log.info(category, "Successfully refreshed Gemini access token")

        return GeminiOAuthTokens(
            accessToken: tokenResponse.accessToken,
            refreshToken: refreshToken, // Keep the same refresh token
            idToken: tokenResponse.idToken,
            expiryDate: expiryDate
        )
    }

    // MARK: - Private Methods

    /// Load client credentials from Gemini CLI binary
    private func loadClientCredentials() {
        // Try multiple possible paths for the Gemini CLI
        let possiblePaths = [
            // Homebrew on Apple Silicon
            "/opt/homebrew/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            // Homebrew on Intel
            "/usr/local/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js",
            // npm global
            NSString(string: "~/.npm/lib/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
                .expandingTildeInPath,
            // bun global
            NSString(string: "~/.bun/install/global/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js")
                .expandingTildeInPath,
        ]

        for path in possiblePaths {
            if let (id, secret) = extractClientCredentials(fromPath: path) {
                clientId = id
                clientSecret = secret
                Log.debug(category, "Found Gemini client credentials from: \(path)")
                return
            }
        }

        // No fallback credentials - token refresh requires valid client credentials
        // extracted from the Gemini CLI binary. Without them, only initial token usage works.
        clientId = nil
        clientSecret = nil

        Log.warning(category, "Could not extract Gemini client credentials from CLI - token refresh will not work")
    }

    /// Extract client ID and secret from a JavaScript file
    private func extractClientCredentials(fromPath path: String) -> (String, String)? {
        guard FileManager.default.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            return nil
        }

        // Look for patterns like:
        // OAUTH_CLIENT_ID = "xxx.apps.googleusercontent.com"
        // OAUTH_CLIENT_SECRET = "GOCSPX-xxx"

        let clientIdPattern = #"OAUTH_CLIENT_ID\s*=\s*["']([^"']+)["']"#
        let clientSecretPattern = #"OAUTH_CLIENT_SECRET\s*=\s*["']([^"']+)["']"#

        guard let idRegex = try? NSRegularExpression(pattern: clientIdPattern),
              let secretRegex = try? NSRegularExpression(pattern: clientSecretPattern)
        else {
            return nil
        }

        let range = NSRange(content.startIndex..., in: content)

        guard let idMatch = idRegex.firstMatch(in: content, range: range),
              let secretMatch = secretRegex.firstMatch(in: content, range: range),
              let idRange = Range(idMatch.range(at: 1), in: content),
              let secretRange = Range(secretMatch.range(at: 1), in: content)
        else {
            return nil
        }

        return (String(content[idRange]), String(content[secretRange]))
    }

    /// Fetch tier information from the loadCodeAssist endpoint
    private func fetchTier(accessToken: String) async -> String {
        guard let url = URL(string: tierURL) else {
            return "Unknown"
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Include metadata in the request body
        let metadata: [String: Any] = [
            "ideType": "VSCODE",
            "pluginType": "GEMINI_CODE_ASSIST",
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: metadata)

        do {
            let (data, response) = try await performRequest(request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return "Unknown"
            }

            // Try to parse tier from response
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let tier = json["tier"] as? String {
                    return mapTierName(tier)
                }
            }

            return "Unknown"
        } catch {
            Log.warning(category, "Failed to fetch Gemini tier: \(error)")
            return "Unknown"
        }
    }

    /// Map tier codes to display names
    private func mapTierName(_ tier: String) -> String {
        switch tier.lowercased() {
        case "standard-tier", "paid":
            "Paid"
        case "free-tier":
            "Free"
        case "legacy-tier":
            "Legacy"
        default:
            if tier.contains("hd") {
                "Workspace"
            } else {
                tier.capitalized
            }
        }
    }

    /// Format reset time from ISO-8601 or epoch to display string
    private func formatResetTime(_ resetTime: String) -> String {
        // Try parsing as ISO-8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: resetTime) {
            return DateFormattingHelper.formatTimeRemaining(date)
        }

        // Try parsing as epoch seconds
        if let epochSeconds = Double(resetTime) {
            let date = Date(timeIntervalSince1970: epochSeconds)
            return DateFormattingHelper.formatTimeRemaining(date)
        }

        // Return as-is if parsing fails
        return resetTime
    }

    /// Perform HTTP request with error handling
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw GeminiTrackerError.networkError(error)
        }
    }
}
