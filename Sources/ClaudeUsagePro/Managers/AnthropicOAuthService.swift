import Foundation
import os

/// Errors that can occur when communicating with the Anthropic OAuth API.
enum AnthropicOAuthError: Error, LocalizedError {
    /// No OAuth token is available or configured
    case noToken
    /// The API URL could not be constructed
    case invalidURL
    /// The server returned an HTTP error status code
    case httpError(statusCode: Int, message: String?)
    /// The response could not be decoded as expected JSON
    case decodingError(Error)
    /// A network-level error occurred (e.g., no connection, timeout)
    case networkError(Error)
    /// All retry attempts failed
    case allRetriesFailed(lastError: Error?)
    /// Rate limit exceeded
    case rateLimitExceeded

    var errorDescription: String? {
        String(localized: "Could not access the Anthropic API.")
    }

    var failureReason: String? {
        switch self {
        case .noToken:
            return "No OAuth token is available."
        case .invalidURL:
            return "The API URL is invalid."
        case let .httpError(code, msg):
            if let msg = msg {
                return "The server returned HTTP \(code): \(msg)"
            } else {
                return "The server returned HTTP \(code)."
            }
        case .decodingError(let error):
            return "Failed to parse the server response: \(error.localizedDescription)"
        case .networkError(let error):
            return "A network error occurred: \(error.localizedDescription)"
        case .allRetriesFailed(let lastError):
            return "All retry attempts failed: \(lastError?.localizedDescription ?? "Unknown")"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please wait before trying again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noToken:
            return "Make sure Claude Code is installed and authenticated, or add a Claude.ai account."
        case .httpError(let code, _):
            if code == 401 {
                return "Your token may be invalid or expired. Try re-authenticating in Claude Code."
            } else if code == 429 {
                return "You've exceeded the rate limit. Please wait before trying again."
            }
            return nil
        case .networkError:
            return "Check your internet connection and try again."
        default:
            return nil
        }
    }
}

// MARK: - API Response Models

/// A single usage bucket from the OAuth API response.
struct OAuthUsageBucket: Codable {
    /// The current utilization as a percentage (0-100)
    let utilization: Double
    /// The ISO 8601 timestamp when this limit will reset, or nil if not applicable
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// The raw JSON response from the Anthropic OAuth usage API endpoint.
struct OAuthUsageResponse: Codable {
    /// The 5-hour rolling session limit
    let fiveHour: OAuthUsageBucket?
    /// The 7-day combined usage limit across all models
    let sevenDay: OAuthUsageBucket?
    /// The 7-day usage limit for OAuth applications
    let sevenDayOauthApps: OAuthUsageBucket?
    /// The 7-day usage limit specifically for Claude Opus
    let sevenDayOpus: OAuthUsageBucket?
    /// The 7-day usage limit specifically for Claude Sonnet
    let sevenDaySonnet: OAuthUsageBucket?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOauthApps = "seven_day_oauth_apps"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

/// Profile response from the OAuth profile endpoint.
struct OAuthProfileResponse: Codable {
    let organization: OAuthOrganization?

    struct OAuthOrganization: Codable {
        let organizationType: String?

        enum CodingKeys: String, CodingKey {
            case organizationType = "organization_type"
        }
    }
}

// MARK: - Service

/// A service for communicating with the Anthropic OAuth API.
/// Uses the official OAuth endpoints instead of scraping claude.ai.
///
/// This is a significant improvement over the WKWebView approach:
/// - Uses official, documented API
/// - No WebView overhead
/// - Proper error handling with retry logic
/// - Exponential backoff for rate limiting
actor AnthropicOAuthService {
    private let category = Log.Category.api

    // API Configuration (from Constants)
    private var baseURL: String { Constants.AnthropicAPI.baseURL }
    private var usagePath: String { Constants.AnthropicAPI.usagePath }
    private var profilePath: String { Constants.AnthropicAPI.profilePath }
    private var tokenURL: String { Constants.OAuth.tokenURL }
    private var clientId: String { Constants.OAuth.clientId }
    private var anthropicBetaHeader: String { Constants.AnthropicAPI.betaHeader }
    private var userAgent: String { Constants.AnthropicAPI.userAgent }

    // Retry Configuration (from Constants)
    private var maxRetries: Int { Constants.AnthropicAPI.maxRetries }
    private var baseBackoffSeconds: Double { Constants.AnthropicAPI.baseBackoffSeconds }
    private var rateLimitBackoffSeconds: Double { Constants.AnthropicAPI.rateLimitBackoffSeconds }

    /// Map organization_type to display name
    private let planTypeMap: [String: String] = [
        "claude_max": "Max",
        "claude_pro": "Pro",
        "claude_enterprise": "Enterprise",
        "claude_team": "Team"
    ]

    // MARK: - Public API

    /// Fetches usage data from the Anthropic OAuth API with retry logic.
    /// - Parameter token: A valid OAuth token (starts with `sk-ant-oat` or `sk-ant-sid01`)
    /// - Returns: UsageData containing all usage statistics
    /// - Throws: AnthropicOAuthError if the request fails after all retries
    func fetchUsage(token: String) async throws -> UsageData {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                let usageResponse = try await fetchUsageResponse(token: token)
                let planType = await fetchPlanType(token: token)

                return convertToUsageData(response: usageResponse, planType: planType)

            } catch AnthropicOAuthError.rateLimitExceeded {
                Log.warning(category, "Rate limit exceeded (attempt \(attempt + 1)/\(maxRetries))")
                lastError = AnthropicOAuthError.rateLimitExceeded
                let delay = rateLimitBackoffSeconds * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))

            } catch AnthropicOAuthError.networkError(let error) {
                Log.warning(category, "Network error (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                lastError = AnthropicOAuthError.networkError(error)
                let delay = baseBackoffSeconds * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))

            } catch let error as URLError where isRetryableURLError(error) {
                Log.warning(category, "URL error (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)")
                lastError = error
                let delay = baseBackoffSeconds * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))

            } catch {
                // Non-retryable error, fail immediately
                Log.error(category, "Non-retryable error: \(error.localizedDescription)")
                throw error
            }
        }

        Log.error(category, "All \(maxRetries) retry attempts failed")
        throw AnthropicOAuthError.allRetriesFailed(lastError: lastError)
    }

    /// Validates whether a token is valid by attempting to fetch usage data.
    /// - Parameter token: The token to validate
    /// - Returns: true if the token is valid and the API call succeeded
    func validateToken(_ token: String) async -> Bool {
        do {
            _ = try await fetchUsageResponse(token: token)
            return true
        } catch {
            return false
        }
    }

    /// Attempts to refresh an access token using a refresh token.
    /// - Parameter refreshToken: The refresh token obtained during initial authentication
    /// - Returns: A new token response containing the fresh access token and possibly a new refresh token
    /// - Throws: AnthropicOAuthError if the refresh fails
    func refreshAccessToken(refreshToken: String) async throws -> OAuthTokenResponse {
        guard let url = URL(string: tokenURL) else {
            throw AnthropicOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build JSON body for refresh token grant
        let bodyParams: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyParams)

        Log.debug(category, "Attempting to refresh access token...")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AnthropicOAuthError.networkError(NSError(domain: "Invalid response", code: -1))
            }

            if httpResponse.statusCode == 429 {
                throw AnthropicOAuthError.rateLimitExceeded
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                Log.warning(category, "Token refresh HTTP error: \(httpResponse.statusCode)")
                throw AnthropicOAuthError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
            Log.info(category, "Successfully refreshed access token")
            return tokenResponse
        } catch let error as AnthropicOAuthError {
            throw error
        } catch {
            Log.error(category, "Token refresh network error: \(error)")
            throw AnthropicOAuthError.networkError(error)
        }
    }

    // MARK: - Private Implementation

    private func fetchUsageResponse(token: String) async throws -> OAuthUsageResponse {
        guard let url = URL(string: baseURL + usagePath) else {
            throw AnthropicOAuthError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Log.debug(category, "Fetching usage data from OAuth API")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AnthropicOAuthError.networkError(NSError(domain: "Invalid response", code: -1))
            }

            if httpResponse.statusCode == 429 {
                throw AnthropicOAuthError.rateLimitExceeded
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8)
                Log.warning(category, "HTTP error: \(httpResponse.statusCode)")
                throw AnthropicOAuthError.httpError(statusCode: httpResponse.statusCode, message: message)
            }

            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(OAuthUsageResponse.self, from: data)
                Log.debug(category, "Successfully fetched usage data")
                return response
            } catch {
                Log.error(category, "Failed to decode response: \(error)")
                throw AnthropicOAuthError.decodingError(error)
            }
        } catch let error as AnthropicOAuthError {
            throw error
        } catch {
            Log.error(category, "Network error: \(error)")
            throw AnthropicOAuthError.networkError(error)
        }
    }

    /// Fetch plan type from profile endpoint (best effort, non-throwing)
    private func fetchPlanType(token: String) async -> String? {
        guard let url = URL(string: baseURL + profilePath) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            let profileResponse = try JSONDecoder().decode(OAuthProfileResponse.self, from: data)
            if let orgType = profileResponse.organization?.organizationType {
                return planTypeMap[orgType] ?? orgType
            }
            return nil
        } catch {
            Log.debug(category, "Failed to fetch plan type (non-critical): \(error.localizedDescription)")
            return nil
        }
    }

    private func isRetryableURLError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func convertToUsageData(response: OAuthUsageResponse, planType: String?) -> UsageData {
        // Parse session (5-hour)
        var sessionPct = 0.0
        var sessionReset = "Ready"
        if let fiveHour = response.fiveHour {
            sessionPct = fiveHour.utilization / 100.0
            if let resetDateStr = fiveHour.resetsAt {
                sessionReset = formatResetTime(isoDate: resetDateStr)
            }
        }

        // Parse weekly (7-day)
        var weeklyPct = 0.0
        var weeklyReset = "Ready"
        if let sevenDay = response.sevenDay {
            weeklyPct = sevenDay.utilization / 100.0
            if let resetDateStr = sevenDay.resetsAt {
                weeklyReset = formatResetDate(isoDate: resetDateStr)
            }
        }

        // Determine tier from plan type
        let tier = planType ?? "Pro"

        return UsageData(
            sessionPercentage: sessionPct,
            sessionReset: sessionReset,
            sessionResetDisplay: UsageData.formatSessionResetDisplay(sessionReset),
            weeklyPercentage: weeklyPct,
            weeklyReset: weeklyReset,
            weeklyResetDisplay: weeklyReset,
            tier: tier,
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: planType,
            // Extended OAuth data
            opusPercentage: response.sevenDayOpus.map { $0.utilization / 100.0 },
            opusReset: response.sevenDayOpus?.resetsAt.map { formatResetDate(isoDate: $0) },
            sonnetPercentage: response.sevenDaySonnet.map { $0.utilization / 100.0 },
            sonnetReset: response.sevenDaySonnet?.resetsAt.map { formatResetDate(isoDate: $0) }
        )
    }

    // MARK: - Date Formatting

    /// Shared ISO8601 date parser with fallback for fractional seconds
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parse an ISO8601 date string, trying with and without fractional seconds
    private func parseISO8601Date(_ isoDate: String) -> Date? {
        Self.iso8601Formatter.date(from: isoDate) ?? Self.iso8601FallbackFormatter.date(from: isoDate)
    }

    private func formatResetTime(isoDate: String) -> String {
        guard let date = parseISO8601Date(isoDate) else {
            return isoDate
        }
        return formatTimeRemaining(date)
    }

    private func formatTimeRemaining(_ date: Date) -> String {
        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Ready" }

        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)h \(mins)m"
    }

    private func formatResetDate(isoDate: String) -> String {
        guard let date = parseISO8601Date(isoDate) else {
            return isoDate
        }
        return formatDateDisplay(date)
    }

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E h:mm a"
        return formatter
    }()

    private func formatDateDisplay(_ date: Date) -> String {
        Self.displayDateFormatter.string(from: date)
    }
}
