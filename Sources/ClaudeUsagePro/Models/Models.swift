import Foundation
import WebKit

struct UsageData: Hashable, Codable {
    var sessionPercentage: Double
    var sessionReset: String
    var sessionResetDisplay: String
    var weeklyPercentage: Double
    var weeklyReset: String
    var tier: String
    var email: String?
    
    var fullName: String?
    var orgName: String?
    var planType: String?
}

struct ClaudeAccount: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var cookieProps: [[String: String]] // Store as raw properties
    
    // Usage Data is transient, we don't save it, or we make it Codable too (let's save it for cache)
    var usageData: UsageData?
    
    var limitDetails: String {
        return usageData?.tier ?? "Fetching..."
    }
    
    var cookies: [HTTPCookie] {
        return cookieProps.compactMap { props in
            // Convert String keys back to HTTPCookiePropertyKey
            var convertedProps: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in props {
                convertedProps[HTTPCookiePropertyKey(rawValue: k)] = v
            }
            if let secure = props[HTTPCookiePropertyKey.secure.rawValue] {
                  convertedProps[.secure] = (secure == "TRUE" || secure == "true")
            }
            if let discard = props[HTTPCookiePropertyKey.discard.rawValue] {
                  convertedProps[.discard] = (discard == "TRUE" || discard == "true")
            }
            return HTTPCookie(properties: convertedProps)
        }
    }
    
    init(name: String, cookies: [HTTPCookie]) {
        self.name = name
        self.cookieProps = cookies.compactMap { $0.toCodable() }
    }
    
    init(id: UUID, name: String, cookies: [HTTPCookie], usageData: UsageData?) {
        self.id = id
        self.name = name
        self.cookieProps = cookies.compactMap { $0.toCodable() }
        self.usageData = usageData
    }
    
    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: ClaudeAccount, rhs: ClaudeAccount) -> Bool {
        lhs.id == rhs.id
    }
}
