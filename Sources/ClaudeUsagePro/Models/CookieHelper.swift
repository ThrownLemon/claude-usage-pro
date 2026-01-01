import Foundation

struct CookieProperties: Codable {
    let properties: [HTTPCookiePropertyKey.RawValue: String]
}

extension HTTPCookie {
    func toCodable() -> [String: String]? {
        guard let props = self.properties else { return nil }
        // Convert [HTTPCookiePropertyKey: Any] to [String: String]
        var stringProps: [String: String] = [:]
        for (key, value) in props {
            if let v = value as? String {
                stringProps[key.rawValue] = v
            } else if let v = value as? Int {
                 stringProps[key.rawValue] = String(v)
            } else if let v = value as? Bool {
                stringProps[key.rawValue] = String(v)
            }
        }
        return stringProps
    }
}
