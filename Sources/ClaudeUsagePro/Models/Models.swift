import Foundation
import WebKit

struct UsageData: Hashable, Codable {
    var sessionPercentage: Double // 0.0 to 1.0
    var sessionReset: String // e.g., "3 hr 21 min"
    var weeklyPercentage: Double // 0.0 to 1.0
    var weeklyReset: String // e.g., "Thu 8:59 PM"
    var tier: String // "Free", "Pro", "Team"
    var email: String?
    
    // New Metadata
    var fullName: String?
    var orgName: String?
    var planType: String?
}
