import Foundation
import WebKit

enum AccountType: String, Codable {
    case claude
    case cursor
}

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
    
    var cursorUsed: Int?
    var cursorLimit: Int?
}

struct ClaudeAccount: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var type: AccountType = .claude
    var cookieProps: [[String: String]] = []
    var usageData: UsageData?
    
    enum CodingKeys: String, CodingKey {
        case id, name, type, cookieProps, usageData
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decodeIfPresent(AccountType.self, forKey: .type) ?? .claude
        cookieProps = try container.decodeIfPresent([[String: String]].self, forKey: .cookieProps) ?? []
        usageData = try container.decodeIfPresent(UsageData.self, forKey: .usageData)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encode(cookieProps, forKey: .cookieProps)
        try container.encode(usageData, forKey: .usageData)
    }
    
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
    
    init(name: String, cookies: [HTTPCookie], type: AccountType = .claude) {
        self.name = name
        self.type = type
        self.cookieProps = cookies.compactMap { $0.toCodable() }
    }
    
    init(id: UUID, name: String, cookies: [HTTPCookie], usageData: UsageData?, type: AccountType = .claude) {
        self.id = id
        self.name = name
        self.type = type
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
