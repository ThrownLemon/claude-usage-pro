import Foundation

class ClaudeAPIService {
    private let session: URLSession
    
    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        self.session = URLSession(configuration: config)
    }
    
    func fetchUsage(cookies: [HTTPCookie], completion: @escaping (Result<UsageData, Error>) -> Void) {
        let baseUrl = "https://claude.ai"
        
        guard let orgsUrl = URL(string: "\(baseUrl)/api/organizations") else { return }
        var orgsRequest = URLRequest(url: orgsUrl)
        orgsRequest.httpMethod = "GET"
        setupRequest(&orgsRequest, cookies: cookies)
        
        session.dataTask(with: orgsRequest) { [weak self] data, response, error in
            guard let self = self else { return }
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let orgs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let orgId = orgs.first?["uuid"] as? String ?? orgs.first?["id"] as? String else {
                completion(.failure(NSError(domain: "ClaudeAPI", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch organizations"])))
                return
            }
            
            self.fetchUsageData(orgId: orgId, cookies: cookies) { result in
                switch result {
                case .success(var usageData):
                    self.fetchUserInfo(cookies: cookies) { userInfo in
                        if let userInfo = userInfo {
                            usageData.email = userInfo.email
                            usageData.fullName = userInfo.fullName
                        }
                        
                        self.fetchTier(orgId: orgId, cookies: cookies) { tier in
                            if let tier = tier {
                                usageData.tier = tier
                            }
                            completion(.success(usageData))
                        }
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    private func fetchUsageData(orgId: String, cookies: [HTTPCookie], completion: @escaping (Result<UsageData, Error>) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)
        
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(NSError(domain: "ClaudeAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch usage data"])))
                return
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
                    sessionReset = self.formatResetTime(isoDate: resetDateStr)
                }
            }
            
            if let sevenDay = json["seven_day"] as? [String: Any] {
                if let util = sevenDay["utilization"] as? Double {
                    weeklyPct = util / 100.0
                }
                if let resetDateStr = sevenDay["resets_at"] as? String {
                    weeklyReset = self.formatResetDate(isoDate: resetDateStr)
                }
            }
            
            let dataObj = UsageData(
                sessionPercentage: sessionPct,
                sessionReset: sessionReset,
                weeklyPercentage: weeklyPct,
                weeklyReset: weeklyReset,
                tier: "Unknown",
                email: nil,
                fullName: nil,
                orgName: nil,
                planType: nil
            )
            completion(.success(dataObj))
        }.resume()
    }
    
    private func fetchUserInfo(cookies: [HTTPCookie], completion: @escaping ((email: String?, fullName: String?)?) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/users/me") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)
        
        session.dataTask(with: request) { data, response, error in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(nil)
                return
            }
            
            let email = json["email_address"] as? String ?? json["email"] as? String
            let name = json["full_name"] as? String
            completion((email, name))
        }.resume()
    }
    
    private func fetchTier(orgId: String, cookies: [HTTPCookie], completion: @escaping (String?) -> Void) {
        guard let url = URL(string: "https://claude.ai/api/bootstrap/\(orgId)/statsig") else {
            completion(nil)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        setupRequest(&request, cookies: cookies)
        
        session.dataTask(with: request) { data, response, error in
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let user = json["user"] as? [String: Any],
                  let custom = user["custom"] as? [String: Any] else {
                completion(nil)
                return
            }
            
            let isPro = custom["isPro"] as? Bool ?? false
            completion(isPro ? "Pro" : "Free")
        }.resume()
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
