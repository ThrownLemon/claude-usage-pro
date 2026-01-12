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
            "No OAuth token is available."
        case .invalidURL:
            "The API URL is invalid."
        case let .httpError(code, msg):
            if let msg {
                "The server returned HTTP \(code): \(msg)"
            } else {
                "The server returned HTTP \(code)."
            }
        case let .decodingError(error):
            "Failed to parse the server response: \(error.localizedDescription)"
        case let .networkError(error):
            "A network error occurred: \(error.localizedDescription)"
        case let .allRetriesFailed(lastError):
            "All retry attempts failed: \(lastError?.localizedDescription ?? "Unknown")"
        case .rateLimitExceeded:
            "Rate limit exceeded. Please wait before trying again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .noToken:
            return "Make sure Claude Code is installed and authenticated, or add a Claude.ai account."
        case let .httpError(code, _):
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
        "claude_team": "Team",
    ]

    // MARK: - Public API

    /// Fetches usage data from the Anthropic OAuth API with retry logic.
    /// - Parameter token: A valid OAuth token (starts with `sk-ant-oat` or `sk-ant-sid01`)
    /// - Returns: UsageData containing all usage statistics
    /// - Throws: AnthropicOAuthError if the request fails after all retries
    func fetchUsage(token: String) async throws -> UsageData {
        var lastError: Error?

        for attempt in 0 ..< maxRetries {
            do {
                let usageResponse = try await fetchUsageResponse(token: token)
                let planType = await fetchPlanType(token: token)

                return convertToUsageData(response: usageResponse, planType: planType)

            } catch AnthropicOAuthError.rateLimitExceeded {
                Log.warning(category, "Rate limit exceeded (attempt \(attempt + 1)/\(maxRetries))")
                lastError = AnthropicOAuthError.rateLimitExceeded
                let delay = rateLimitBackoffSeconds * pow(2.0, Double(attempt))
                try await Task.sleep(for: .seconds(delay))

            } catch let AnthropicOAuthError.networkError(error) {
                Log.warning(
                    category,
                    "Network error (attempt \(attempt + 1)/\(maxRetries)): \(error.localizedDescription)"
                )
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
            "client_id": clientId,
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

            guard (200 ... 299).contains(httpResponse.statusCode) else {
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

    /// Pings the Claude session to wake it up by creating and deleting a minimal conversation.
    /// Uses the claude.ai web API with the OAuth token.
    /// - Parameter token: A valid OAuth token
    /// - Returns: true if the ping succeeded, false otherwise
    func pingSession(token: String) async -> Bool {
        let claudeBaseURL = "https://claude.ai"

        // Step 1: Get organizations
        guard let orgsURL = URL(string: "\(claudeBaseURL)/api/organizations") else {
            Log.error(category, "Ping: Invalid organizations URL")
            return false
        }

        var orgsRequest = URLRequest(url: orgsURL)
        orgsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        orgsRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        let orgId: String
        do {
            let (orgsData, orgsResponse) = try await URLSession.shared.data(for: orgsRequest)
            guard let httpResponse = orgsResponse as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                let status = (orgsResponse as? HTTPURLResponse)?.statusCode ?? -1
                Log.error(category, "Ping: Failed to fetch organizations (status \(status))")
                return false
            }

            struct Org: Codable {
                let uuid: String?
                let id: String?
            }
            let orgs = try JSONDecoder().decode([Org].self, from: orgsData)
            guard let firstOrg = orgs.first, let id = firstOrg.uuid ?? firstOrg.id else {
                Log.error(category, "Ping: No organizations found")
                return false
            }
            orgId = id
            Log.debug(category, "Ping: Using organization \(orgId)")
        } catch {
            Log.error(category, "Ping: Error fetching organizations: \(error)")
            return false
        }

        // Step 2: Create conversation
        guard let createURL = URL(string: "\(claudeBaseURL)/api/organizations/\(orgId)/chat_conversations") else {
            Log.error(category, "Ping: Invalid create conversation URL")
            return false
        }

        let chatId: String
        do {
            var createRequest = URLRequest(url: createURL)
            createRequest.httpMethod = "POST"
            createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            createRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "uuid": UUID().uuidString.lowercased(),
                "name": "",
            ])

            let (createData, createResponse) = try await URLSession.shared.data(for: createRequest)
            guard let httpResponse = createResponse as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                let status = (createResponse as? HTTPURLResponse)?.statusCode ?? -1
                Log.error(category, "Ping: Failed to create conversation (status \(status))")
                return false
            }

            struct Chat: Codable {
                let uuid: String
            }
            let chat = try JSONDecoder().decode(Chat.self, from: createData)
            chatId = chat.uuid
            Log.debug(category, "Ping: Created conversation \(chatId)")
        } catch {
            Log.error(category, "Ping: Error creating conversation: \(error)")
            return false
        }

        // Step 3: Send minimal message
        guard let msgURL = URL(
            string: "\(claudeBaseURL)/api/organizations/\(orgId)/chat_conversations/\(chatId)/completion"
        ) else {
            Log.error(category, "Ping: Invalid message URL")
            return false
        }

        do {
            var msgRequest = URLRequest(url: msgURL)
            msgRequest.httpMethod = "POST"
            msgRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            msgRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            msgRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")

            let timezone = TimeZone.current.identifier
            msgRequest.httpBody = try JSONSerialization.data(withJSONObject: [
                "prompt": "hi",
                "timezone": timezone,
                "rendering_mode": "default",
                "attachments": [],
                "files": [],
            ] as [String: Any])

            let (_, msgResponse) = try await URLSession.shared.data(for: msgRequest)
            guard let httpResponse = msgResponse as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
                let status = (msgResponse as? HTTPURLResponse)?.statusCode ?? -1
                Log.error(category, "Ping: Failed to send message (status \(status))")
                // Still try to delete the conversation
                _ = await deleteConversation(token: token, orgId: orgId, chatId: chatId)
                return false
            }
            Log.debug(category, "Ping: Message sent successfully")
        } catch {
            Log.error(category, "Ping: Error sending message: \(error)")
            // Still try to delete the conversation
            _ = await deleteConversation(token: token, orgId: orgId, chatId: chatId)
            return false
        }

        // Step 4: Delete conversation
        let deleted = await deleteConversation(token: token, orgId: orgId, chatId: chatId)
        if deleted {
            Log.info(category, "Ping: Success!")
        }
        return true
    }

    /// Helper to delete a conversation during ping cleanup
    private func deleteConversation(token: String, orgId: String, chatId: String) async -> Bool {
        let claudeBaseURL = "https://claude.ai"
        guard let deleteURL = URL(
            string: "\(claudeBaseURL)/api/organizations/\(orgId)/chat_conversations/\(chatId)"
        ) else {
            return false
        }

        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.httpMethod = "DELETE"
        deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)
            let status = (deleteResponse as? HTTPURLResponse)?.statusCode ?? -1
            Log.debug(category, "Ping: Deleted conversation (status \(status))")
            return (200 ... 299).contains(status)
        } catch {
            Log.warning(category, "Ping: Failed to delete conversation: \(error)")
            return false
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

            guard (200 ... 299).contains(httpResponse.statusCode) else {
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
                  (200 ... 299).contains(httpResponse.statusCode)
            else {
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
            true
        default:
            false
        }
    }

    private func convertToUsageData(response: OAuthUsageResponse, planType: String?) -> UsageData {
        // Parse session (5-hour)
        var sessionPct = 0.0
        var sessionReset = Constants.Status.ready
        if let fiveHour = response.fiveHour {
            sessionPct = fiveHour.utilization / 100.0
            if let resetDateStr = fiveHour.resetsAt {
                sessionReset = DateFormattingHelper.formatResetTime(isoDate: resetDateStr)
            }
        }

        // Parse weekly (7-day)
        var weeklyPct = 0.0
        var weeklyReset = Constants.Status.ready
        if let sevenDay = response.sevenDay {
            weeklyPct = sevenDay.utilization / 100.0
            if let resetDateStr = sevenDay.resetsAt {
                weeklyReset = DateFormattingHelper.formatResetDate(isoDate: resetDateStr)
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
            opusReset: response.sevenDayOpus?.resetsAt.map { DateFormattingHelper.formatResetDate(isoDate: $0) },
            sonnetPercentage: response.sevenDaySonnet.map { $0.utilization / 100.0 },
            sonnetReset: response.sevenDaySonnet?.resetsAt.map { DateFormattingHelper.formatResetDate(isoDate: $0) }
        )
    }
}
