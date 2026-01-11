import Foundation
import os

/// Errors that can occur when tracking GLM Coding Plan usage.
enum GLMTrackerError: Error, LocalizedError {
    /// API token not provided
    case tokenNotFound
    /// Network request failed
    case fetchFailed(Error)
    /// Response is not an HTTPURLResponse
    case nonHTTPResponse
    /// Server returned non-200 status code
    case badResponse(statusCode: Int)
    /// Failed to parse JSON response
    case invalidJSONResponse(Error)
    /// API URL is malformed
    case invalidAPIURL

    var errorDescription: String? {
        switch self {
        case .tokenNotFound:
            return "GLM API token not found."
        case .fetchFailed(let error):
            return "Failed to fetch usage: \(error.localizedDescription)"
        case .nonHTTPResponse:
            return "Received a non-HTTP response from the server."
        case .badResponse(let statusCode):
            return "Received an invalid server response (Status Code: \(statusCode))."
        case .invalidJSONResponse(let error):
            return "Failed to parse the JSON response: \(error.localizedDescription)"
        case .invalidAPIURL:
            return "The API endpoint URL is invalid."
        }
    }
}

// MARK: - GLM API Response Models

private struct GLMUsageResponse: Codable {
    let code: Int?
    let msg: String?
    let data: GLMUsageData?
}

private struct GLMUsageData: Codable {
    let limits: [GLMLimitItem]?
}

private struct GLMLimitItem: Codable {
    let type: String
    let percentage: Double?
    let currentValue: Double?
    let total: Double?
    let usageDetails: [GLMUsageDetail]?
    let usage: Double?
}

private struct GLMUsageDetail: Codable {
    let currentValue: Double?
    let total: Double?
}


/// Usage information for a GLM Coding Plan account.
struct GLMUsageInfo {
    /// Usage percentage for the 5-hour rolling window
    let sessionPercentage: Double
    /// Usage percentage for the monthly limit
    let monthlyPercentage: Double
    /// Tokens used in current 5-hour window
    let sessionUsed: Double
    /// Token limit for 5-hour window
    let sessionLimit: Double
    /// Tokens used this month
    let monthlyUsed: Double
    /// Monthly token limit
    let monthlyLimit: Double

    /// Format session reset display based on remaining time in the 5-hour rolling window
    static func formatSessionResetDisplay(sessionPercentage: Double) -> String {
        let sessionRemainingHours = (1.0 - sessionPercentage) * Constants.GLM.sessionWindowHours
        let hours = Int(sessionRemainingHours)
        let minutes = Int((sessionRemainingHours - Double(hours)) * 60)

        if hours > 0 && minutes > 0 {
            return String(format: "Resets in %dh %dm", hours, minutes)
        } else if hours > 0 {
            return String(format: "Resets in %dh", hours)
        } else if minutes > 0 {
            return String(format: "Resets in %dm", minutes)
        } else {
            return "Resets in <1m"
        }
    }

    /// Format weekly/monthly reset display showing usage vs limit
    static func formatMonthlyResetDisplay(monthlyUsed: Double, monthlyLimit: Double, monthlyPercentage: Double) -> String {
        return monthlyLimit > 0
            ? String(format: "%.0f / %.0f", monthlyUsed, monthlyLimit)
            : String(format: "%.1f%%", monthlyPercentage * 100)
    }
}

/// Service for fetching GLM Coding Plan usage statistics from the Zhipu AI API.
/// Marked @unchecked Sendable because all properties are immutable after init
/// and async methods use only URLSession.shared which is itself Sendable.
final class GLMTrackerService: @unchecked Sendable {
    private let category = Log.Category.glmTracker
    private let baseURL: String
    private let modelUsageURL: String
    private let toolUsageURL: String
    private let quotaLimitURL: String

    /// Build endpoint URLs for a given base domain
    private static func buildEndpoints(fromDomain domain: String) -> (base: String, model: String, tool: String, quota: String) {
        return (
            base: "\(domain)/api/monitor/usage",
            model: "\(domain)/api/monitor/usage/model-usage",
            tool: "\(domain)/api/monitor/usage/tool-usage",
            quota: "\(domain)/api/monitor/usage/quota/limit"
        )
    }

    /// Extract base domain from URL string, returns nil if parsing fails
    private static func extractBaseDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let host = url.host else { return nil }
        return "\(url.scheme ?? "https")://\(host)"
    }

    init() {
        // Determine platform based on ANTHROPIC_BASE_URL environment variable (like the plugin)
        let anthropicBaseURL = ProcessInfo.processInfo.environment["ANTHROPIC_BASE_URL"] ?? ""
        let defaultDomain = "https://open.bigmodel.cn"

        let domain: String
        if anthropicBaseURL.contains("api.z.ai") {
            domain = Self.extractBaseDomain(from: anthropicBaseURL) ?? "https://api.z.ai"
        } else if anthropicBaseURL.contains("open.bigmodel.cn") || anthropicBaseURL.contains("dev.bigmodel.cn") {
            domain = Self.extractBaseDomain(from: anthropicBaseURL) ?? defaultDomain
        } else {
            domain = defaultDomain
        }

        let endpoints = Self.buildEndpoints(fromDomain: domain)
        baseURL = endpoints.base
        modelUsageURL = endpoints.model
        toolUsageURL = endpoints.tool
        quotaLimitURL = endpoints.quota
    }

    func fetchGLMUsage(apiToken: String) async throws -> GLMUsageInfo {
        // Fetch quota limits which gives us both session (TOKENS_LIMIT) and monthly (TIME_LIMIT) data
        guard let url = URL(string: quotaLimitURL) else {
            throw GLMTrackerError.invalidAPIURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let jsonObject = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            Log.debug(category, "Raw API Response:\n\(prettyString)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            let responseType = type(of: response)
            Log.error(category, "Unexpected response type: \(responseType)")
            throw GLMTrackerError.nonHTTPResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GLMTrackerError.badResponse(statusCode: httpResponse.statusCode)
        }

        do {
            let apiResponse = try JSONDecoder().decode(GLMUsageResponse.self, from: data)

            guard let limits = apiResponse.data?.limits else {
                throw GLMTrackerError.invalidJSONResponse(NSError(domain: "GLMTracker", code: -1, userInfo: [NSLocalizedDescriptionKey: "No limits data in response"]))
            }

            var sessionPercentage: Double = 0
            var sessionUsed: Double = 0
            var sessionLimit: Double = 0
            var monthlyPercentage: Double = 0
            var monthlyUsed: Double = 0
            var monthlyLimit: Double = 0

            for limit in limits {
                switch limit.type {
                case "TOKENS_LIMIT":
                    // 5-hour session limit
                    sessionPercentage = limit.percentage ?? 0
                    if let current = limit.currentValue, let total = limit.total {
                        sessionUsed = current
                        sessionLimit = total
                    } else if let details = limit.usageDetails, !details.isEmpty,
                          let current = details.first?.currentValue, let total = details.first?.total {
                        sessionUsed = current
                        sessionLimit = total
                    }
                case "TIME_LIMIT":
                    // 1-month MCP limit
                    monthlyPercentage = limit.percentage ?? 0
                    if let current = limit.currentValue, let total = limit.total {
                        monthlyUsed = current
                        monthlyLimit = total
                    } else if let usage = limit.usage, let total = limit.total {
                        // When usage field is present, it represents current usage
                        monthlyUsed = usage
                        monthlyLimit = total
                    } else if let usage = limit.usage {
                        // Fallback: if we only have usage without total, estimate limit from percentage
                        monthlyUsed = usage
                        // Safety: require minimum 1% to avoid division by very small values
                        let minPercentage = 1.0  // 1% minimum threshold
                        let maxMonthlyLimit = 1_000_000_000.0  // 1 billion cap for sanity
                        if monthlyPercentage >= minPercentage {
                            let calculatedLimit = usage / (monthlyPercentage / 100.0)
                            // Validate the result is finite and reasonable
                            if calculatedLimit.isFinite && calculatedLimit <= maxMonthlyLimit {
                                monthlyLimit = calculatedLimit
                            } else {
                                Log.warning(category, "Calculated monthlyLimit (\(calculatedLimit)) is invalid, using 0")
                                monthlyLimit = 0
                            }
                        } else {
                            monthlyLimit = 0
                        }
                    } else if let details = limit.usageDetails, !details.isEmpty,
                          let current = details.first?.currentValue, let total = details.first?.total {
                        monthlyUsed = current
                        monthlyLimit = total
                    }
                default:
                    break
                }
            }

            Log.info(category, "Parsed Info - Session: \(sessionUsed)/\(sessionLimit) (\(sessionPercentage)%), Monthly: \(monthlyUsed)/\(monthlyLimit) (\(monthlyPercentage)%)")

            return GLMUsageInfo(
                sessionPercentage: sessionPercentage / 100.0,  // Convert to 0-1 range
                monthlyPercentage: monthlyPercentage / 100.0,
                sessionUsed: sessionUsed,
                sessionLimit: sessionLimit,
                monthlyUsed: monthlyUsed,
                monthlyLimit: monthlyLimit
            )
        } catch {
            throw GLMTrackerError.invalidJSONResponse(error)
        }
    }

    // Additional endpoints from the plugin (for future use)
    func fetchModelUsage(apiToken: String, startTime: Date, endTime: Date) async throws -> Data {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startTimeStr = dateFormatter.string(from: startTime)
        let endTimeStr = dateFormatter.string(from: endTime)

        guard var urlComponents = URLComponents(string: modelUsageURL) else {
            throw GLMTrackerError.invalidAPIURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "startTime", value: startTimeStr),
            URLQueryItem(name: "endTime", value: endTimeStr)
        ]

        guard let url = urlComponents.url else {
            throw GLMTrackerError.invalidAPIURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            let responseType = type(of: response)
            Log.error(category, "Unexpected response type in fetchModelUsage: \(responseType)")
            throw GLMTrackerError.nonHTTPResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GLMTrackerError.badResponse(statusCode: httpResponse.statusCode)
        }

        return data
    }

    func fetchToolUsage(apiToken: String, startTime: Date, endTime: Date) async throws -> Data {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let startTimeStr = dateFormatter.string(from: startTime)
        let endTimeStr = dateFormatter.string(from: endTime)

        guard var urlComponents = URLComponents(string: toolUsageURL) else {
            throw GLMTrackerError.invalidAPIURL
        }

        urlComponents.queryItems = [
            URLQueryItem(name: "startTime", value: startTimeStr),
            URLQueryItem(name: "endTime", value: endTimeStr)
        ]

        guard let url = urlComponents.url else {
            throw GLMTrackerError.invalidAPIURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            let responseType = type(of: response)
            Log.error(category, "Unexpected response type in fetchToolUsage: \(responseType)")
            throw GLMTrackerError.nonHTTPResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GLMTrackerError.badResponse(statusCode: httpResponse.statusCode)
        }

        return data
    }
}
