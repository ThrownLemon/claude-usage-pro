import Foundation
import Security

/// A service for securely storing and retrieving sensitive data from the macOS Keychain.
/// Use this for storing cookies, API tokens, and other credentials instead of UserDefaults.
struct KeychainService {
    /// Errors that can occur during Keychain operations
    enum KeychainError: LocalizedError {
        case unableToSave(OSStatus)
        case unableToLoad(OSStatus)
        case unableToDelete(OSStatus)
        case dataConversionFailed
        case itemNotFound

        var errorDescription: String? {
            switch self {
            case .unableToSave(let status):
                return "Unable to save to Keychain: \(status)"
            case .unableToLoad(let status):
                return "Unable to load from Keychain: \(status)"
            case .unableToDelete(let status):
                return "Unable to delete from Keychain: \(status)"
            case .dataConversionFailed:
                return "Failed to convert data"
            case .itemNotFound:
                return "Item not found in Keychain"
            }
        }
    }

    /// The service identifier used to group related Keychain items
    /// Using a fixed identifier to ensure consistency across different run configurations
    private static let service = "com.claudeusagepro"

    /// Alternate service names to check for legacy data (migration support)
    private static let legacyServices = ["ClaudeUsagePro", Bundle.main.bundleIdentifier].compactMap { $0 }

    // MARK: - Core Operations

    /// Save data to the Keychain
    /// - Parameters:
    ///   - data: The data to store
    ///   - key: The unique key to identify this item
    /// - Throws: KeychainError if the operation fails
    ///
    /// Uses the file-based keychain (kSecUseDataProtectionKeychain: false) which works
    /// without code signing entitlements. This is required for CLI tools like `swift run`.
    /// See: https://developer.apple.com/forums/thread/114456
    static func save(_ data: Data, forKey key: String) throws {
        // First delete any existing item (best-effort, ignores not-found)
        deleteForSave(forKey: key)

        // Legacy keychain cleanup is best-effort (may not exist, different error handling)
        deleteFromLegacyKeychain(forKey: key)

        // Use file-based keychain (works without entitlements for CLI tools)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            Log.error(Log.Category.keychain, "Failed to save to keychain: \(status)")
            throw KeychainError.unableToSave(status)
        }

        Log.debug(Log.Category.keychain, "Saved to keychain: \(key)")
    }

    /// Delete from legacy (non-data-protection) keychain
    /// Best-effort deletion - ignores errors since legacy items may not exist
    private static func deleteFromLegacyKeychain(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        // Ignore result - legacy items may not exist
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Delete before save - best-effort, doesn't throw
    /// Used internally by save() to clear existing items before adding new ones
    private static func deleteForSave(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false
        ]
        // Best-effort deletion - item may not exist
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Load data from the Keychain
    /// - Parameter key: The unique key identifying the item
    /// - Returns: The stored data, or nil if not found
    /// - Throws: KeychainError if the operation fails (other than item not found)
    static func load(forKey key: String) throws -> Data? {
        // First try the primary service
        if let data = try loadFromService(service, forKey: key) {
            return data
        }

        // Fall back to legacy services for migration
        for legacyService in legacyServices where legacyService != service {
            if let data = try loadFromService(legacyService, forKey: key) {
                Log.info(Log.Category.keychain, "Found data in legacy service '\(legacyService)', migrating to '\(service)'")
                // Migrate to the primary service
                try? save(data, forKey: key)
                return data
            }
        }

        return nil
    }

    /// Internal helper to load from a specific service
    /// Uses file-based keychain (works without entitlements for CLI tools)
    private static func loadFromService(_ serviceName: String, forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: false
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unableToLoad(status)
        }

        return result as? Data
    }

    /// Delete data from the Keychain
    /// - Parameter key: The unique key identifying the item
    /// - Throws: KeychainError if the operation fails
    /// Uses file-based keychain (works without entitlements for CLI tools)
    static func delete(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status)
        }
    }

    // MARK: - Convenience Methods for Codable Types

    /// Save a Codable object to the Keychain
    /// - Parameters:
    ///   - object: The Codable object to store
    ///   - key: The unique key to identify this item
    /// - Throws: KeychainError or encoding errors
    static func save<T: Encodable>(_ object: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(object)
        try save(data, forKey: key)
    }

    /// Load a Codable object from the Keychain
    /// - Parameter key: The unique key identifying the item
    /// - Returns: The decoded object, or nil if not found
    /// - Throws: KeychainError or decoding errors
    static func load<T: Decodable>(forKey key: String) throws -> T? {
        guard let data = try load(forKey: key) else {
            return nil
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Non-Throwing Convenience Variants

    /// Save a Codable object to the Keychain, swallowing errors.
    /// - Parameters:
    ///   - object: The Codable object to store
    ///   - key: The unique key to identify this item
    /// - Returns: true if saved successfully, false if encoding or save failed
    @discardableResult
    static func saveOptional<T: Encodable>(_ object: T, forKey key: String) -> Bool {
        guard let data = try? JSONEncoder().encode(object) else {
            return false
        }
        return (try? save(data, forKey: key)) != nil
    }

    /// Load a Codable object from the Keychain, swallowing errors.
    /// - Parameter key: The unique key identifying the item
    /// - Returns: The decoded object, or nil if not found or on any error
    static func loadOptional<T: Decodable>(forKey key: String) -> T? {
        guard let data = try? load(forKey: key) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - String Convenience

    /// Save a string to the Keychain
    /// - Parameters:
    ///   - string: The string to store
    ///   - key: The unique key to identify this item
    /// - Throws: KeychainError if the operation fails
    static func save(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }
        try save(data, forKey: key)
    }

    /// Load a string from the Keychain
    /// - Parameter key: The unique key identifying the item
    /// - Returns: The stored string, or nil if not found
    /// - Throws: KeychainError if the operation fails
    static func loadString(forKey key: String) throws -> String? {
        guard let data = try load(forKey: key) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Account-Specific Keys

    /// Generate a Keychain key for storing cookies for a specific account
    /// - Parameter accountId: The account's UUID
    /// - Returns: A unique key string for the account's cookies
    static func cookiesKey(for accountId: UUID) -> String {
        return "cookies_\(accountId.uuidString)"
    }

    /// Generate a Keychain key for storing an API token for a specific account
    /// - Parameter accountId: The account's UUID
    /// - Returns: A unique key string for the account's API token
    static func apiTokenKey(for accountId: UUID) -> String {
        return "apiToken_\(accountId.uuidString)"
    }

    /// Generate a Keychain key for storing an OAuth token for a specific account
    /// - Parameter accountId: The account's UUID
    /// - Returns: A unique key string for the account's OAuth token
    static func oauthTokenKey(for accountId: UUID) -> String {
        return "oauthToken_\(accountId.uuidString)"
    }

    /// Generate a Keychain key for storing an OAuth refresh token for a specific account
    /// - Parameter accountId: The account's UUID
    /// - Returns: A unique key string for the account's OAuth refresh token
    static func oauthRefreshTokenKey(for accountId: UUID) -> String {
        return "oauthRefreshToken_\(accountId.uuidString)"
    }

    /// Delete all Keychain items for this app's service.
    /// Uses file-based keychain (works without entitlements for CLI tools)
    ///
    /// Note: SecItemDelete cannot report the actual count of deleted items.
    /// - Returns: Status indicator: 1 = deletion succeeded, 0 = no items found, -1 = error
    @discardableResult
    static func deleteAll() -> Int {
        // Query to find all items for our service (file-based keychain)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecUseDataProtectionKeychain as String: false
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess {
            Log.info(Log.Category.keychain, "Deleted all keychain items for service")
            return 1
        } else if status == errSecItemNotFound {
            Log.info(Log.Category.keychain, "No keychain items found to delete")
            return 0
        } else {
            Log.error(Log.Category.keychain, "Failed to delete keychain items: \(status)")
            return -1
        }
    }
}
