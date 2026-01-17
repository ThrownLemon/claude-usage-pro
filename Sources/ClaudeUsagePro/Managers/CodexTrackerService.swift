import Foundation
import os

/// Errors that can occur when tracking OpenAI Codex CLI usage.
enum CodexTrackerError: Error, LocalizedError {
    /// Codex CLI not installed
    case cliNotInstalled
    /// Codex CLI credentials not found
    case credentialsNotFound
    /// Auth token not found
    case tokenNotFound
    /// Usage fetch failed
    case usageFetchFailed(Error)
    /// Invalid response from API
    case invalidResponse(String)
    /// Network request failed
    case networkError(Error)
    /// HTTP error with status code
    case httpError(statusCode: Int, message: String?)
    /// CLI command failed
    case cliCommandFailed(String)
    /// User not authenticated
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .cliNotInstalled:
            "Codex CLI is not installed. Install with: npm install -g @openai/codex"
        case .credentialsNotFound:
            "Codex CLI credentials not found. Run 'codex auth' to log in."
        case .tokenNotFound:
            "Codex auth token not found."
        case let .usageFetchFailed(error):
            "Failed to fetch usage: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid response: \(message)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .httpError(statusCode, message):
            "HTTP error (\(statusCode)): \(message ?? "Unknown error")"
        case let .cliCommandFailed(message):
            "CLI command failed: \(message)"
        case .notAuthenticated:
            "Not authenticated. Run 'codex auth' to log in."
        }
    }
}

// MARK: - Codex Auth Models

/// Auth credentials stored by Codex CLI in ~/.codex/auth.json
struct CodexAuthCredentials: Codable {
    let accessToken: String?
    let refreshToken: String?
    let idToken: String?
    let expiresAt: Int64?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresAt = "expires_at"
    }
}

/// Usage information for a Codex CLI account.
struct CodexUsageInfo {
    /// Session messages used (5-hour rolling window)
    let sessionUsed: Int
    /// Session messages limit (5-hour rolling window)
    let sessionLimit: Int
    /// Weekly messages used
    let weeklyUsed: Int
    /// Weekly messages limit
    let weeklyLimit: Int
    /// Plan type: "plus", "pro", "business", "enterprise"
    let planType: String
    /// Session usage percentage (0.0-1.0)
    var sessionPercentage: Double {
        sessionLimit > 0 ? Double(sessionUsed) / Double(sessionLimit) : 0.0
    }
    /// Weekly usage percentage (0.0-1.0)
    var weeklyPercentage: Double {
        weeklyLimit > 0 ? Double(weeklyUsed) / Double(weeklyLimit) : 0.0
    }
    /// Session reset time (approximate, based on 5-hour window)
    let sessionResetTime: String?
    /// Weekly reset time
    let weeklyResetTime: String?
}

/// Service for fetching OpenAI Codex CLI usage statistics.
/// Reads credentials from ~/.codex/auth.json and fetches usage from the CLI or dashboard.
///
/// Thread-safety: All properties are immutable after initialization.
/// Async methods use URLSession which is internally thread-safe.
final class CodexTrackerService: Sendable {
    private let category = "CodexTracker"

    // Paths
    private let authFilePath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/auth.json").path
    }()

    // Known plan limits (messages per time window)
    // These are based on publicly documented limits
    private let planLimits: [String: (session: Int, weekly: Int)] = [
        "plus": (session: 45, weekly: 225),
        "pro": (session: 300, weekly: 1500),
        "business": (session: 600, weekly: 3000),
        "enterprise": (session: 1200, weekly: 6000),
    ]

    init() {}

    // MARK: - Public Methods

    /// Check if Codex CLI is installed
    var isInstalled: Bool {
        // Check for the auth file or the CLI binary
        FileManager.default.fileExists(atPath: authFilePath) || findCodexCLI() != nil
    }

    /// Detect Codex CLI installation and read credentials.
    /// - Returns: Auth credentials if found, nil otherwise
    func detectCodexCLI() -> CodexAuthCredentials? {
        guard FileManager.default.fileExists(atPath: authFilePath) else {
            Log.debug(category, "Codex auth file not found at \(authFilePath)")
            return nil
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: authFilePath))
            let credentials = try JSONDecoder().decode(CodexAuthCredentials.self, from: data)
            Log.debug(
                category,
                "Found Codex CLI credentials (token: \(Log.sanitize(credentials.accessToken)))"
            )
            return credentials
        } catch {
            Log.error(category, "Failed to read Codex credentials: \(error)")
            return nil
        }
    }

    /// Fetch usage from Codex CLI or dashboard.
    /// - Parameter authToken: The auth token (access token from auth.json)
    /// - Returns: Usage information
    /// - Throws: CodexTrackerError on failure
    func fetchUsage(authToken: String) async throws -> CodexUsageInfo {
        // Try to get usage from CLI first
        do {
            return try await fetchUsageFromCLI()
        } catch {
            // Log CLI error but continue to API fallback
            Log.debug(category, "CLI fetch failed, falling back to API: \(error.localizedDescription)")
        }

        // Fall back to fetching from dashboard/API
        return try await fetchUsageFromAPI(authToken: authToken)
    }

    // MARK: - Private Methods

    /// Find the Codex CLI binary path
    private func findCodexCLI() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.npm-global/bin/codex").expandingTildeInPath,
            NSString(string: "~/.bun/bin/codex").expandingTildeInPath,
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // Try to find it via which (with timeout)
        if let path = ProcessHelper.runAndGetOutput(
            executablePath: "/usr/bin/which",
            arguments: ["codex"]
        ), !path.isEmpty {
            return path
        }

        return nil
    }

    /// Fetch usage by running the Codex CLI status command
    private func fetchUsageFromCLI() async throws -> CodexUsageInfo {
        guard let cliPath = findCodexCLI() else {
            throw CodexTrackerError.cliNotInstalled
        }

        do {
            let result = try ProcessHelper.run(
                executablePath: cliPath,
                arguments: ["status", "--json"]
            )

            guard result.exitStatus == 0 else {
                let errorMessage = String(data: result.stderr, encoding: .utf8) ?? "Unknown error"
                throw CodexTrackerError.cliCommandFailed(errorMessage)
            }

            // Parse the JSON output
            guard let output = String(data: result.stdout, encoding: .utf8) else {
                throw CodexTrackerError.invalidResponse("Could not decode CLI output")
            }

            Log.debug(category, "CLI status output: \(output.prefix(500))")

            return try parseCliStatusOutput(output)

        } catch ProcessHelper.ProcessError.timeout {
            throw CodexTrackerError.cliCommandFailed("CLI command timed out")
        } catch let error as CodexTrackerError {
            throw error
        } catch {
            throw CodexTrackerError.cliCommandFailed(error.localizedDescription)
        }
    }

    /// Parse the CLI status JSON output
    private func parseCliStatusOutput(_ output: String) throws -> CodexUsageInfo {
        guard let data = output.data(using: .utf8) else {
            throw CodexTrackerError.invalidResponse("Invalid output encoding")
        }

        // Try to parse as JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexTrackerError.invalidResponse("Invalid JSON output")
        }

        // Extract usage info from JSON
        // The structure may vary, so we try multiple paths
        let usage = json["usage"] as? [String: Any] ?? json
        let limits = json["limits"] as? [String: Any] ?? usage

        let sessionUsed = (usage["session_used"] as? Int) ??
            (usage["sessionUsed"] as? Int) ??
            (usage["current_session"] as? Int) ?? 0

        let sessionLimit = (limits["session_limit"] as? Int) ??
            (limits["sessionLimit"] as? Int) ??
            (limits["session"] as? Int) ?? 45 // Default to Plus plan

        let weeklyUsed = (usage["weekly_used"] as? Int) ??
            (usage["weeklyUsed"] as? Int) ??
            (usage["current_week"] as? Int) ?? 0

        let weeklyLimit = (limits["weekly_limit"] as? Int) ??
            (limits["weeklyLimit"] as? Int) ??
            (limits["weekly"] as? Int) ?? 225 // Default to Plus plan

        let planType = (json["plan"] as? String) ??
            (json["planType"] as? String) ??
            detectPlanFromLimits(sessionLimit: sessionLimit, weeklyLimit: weeklyLimit)

        return CodexUsageInfo(
            sessionUsed: sessionUsed,
            sessionLimit: sessionLimit,
            weeklyUsed: weeklyUsed,
            weeklyLimit: weeklyLimit,
            planType: planType,
            sessionResetTime: nil,
            weeklyResetTime: nil
        )
    }

    /// Fetch usage from the Codex API/dashboard
    private func fetchUsageFromAPI(authToken: String) async throws -> CodexUsageInfo {
        // The Codex dashboard uses the same API as ChatGPT
        // Try to fetch from the settings/usage endpoint
        guard let url = URL(string: Constants.CodexAPI.usageURL) else {
            throw CodexTrackerError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Add user agent to look like a browser
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw CodexTrackerError.invalidResponse("Non-HTTP response")
            }

            if httpResponse.statusCode == 401 {
                throw CodexTrackerError.notAuthenticated
            }

            guard httpResponse.statusCode == 200 else {
                let errorMessage = String(data: data, encoding: .utf8)
                throw CodexTrackerError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            // Debug: log raw response
            if let responseStr = String(data: data, encoding: .utf8) {
                Log.debug(category, "API response: \(responseStr.prefix(500))")
            }

            // Parse the response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexTrackerError.invalidResponse("Invalid JSON response")
            }

            return try parseApiResponse(json)

        } catch let error as CodexTrackerError {
            throw error
        } catch {
            throw CodexTrackerError.networkError(error)
        }
    }

    /// Parse the API response
    private func parseApiResponse(_ json: [String: Any]) throws -> CodexUsageInfo {
        let usage = json["usage"] as? [String: Any] ?? json

        let sessionUsed = (usage["session_count"] as? Int) ??
            (usage["session_used"] as? Int) ?? 0

        let sessionLimit = (usage["session_limit"] as? Int) ?? 45

        let weeklyUsed = (usage["weekly_count"] as? Int) ??
            (usage["weekly_used"] as? Int) ?? 0

        let weeklyLimit = (usage["weekly_limit"] as? Int) ?? 225

        let planType = (json["plan"] as? String) ??
            detectPlanFromLimits(sessionLimit: sessionLimit, weeklyLimit: weeklyLimit)

        let sessionResetTime = usage["session_reset"] as? String
        let weeklyResetTime = usage["weekly_reset"] as? String

        Log.info(
            category,
            "Codex usage: \(sessionUsed)/\(sessionLimit) session, \(weeklyUsed)/\(weeklyLimit) weekly, plan: \(planType)"
        )

        return CodexUsageInfo(
            sessionUsed: sessionUsed,
            sessionLimit: sessionLimit,
            weeklyUsed: weeklyUsed,
            weeklyLimit: weeklyLimit,
            planType: planType,
            sessionResetTime: sessionResetTime,
            weeklyResetTime: weeklyResetTime
        )
    }

    /// Detect plan type from limits
    private func detectPlanFromLimits(sessionLimit: Int, weeklyLimit: Int) -> String {
        for (plan, limits) in planLimits {
            if sessionLimit == limits.session && weeklyLimit == limits.weekly {
                return plan.capitalized
            }
        }
        // If limits are higher than Pro, assume Enterprise
        if sessionLimit >= 600 {
            return "Enterprise"
        } else if sessionLimit >= 300 {
            return "Pro"
        }
        return "Plus"
    }
}
