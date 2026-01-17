import Foundation
import os

/// Errors that can occur when tracking Google Antigravity usage.
enum AntigravityTrackerError: Error, LocalizedError {
    /// Antigravity IDE not running
    case ideNotRunning
    /// Could not find the language server port
    case portNotFound
    /// Could not extract CSRF token from process
    case csrfTokenNotFound
    /// Quota fetch failed
    case quotaFetchFailed(Error)
    /// Invalid response from API
    case invalidResponse(String)
    /// Network request failed
    case networkError(Error)
    /// HTTP error with status code
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .ideNotRunning:
            "Antigravity IDE is not running. Please start Antigravity first."
        case .portNotFound:
            "Could not find Antigravity language server port."
        case .csrfTokenNotFound:
            "Could not extract CSRF token from Antigravity process."
        case let .quotaFetchFailed(error):
            "Failed to fetch quota: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid API response: \(message)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .httpError(statusCode):
            "HTTP error (status \(statusCode))"
        }
    }
}

// MARK: - Antigravity Response Models

/// Quota information from Antigravity GetUserStatus response
struct AntigravityQuotaInfo: Codable {
    let remainingFraction: Double?
    let resetTime: String?
}

/// Model quota from Antigravity GetUserStatus response
struct AntigravityModelQuota: Codable {
    let modelId: String?
    let quotaInfo: AntigravityQuotaInfo?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case quotaInfo = "quota_info"
    }
}

/// GetUserStatus response structure
private struct AntigravityUserStatusResponse: Codable {
    let quotas: [AntigravityModelQuota]?
    let tier: String?
    let email: String?
}

/// Usage information for an Antigravity account.
struct AntigravityUsageInfo {
    /// Usage percentage (0.0-1.0) calculated from remainingFraction
    let sessionPercentage: Double
    /// Weekly usage percentage (mirrors session for Antigravity)
    let weeklyPercentage: Double
    /// Remaining quota fraction (0.0-1.0)
    let remainingFraction: Double
    /// Reset time as display string
    let resetTime: String?
    /// Model name (e.g., "claude-sonnet", "gemini-pro")
    let modelName: String?
    /// Tier: "Free", "Pro", etc.
    let tier: String
    /// All model quotas returned
    let allQuotas: [AntigravityModelQuota]
}

/// Service for fetching Google Antigravity IDE usage statistics.
/// Probes the local Antigravity language server to get quota information.
/// Requires Antigravity IDE to be running locally.
///
/// Thread-safety: All properties are immutable after initialization.
/// Async methods use URLSession which is internally thread-safe.
final class AntigravityTrackerService: Sendable {
    private let category = "AntigravityTracker"

    init() {}

    // MARK: - Public Methods

    /// Check if Antigravity IDE is running
    var isRunning: Bool {
        findAntigravityProcess() != nil
    }

    /// Fetch usage quota from local Antigravity language server.
    /// - Returns: Usage information
    /// - Throws: AntigravityTrackerError on failure
    func fetchUsage() async throws -> AntigravityUsageInfo {
        // Step 1: Find Antigravity process and extract CSRF token
        guard let processInfo = findAntigravityProcess() else {
            throw AntigravityTrackerError.ideNotRunning
        }

        guard let csrfToken = processInfo.csrfToken else {
            throw AntigravityTrackerError.csrfTokenNotFound
        }

        // Step 2: Find the language server port
        guard let port = try await findLanguageServerPort(pid: processInfo.pid) else {
            throw AntigravityTrackerError.portNotFound
        }

        Log.debug(category, "Found Antigravity on port \(port) with CSRF token: \(Log.sanitize(csrfToken))")

        // Step 3: Call GetUserStatus RPC
        let userStatus = try await fetchUserStatus(port: port, csrfToken: csrfToken)

        // Step 4: Parse and return usage info
        return parseUsageInfo(from: userStatus)
    }

    // MARK: - Process Discovery

    /// Information about a running Antigravity process
    private struct ProcessInfo {
        let pid: Int
        let csrfToken: String?
    }

    /// Find the Antigravity process and extract CSRF token from arguments
    private func findAntigravityProcess() -> ProcessInfo? {
        // Run ps to find Antigravity process (with timeout)
        guard let output = ProcessHelper.runAndGetOutput(
            executablePath: "/bin/ps",
            arguments: ["-ax", "-o", "pid,args"]
        ) else {
            Log.error(category, "Failed to run ps command")
            return nil
        }

        // Look for Antigravity language server process
        // Pattern: "Antigravity" or "antigravity" with --csrf_token flag
        for line in output.components(separatedBy: "\n") {
            let lowercaseLine = line.lowercased()
            if lowercaseLine.contains("antigravity") || lowercaseLine.contains("windsurf") {
                // Extract PID
                let components = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard let pidStr = components.first,
                      let pid = Int(pidStr) else { continue }

                // Extract CSRF token from command line arguments
                // Supports multiple formats:
                // - --csrf_token VALUE
                // - --csrf-token VALUE
                // - --csrf_token=VALUE
                // - --csrf-token=VALUE
                var csrfToken: String?

                // Try patterns with space separator
                let csrfPatterns = ["--csrf_token", "--csrf-token"]
                for pattern in csrfPatterns {
                    if csrfToken != nil { break }

                    if let csrfRange = line.range(of: pattern) {
                        let afterCsrf = line[csrfRange.upperBound...]

                        // Check for = format first (--csrf_token=VALUE)
                        if afterCsrf.hasPrefix("=") {
                            let valueStart = afterCsrf.index(after: afterCsrf.startIndex)
                            let remainingValue = String(afterCsrf[valueStart...])
                            let tokenValue = remainingValue.components(separatedBy: .whitespaces).first ?? ""
                            if !tokenValue.isEmpty {
                                csrfToken = tokenValue
                            }
                        } else {
                            // Space separator format (--csrf_token VALUE)
                            let tokenComponents = afterCsrf.trimmingCharacters(in: .whitespaces)
                                .components(separatedBy: .whitespaces)
                            if let token = tokenComponents.first, !token.isEmpty {
                                csrfToken = token
                            }
                        }
                    }
                }

                Log.debug(category, "Found Antigravity process PID: \(pid)")
                return ProcessInfo(pid: pid, csrfToken: csrfToken)
            }
        }

        return nil
    }

    /// Find the language server port using lsof
    private func findLanguageServerPort(pid: Int) async throws -> Int? {
        // Run lsof with timeout to find listening ports
        if let output = ProcessHelper.runAndGetOutput(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-p", String(pid)]
        ) {
            // Parse lsof output for listening ports
            // Format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
            // NAME column contains: *:PORT or 127.0.0.1:PORT
            for line in output.components(separatedBy: "\n") {
                if line.contains("LISTEN") {
                    // Extract port from the NAME column (last column)
                    let components = line.split(separator: " ")
                    if let lastComponent = components.last {
                        let portStr = String(lastComponent)
                        // Port is after the colon
                        if let colonIndex = portStr.lastIndex(of: ":") {
                            let portPart = String(portStr[portStr.index(after: colonIndex)...])
                            if let port = Int(portPart) {
                                // Prefer ports in typical range for language servers
                                if port > 1024, port < 65535 {
                                    return port
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fallback: try common ports
        let commonPorts = [3000, 8080, 8081, 9000, 9001, 45678]
        for port in commonPorts {
            if await probePort(port) {
                return port
            }
        }

        return nil
    }

    /// Probe a port to see if Antigravity language server is listening
    private func probePort(_ port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/health") else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            // Port not responding
        }

        return false
    }

    // MARK: - API Calls

    /// Fetch user status from the language server
    private func fetchUserStatus(port: Int, csrfToken: String) async throws -> AntigravityUserStatusResponse {
        // The Antigravity language server uses gRPC-web style HTTP/JSON
        guard let url = URL(string: "http://127.0.0.1:\(port)/exa.language_server_pb.LanguageServerService/GetUserStatus")
        else {
            throw AntigravityTrackerError.invalidResponse("Invalid URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.httpBody = "{}".data(using: .utf8) // Empty request body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AntigravityTrackerError.invalidResponse("Non-HTTP response")
            }

            guard httpResponse.statusCode == 200 else {
                throw AntigravityTrackerError.httpError(statusCode: httpResponse.statusCode)
            }

            // Debug: log response structure without sensitive data
            // Note: Avoiding full response logging as it may contain email and quota details
            Log.debug(category, "GetUserStatus response received (\(data.count) bytes)")

            return try JSONDecoder().decode(AntigravityUserStatusResponse.self, from: data)
        } catch let error as AntigravityTrackerError {
            throw error
        } catch {
            throw AntigravityTrackerError.networkError(error)
        }
    }

    // MARK: - Response Parsing

    /// Parse usage info from the user status response
    private func parseUsageInfo(from response: AntigravityUserStatusResponse) -> AntigravityUsageInfo {
        // Find the quota with the lowest remaining fraction (most used)
        let allQuotas = response.quotas ?? []
        let lowestQuota = allQuotas.min(by: {
            ($0.quotaInfo?.remainingFraction ?? 1.0) < ($1.quotaInfo?.remainingFraction ?? 1.0)
        })

        let remainingFraction = lowestQuota?.quotaInfo?.remainingFraction ?? 1.0
        let sessionPercentage = 1.0 - remainingFraction

        // Format reset time
        let resetDisplay: String?
        if let resetTime = lowestQuota?.quotaInfo?.resetTime {
            resetDisplay = formatResetTime(resetTime)
        } else {
            resetDisplay = nil
        }

        let tier = response.tier ?? "Unknown"
        let modelName = lowestQuota?.modelId

        Log.info(
            category,
            "Antigravity usage: \(Int(sessionPercentage * 100))% used, tier: \(tier), model: \(modelName ?? "unknown")"
        )

        return AntigravityUsageInfo(
            sessionPercentage: sessionPercentage,
            weeklyPercentage: sessionPercentage, // Antigravity doesn't have separate weekly
            remainingFraction: remainingFraction,
            resetTime: resetDisplay,
            modelName: modelName,
            tier: tier,
            allQuotas: allQuotas
        )
    }

    /// Format reset time from ISO-8601 or epoch to display string
    private func formatResetTime(_ resetTime: String) -> String {
        // Try parsing as ISO-8601
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = isoFormatter.date(from: resetTime) {
            return DateFormattingHelper.formatTimeRemaining(date)
        }

        // Try parsing as epoch seconds
        if let epochSeconds = Double(resetTime) {
            let date = Date(timeIntervalSince1970: epochSeconds)
            return DateFormattingHelper.formatTimeRemaining(date)
        }

        // Return as-is if parsing fails
        return resetTime
    }
}
