import Foundation

/// A simple cache for storing usage data to provide offline resilience.
/// Stores the last successful fetch for each account.
actor UsageCache {
    /// Shared singleton instance
    static let shared = UsageCache()

    /// Cache entry with timestamp
    private struct CacheEntry: Codable {
        let usageData: UsageData
        let timestamp: Date

        /// Age of this cache entry in seconds
        var age: TimeInterval {
            Date().timeIntervalSince(timestamp)
        }

        /// Whether this entry is considered stale (older than threshold)
        func isStale(threshold: TimeInterval) -> Bool {
            age > threshold
        }
    }

    /// In-memory cache keyed by account ID
    private var cache: [UUID: CacheEntry] = [:]

    /// Default cache duration (5 minutes)
    private let defaultCacheThreshold: TimeInterval = 300

    /// File URL for persistent cache
    private var cacheFileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("usage_cache.json")
    }

    private init() {
        Task { await self.loadFromDisk() }
    }

    // MARK: - Public API

    /// Stores usage data for an account
    /// - Parameters:
    ///   - usageData: The usage data to cache
    ///   - accountId: The account's UUID
    func set(_ usageData: UsageData, for accountId: UUID) {
        let entry = CacheEntry(usageData: usageData, timestamp: Date())
        cache[accountId] = entry
        saveToDisk()
    }

    /// Retrieves cached usage data for an account
    /// - Parameter accountId: The account's UUID
    /// - Returns: The cached usage data if available and not stale
    func get(for accountId: UUID) -> UsageData? {
        guard let entry = cache[accountId] else { return nil }

        // Return data if not stale
        if !entry.isStale(threshold: defaultCacheThreshold) {
            return entry.usageData
        }
        return nil
    }

    /// Retrieves the last known usage data regardless of age
    /// Useful when network is unavailable
    /// - Parameter accountId: The account's UUID
    /// - Returns: The last known usage data, may be stale
    func getLastKnown(for accountId: UUID) -> (data: UsageData, isStale: Bool)? {
        guard let entry = cache[accountId] else { return nil }
        return (entry.usageData, entry.isStale(threshold: defaultCacheThreshold))
    }

    /// Invalidates the cache for an account
    /// - Parameter accountId: The account's UUID
    func invalidate(for accountId: UUID) {
        cache.removeValue(forKey: accountId)
        saveToDisk()
    }

    /// Invalidates all cached data
    func invalidateAll() {
        cache.removeAll()
        saveToDisk()
    }

    /// Returns the age of the cached data in seconds
    /// - Parameter accountId: The account's UUID
    /// - Returns: Age in seconds, or nil if not cached
    func age(for accountId: UUID) -> TimeInterval? {
        cache[accountId]?.age
    }

    // MARK: - Persistence

    private func saveToDisk() {
        guard let url = cacheFileURL else { return }

        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url)
        } catch {
            Log.error(Log.Category.cache, "Failed to save cache: \(error)")
        }
    }

    private func loadFromDisk() {
        guard let url = cacheFileURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            cache = try JSONDecoder().decode([UUID: CacheEntry].self, from: data)
            Log.debug(Log.Category.cache, "Loaded \(cache.count) cached entries")
        } catch {
            Log.error(Log.Category.cache, "Failed to load cache: \(error)")
        }
    }
}
