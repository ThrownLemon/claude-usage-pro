import Foundation
import WebKit

/// Wrapper for cookie properties that can be encoded/decoded.
struct CookieProperties: Codable {
    /// Cookie properties as raw string key-value pairs
    let properties: [HTTPCookiePropertyKey.RawValue: String]
}

extension HTTPCookie {
    /// Converts this cookie to a Codable dictionary representation.
    /// - Returns: Dictionary of string properties, or nil if conversion fails
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

    /// Converts an array of codable cookie property dictionaries back to HTTPCookie objects.
    /// - Parameter cookieProps: Array of string dictionaries representing cookie properties
    /// - Returns: Array of HTTPCookie objects (nil entries are filtered out)
    static func fromCodable(_ cookieProps: [[String: String]]) -> [HTTPCookie] {
        return cookieProps.compactMap { props in
            // Convert String keys back to HTTPCookiePropertyKey
            var convertedProps: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in props {
                convertedProps[HTTPCookiePropertyKey(rawValue: k)] = v
            }
            // Handle boolean properties that need special conversion
            if let secure = props[HTTPCookiePropertyKey.secure.rawValue] {
                convertedProps[.secure] = (secure == "TRUE" || secure == "true")
            }
            if let discard = props[HTTPCookiePropertyKey.discard.rawValue] {
                convertedProps[.discard] = (discard == "TRUE" || discard == "true")
            }
            return HTTPCookie(properties: convertedProps)
        }
    }
}
