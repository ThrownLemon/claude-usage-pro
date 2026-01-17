import Foundation

/// Errors that can occur when fetching data from the Claude API.
enum ClaudeAPIError: Error, LocalizedError {
    /// The URL for the specified endpoint could not be constructed
    case invalidURL(String)
    /// A network request to the specified endpoint failed
    case fetchFailed(String, Error?)
    /// The response from the specified endpoint could not be parsed
    case parseFailed(String)
    /// The session is no longer valid and requires re-authentication
    case unauthorized
    /// The server returned a non-success status code
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(endpoint):
            "Invalid URL for endpoint: \(endpoint)"
        case let .fetchFailed(endpoint, error):
            "Failed to fetch from \(endpoint): \(error?.localizedDescription ?? "Unknown error")"
        case let .parseFailed(model):
            "Failed to parse \(model) response"
        case .unauthorized:
            "Session unauthorized. Please log in again."
        case let .badResponse(statusCode):
            "Server returned an error status: \(statusCode)"
        }
    }
}

/// Service for fetching usage data directly from the Claude.ai API using URLSession.
/// This is an alternative to the WKWebView-based TrackerService.
class ClaudeAPIService {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
    }

    /// Fetches usage data for a Claude account.
    /// - Parameter cookies: Authentication cookies from the login session
    /// - Returns: UsageData containing session and weekly usage statistics
    /// - Throws: ClaudeAPIError if any API call fails
    func fetchUsage(cookies: [HTTPCookie]) async throws -> UsageData {
        let orgId = try await fetchOrgId(cookies: cookies)

        async let usageDataTask = fetchUsageData(orgId: orgId, cookies: cookies)
        async let userInfoTask = fetchUserInfo(cookies: cookies)
        async let tierTask = fetchTier(orgId: orgId, cookies: cookies)

        var (usageData, userInfo, tier) = try await (usageDataTask, userInfoTask, tierTask)

        if let userInfo {
            usageData.email = userInfo.email
            usageData.fullName = userInfo.fullName
        }
        if let tier {
            usageData.tier = tier
        }

        return usageData
    }

    /// Fetches the organization ID for the authenticated user.
    /// - Parameter cookies: Authentication cookies
    /// - Returns: The organization UUID
    /// - Throws: ClaudeAPIError if the request fails or no organization is found
    private func fetchOrgId(cookies: [HTTPCookie]) async throws -> String {
        guard let url = URL(string: Constants.ClaudeAPI.baseURL + Constants.ClaudeAPI.organizationsPath) else {
            throw ClaudeAPIError.invalidURL("organizations")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let orgId = orgs.first?["uuid"] as? String ?? orgs.first?["id"] as? String
        else {
            throw ClaudeAPIError.parseFailed("organizations")
        }
        return orgId
    }

    /// Fetches usage statistics for the specified organization.
    /// - Parameters:
    ///   - orgId: The organization UUID
    ///   - cookies: Authentication cookies
    /// - Returns: UsageData with session and weekly usage percentages
    /// - Throws: ClaudeAPIError if the request fails
    private func fetchUsageData(orgId: String, cookies: [HTTPCookie]) async throws -> UsageData {
        guard let url = URL(string: Constants.ClaudeAPI.baseURL + Constants.ClaudeAPI.usagePath(orgId: orgId)) else {
            throw ClaudeAPIError.invalidURL("usage")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.parseFailed("usage")
        }

        var sessionPct = 0.0
        var sessionReset = "Ready"
        var weeklyPct = 0.0
        var weeklyReset = "Ready"

        if let fiveHour = json["five_hour"] as? [String: Any] {
            if let util = fiveHour["utilization"] as? Double {
                sessionPct = util / 100.0
            }
            if let resetDateStr = fiveHour["resets_at"] as? String {
                sessionReset = formatResetTime(isoDate: resetDateStr)
            }
        }

        if let sevenDay = json["seven_day"] as? [String: Any] {
            if let util = sevenDay["utilization"] as? Double {
                weeklyPct = util / 100.0
            }
            if let resetDateStr = sevenDay["resets_at"] as? String {
                weeklyReset = formatResetDate(isoDate: resetDateStr)
            }
        }

        return UsageData(
            sessionPercentage: sessionPct,
            sessionReset: sessionReset,
            sessionResetDisplay: UsageData.formatSessionResetDisplay(sessionReset),
            weeklyPercentage: weeklyPct,
            weeklyReset: weeklyReset,
            weeklyResetDisplay: weeklyReset,
            tier: "Unknown",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: nil
        )
    }

    /// Fetches user profile information.
    /// - Parameter cookies: Authentication cookies
    /// - Returns: Tuple of email and full name, or nil if unavailable
    /// - Throws: ClaudeAPIError if the URL is invalid
    private func fetchUserInfo(cookies: [HTTPCookie]) async throws -> (email: String?, fullName: String?)? {
        guard let url = URL(string: Constants.ClaudeAPI.baseURL + Constants.ClaudeAPI.userPath) else {
            throw ClaudeAPIError.invalidURL("me")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let email = json["email_address"] as? String ?? json["email"] as? String
        let name = json["full_name"] as? String
        return (email, name)
    }

    /// Fetches the subscription tier for the organization.
    /// - Parameters:
    ///   - orgId: The organization UUID
    ///   - cookies: Authentication cookies
    /// - Returns: The tier name ("Pro" or "Free"), or nil if unavailable
    /// - Throws: ClaudeAPIError if the URL is invalid
    private func fetchTier(orgId: String, cookies: [HTTPCookie]) async throws -> String? {
        guard let url = URL(string: Constants.ClaudeAPI.baseURL + Constants.ClaudeAPI.statsigPath(orgId: orgId)) else {
            throw ClaudeAPIError.invalidURL("statsig")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)

        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let custom = user["custom"] as? [String: Any]
        else {
            return nil
        }

        let isPro = custom["isPro"] as? Bool ?? false
        return isPro ? "Pro" : "Free"
    }

    /// Validates an HTTP response and throws appropriate errors for failures.
    /// - Parameter response: The URL response to validate
    /// - Throws: ClaudeAPIError for non-200 status codes or unauthorized access
    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.fetchFailed("network", nil)
        }

        if httpResponse.statusCode == 401 {
            throw ClaudeAPIError.unauthorized
        }

        if httpResponse.statusCode != 200 {
            throw ClaudeAPIError.badResponse(httpResponse.statusCode)
        }
    }

    /// Configures a URL request with authentication cookies and required headers.
    /// - Parameters:
    ///   - request: The request to configure (modified in place)
    ///   - cookies: Authentication cookies to include
    private func setupRequest(_ request: inout URLRequest, cookies: [HTTPCookie]) {
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in cookieHeader {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.setValue(Constants.ClaudeAPI.baseURL, forHTTPHeaderField: "Origin")
        request.setValue(Constants.ClaudeAPI.baseURL + "/chats", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    /// Formats an ISO date string into a human-readable time remaining string.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "3h 21m" or "Ready" if time has passed
    private func formatResetTime(isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else { return isoDate }

        let diff = date.timeIntervalSinceNow
        if diff <= 0 { return "Ready" }

        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        return "\(hours)h \(mins)m"
    }

    /// Formats an ISO date string into a human-readable date display.
    /// - Parameter isoDate: ISO 8601 formatted date string
    /// - Returns: Formatted string like "Thu 8:59 PM"
    private func formatResetDate(isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else { return isoDate }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "E h:mm a"
        return displayFormatter.string(from: date)
    }
}
