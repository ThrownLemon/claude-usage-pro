import Foundation

enum ClaudeAPIError: Error, LocalizedError {
    case invalidURL(String)
    case fetchFailed(String, Error?)
    case parseFailed(String)
    case unauthorized
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let endpoint):
            return "Invalid URL for endpoint: \(endpoint)"
        case .fetchFailed(let endpoint, let error):
            return "Failed to fetch from \(endpoint): \(error?.localizedDescription ?? "Unknown error")"
        case .parseFailed(let model):
            return "Failed to parse \(model) response"
        case .unauthorized:
            return "Session unauthorized. Please log in again."
        case .badResponse(let statusCode):
            return "Server returned an error status: \(statusCode)"
        }
    }
}

class ClaudeAPIService {
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }
    
    func fetchUsage(cookies: [HTTPCookie]) async throws -> UsageData {
        let orgId = try await fetchOrgId(cookies: cookies)
        
        async let usageDataTask = fetchUsageData(orgId: orgId, cookies: cookies)
        async let userInfoTask = fetchUserInfo(cookies: cookies)
        async let tierTask = fetchTier(orgId: orgId, cookies: cookies)
        
        var (usageData, userInfo, tier) = try await (usageDataTask, userInfoTask, tierTask)
        
        if let userInfo = userInfo {
            usageData.email = userInfo.email
            usageData.fullName = userInfo.fullName
        }
        if let tier = tier {
            usageData.tier = tier
        }
        
        return usageData
    }
    
    private func fetchOrgId(cookies: [HTTPCookie]) async throws -> String {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            throw ClaudeAPIError.invalidURL("organizations")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)
        
        let (data, response) = try await session.data(for: request)
        try validateResponse(response)
        
        guard let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let orgId = orgs.first?["uuid"] as? String ?? orgs.first?["id"] as? String else {
            throw ClaudeAPIError.parseFailed("organizations")
        }
        return orgId
    }
    
    private func fetchUsageData(orgId: String, cookies: [HTTPCookie]) async throws -> UsageData {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
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
            sessionResetDisplay: sessionReset,
            weeklyPercentage: weeklyPct,
            weeklyReset: weeklyReset,
            tier: "Unknown",
            email: nil,
            fullName: nil,
            orgName: nil,
            planType: nil
        )
    }
    
    private func fetchUserInfo(cookies: [HTTPCookie]) async throws -> (email: String?, fullName: String?)? {
        guard let url = URL(string: "https://claude.ai/api/users/me") else {
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
    
    private func fetchTier(orgId: String, cookies: [HTTPCookie]) async throws -> String? {
        guard let url = URL(string: "https://claude.ai/api/bootstrap/\(orgId)/statsig") else {
            throw ClaudeAPIError.invalidURL("statsig")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)
        
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let user = json["user"] as? [String: Any],
              let custom = user["custom"] as? [String: Any] else {
            return nil
        }
        
        let isPro = custom["isPro"] as? Bool ?? false
        return isPro ? "Pro" : "Free"
    }
    
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
    
    private func setupRequest(_ request: inout URLRequest, cookies: [HTTPCookie]) {
        let cookieHeader = HTTPCookie.requestHeaderFields(with: cookies)
        for (key, value) in cookieHeader {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("https://claude.ai/chats", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
    }
    
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
    
    private func formatResetDate(isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "E h:mm a"
        return displayFormatter.string(from: date)
    }
}
