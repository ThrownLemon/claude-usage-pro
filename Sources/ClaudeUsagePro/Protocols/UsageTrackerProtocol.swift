import Foundation

/// Protocol defining the interface for usage tracking services.
/// All trackers (Claude, Cursor, GLM) should conform to this protocol
/// to provide a unified interface for fetching usage data.
protocol UsageTracker: Sendable {
    /// Fetch current usage data from the service.
    /// - Returns: Usage data normalized to the common UsageData format
    /// - Throws: Service-specific errors if the fetch fails
    func fetchUsage() async throws -> UsageData
}

/// Protocol for trackers that support session ping/wake functionality.
/// Currently only ClaudeTrackerService supports this feature.
protocol SessionPingable {
    /// Ping the session to wake it up and start a new session.
    /// - Returns: True if the ping was successful
    func pingSession() async throws -> Bool
}

/// Configuration required for different tracker types.
/// Used by the factory to create the appropriate tracker instance.
enum TrackerConfiguration {
    case claude(cookies: [[String: String]])
    case cursor
    case glm(apiToken: String)
}

/// Factory for creating tracker instances based on account type.
enum TrackerFactory {
    /// Create a usage tracker for the given configuration.
    /// - Parameter config: The tracker configuration specifying type and credentials
    /// - Returns: A tracker instance conforming to UsageTracker
    @MainActor
    static func create(for config: TrackerConfiguration) -> any UsageTracker {
        switch config {
        case .claude(let cookies):
            return ClaudeTrackerAdapter(cookies: cookies)
        case .cursor:
            return CursorTrackerAdapter()
        case .glm(let apiToken):
            return GLMTrackerAdapter(apiToken: apiToken)
        }
    }
}

// MARK: - Adapter for CursorTrackerService

/// Adapter that wraps CursorTrackerService to conform to UsageTracker protocol.
final class CursorTrackerAdapter: UsageTracker, @unchecked Sendable {
    private let service = CursorTrackerService()

    func fetchUsage() async throws -> UsageData {
        let info = try await service.fetchCursorUsage()

        let sessionPercentage = info.planLimit > 0
            ? Double(info.planUsed) / Double(info.planLimit)
            : 0.0

        return UsageData(
            sessionPercentage: sessionPercentage,
            sessionReset: "Ready",
            sessionResetDisplay: "\(info.planUsed) / \(info.planLimit)",
            weeklyPercentage: 0,
            weeklyReset: "Ready",
            weeklyResetDisplay: "\(info.planUsed) / \(info.planLimit)",
            tier: info.planType ?? "Pro",
            email: info.email,
            fullName: nil,
            orgName: "Cursor",
            planType: info.planType,
            cursorUsed: info.planUsed,
            cursorLimit: info.planLimit
        )
    }
}

// MARK: - Adapter for GLMTrackerService

/// Adapter that wraps GLMTrackerService to conform to UsageTracker protocol.
final class GLMTrackerAdapter: UsageTracker, @unchecked Sendable {
    private let service = GLMTrackerService()
    private let apiToken: String

    init(apiToken: String) {
        self.apiToken = apiToken
    }

    func fetchUsage() async throws -> UsageData {
        let info = try await service.fetchGLMUsage(apiToken: apiToken)

        // Use shared helper methods for consistent formatting
        let sessionResetDisplay = GLMUsageInfo.formatSessionResetDisplay(sessionPercentage: info.sessionPercentage)
        let weeklyResetDisplay = GLMUsageInfo.formatMonthlyResetDisplay(
            monthlyUsed: info.monthlyUsed,
            monthlyLimit: info.monthlyLimit,
            monthlyPercentage: info.monthlyPercentage
        )

        return UsageData(
            sessionPercentage: info.sessionPercentage,
            sessionReset: "Ready",
            sessionResetDisplay: sessionResetDisplay,
            weeklyPercentage: info.monthlyPercentage,
            weeklyReset: "Ready",
            weeklyResetDisplay: weeklyResetDisplay,
            tier: "GLM Coding Plan",
            email: nil,
            fullName: nil,
            orgName: "GLM",
            planType: "Coding Plan",
            glmSessionUsed: info.sessionUsed,
            glmSessionLimit: info.sessionLimit,
            glmMonthlyUsed: info.monthlyUsed,
            glmMonthlyLimit: info.monthlyLimit
        )
    }
}

// MARK: - Adapter for TrackerService (Claude)

/// Error thrown when a fetch is cancelled due to a new concurrent call
enum TrackerAdapterError: Error {
    case fetchCancelled
}

/// Adapter that wraps TrackerService to conform to UsageTracker protocol.
/// This adapter bridges the callback-based TrackerService to async/await.
/// Handles concurrent calls by cancelling previous pending operations.
@MainActor
final class ClaudeTrackerAdapter: UsageTracker, SessionPingable, @unchecked Sendable {
    private let service: TrackerService
    private let cookieProps: [[String: String]]

    // Track pending continuations to prevent leaks on concurrent calls
    private var pendingFetchContinuation: CheckedContinuation<UsageData, Error>?
    private var pendingPingContinuation: CheckedContinuation<Bool, Error>?

    init(cookies: [[String: String]]) {
        self.cookieProps = cookies
        self.service = TrackerService()
    }

    /// Converts stored cookie properties back to HTTPCookie objects
    private var cookies: [HTTPCookie] {
        HTTPCookie.fromCodable(cookieProps)
    }

    nonisolated func fetchUsage() async throws -> UsageData {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: TrackerAdapterError.fetchCancelled)
                    return
                }

                // Cancel any pending fetch continuation before starting new one
                if let pending = self.pendingFetchContinuation {
                    pending.resume(throwing: TrackerAdapterError.fetchCancelled)
                }
                self.pendingFetchContinuation = continuation

                self.service.onUpdate = { [weak self] usageData in
                    guard let self = self else { return }
                    if let pending = self.pendingFetchContinuation {
                        var data = usageData
                        data.sessionResetDisplay = UsageData.formatSessionResetDisplay(usageData.sessionReset)
                        pending.resume(returning: data)
                        self.pendingFetchContinuation = nil
                    }
                }
                self.service.onError = { [weak self] error in
                    guard let self = self else { return }
                    if let pending = self.pendingFetchContinuation {
                        pending.resume(throwing: error)
                        self.pendingFetchContinuation = nil
                    }
                }
                self.service.fetchUsage(cookies: self.cookies)
            }
        }
    }

    nonisolated func pingSession() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: TrackerAdapterError.fetchCancelled)
                    return
                }

                // Cancel any pending ping continuation before starting new one
                if let pending = self.pendingPingContinuation {
                    pending.resume(throwing: TrackerAdapterError.fetchCancelled)
                }
                self.pendingPingContinuation = continuation

                self.service.onPingComplete = { [weak self] success in
                    guard let self = self else { return }
                    if let pending = self.pendingPingContinuation {
                        pending.resume(returning: success)
                        self.pendingPingContinuation = nil
                    }
                }
                self.service.pingSession()
            }
        }
    }
}
