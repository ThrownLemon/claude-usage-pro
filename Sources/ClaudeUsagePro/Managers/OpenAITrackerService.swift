import Foundation
import os

/// Errors that can occur when tracking OpenAI API usage.
enum OpenAITrackerError: Error, LocalizedError {
    /// Admin API key not found
    case apiKeyNotFound
    /// Invalid API key format
    case invalidApiKeyFormat
    /// Usage fetch failed
    case usageFetchFailed(Error)
    /// Invalid response from API
    case invalidResponse(String)
    /// Network request failed
    case networkError(Error)
    /// HTTP error with status code
    case httpError(statusCode: Int, message: String?)
    /// Unauthorized - API key lacks admin permissions
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .apiKeyNotFound:
            "OpenAI Admin API key not found."
        case .invalidApiKeyFormat:
            "Invalid API key format. Admin API keys start with 'sk-admin-'."
        case let .usageFetchFailed(error):
            "Failed to fetch usage: \(error.localizedDescription)"
        case let .invalidResponse(message):
            "Invalid API response: \(message)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .httpError(statusCode, message):
            "HTTP error (\(statusCode)): \(message ?? "Unknown error")"
        case .unauthorized:
            "Unauthorized. Admin API key required (only available to Organization Owners)."
        }
    }
}

// MARK: - OpenAI API Response Models

/// Usage bucket from OpenAI Usage API response
private struct OpenAIUsageBucket: Codable {
    let startTime: Int
    let endTime: Int
    let results: [UsageResult]

    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case results
    }

    struct UsageResult: Codable {
        let object: String?
        let inputTokens: Int?
        let outputTokens: Int?
        let numModelRequests: Int?
        let projectId: String?
        let userId: String?
        let apiKeyId: String?
        let model: String?
        let inputCachedTokens: Int?
        let inputAudioTokens: Int?
        let outputAudioTokens: Int?

        enum CodingKeys: String, CodingKey {
            case object
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case numModelRequests = "num_model_requests"
            case projectId = "project_id"
            case userId = "user_id"
            case apiKeyId = "api_key_id"
            case model
            case inputCachedTokens = "input_cached_tokens"
            case inputAudioTokens = "input_audio_tokens"
            case outputAudioTokens = "output_audio_tokens"
        }
    }
}

/// Usage API response from OpenAI
private struct OpenAIUsageResponse: Codable {
    let object: String?
    let data: [OpenAIUsageBucket]?
    let hasMore: Bool?
    let nextPage: String?

    enum CodingKeys: String, CodingKey {
        case object
        case data
        case hasMore = "has_more"
        case nextPage = "next_page"
    }
}

/// Organization info response from OpenAI
private struct OpenAIOrgResponse: Codable {
    let object: String?
    let id: String?
    let name: String?
    let title: String?
    let description: String?
}

/// Usage information for an OpenAI API account.
struct OpenAIUsageInfo {
    /// Total tokens used in the current period
    let tokensUsed: Int
    /// Input tokens used
    let inputTokens: Int
    /// Output tokens used
    let outputTokens: Int
    /// Number of API requests
    let requestCount: Int
    /// Estimated cost in dollars (based on public pricing)
    let estimatedCost: Double
    /// Organization name
    let orgName: String?
    /// Time period start (Unix timestamp)
    let periodStart: Int
    /// Time period end (Unix timestamp)
    let periodEnd: Int
}

/// Service for fetching OpenAI API usage statistics.
/// Requires an Admin API key (sk-admin-xxx format), which is only available to Organization Owners.
///
/// Thread-safety: All properties are immutable after initialization.
/// Async methods use URLSession which is internally thread-safe.
final class OpenAITrackerService: Sendable {
    private let category = "OpenAITracker"

    // API endpoints (centralized in Constants)
    private let usageBaseURL = Constants.OpenAIAPI.usageBaseURL
    private let orgURL = Constants.OpenAIAPI.orgURL

    init() {}

    // MARK: - Public Methods

    /// Validates an Admin API key format.
    /// - Parameter apiKey: The API key to validate
    /// - Returns: true if the key has a valid admin format
    func isValidAdminKeyFormat(_ apiKey: String) -> Bool {
        // Admin API keys typically start with "sk-admin-"
        // Regular API keys start with "sk-" but not "sk-admin-"
        apiKey.hasPrefix("sk-admin-") && apiKey.count > 20
    }

    /// Fetch usage from OpenAI API.
    /// - Parameter adminApiKey: OpenAI Admin API key
    /// - Returns: Usage information
    /// - Throws: OpenAITrackerError on failure
    func fetchUsage(adminApiKey: String) async throws -> OpenAIUsageInfo {
        // Calculate time range (last 30 days)
        let now = Int(Date().timeIntervalSince1970)
        let thirtyDaysAgo = now - (30 * 24 * 60 * 60)

        // Fetch completions usage
        let completionsUsage = try await fetchCompletionsUsage(
            adminApiKey: adminApiKey,
            startTime: thirtyDaysAgo,
            endTime: now
        )

        // Fetch organization info
        let orgName = await fetchOrgName(adminApiKey: adminApiKey)

        // Calculate totals
        var totalInputTokens = 0
        var totalOutputTokens = 0
        var totalRequests = 0

        for bucket in completionsUsage {
            for result in bucket.results {
                totalInputTokens += result.inputTokens ?? 0
                totalOutputTokens += result.outputTokens ?? 0
                totalRequests += result.numModelRequests ?? 0
            }
        }

        let totalTokens = totalInputTokens + totalOutputTokens

        // Estimate cost (rough approximation based on GPT-4 pricing)
        // This is a simplified estimate - actual costs vary by model
        let estimatedCost = estimateCost(inputTokens: totalInputTokens, outputTokens: totalOutputTokens)

        Log.info(
            category,
            "OpenAI usage: \(totalTokens) tokens, \(totalRequests) requests, ~$\(String(format: "%.4f", estimatedCost))"
        )

        return OpenAIUsageInfo(
            tokensUsed: totalTokens,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            requestCount: totalRequests,
            estimatedCost: estimatedCost,
            orgName: orgName,
            periodStart: thirtyDaysAgo,
            periodEnd: now
        )
    }

    // MARK: - Private Methods

    /// Fetch completions usage from the API, handling pagination
    private func fetchCompletionsUsage(
        adminApiKey: String,
        startTime: Int,
        endTime: Int
    ) async throws -> [OpenAIUsageBucket] {
        var allBuckets: [OpenAIUsageBucket] = []
        var nextPage: String?
        let maxPages = 100 // Safety limit to prevent infinite loops

        for pageCount in 0 ..< maxPages {
            guard var urlComponents = URLComponents(string: "\(usageBaseURL)/completions") else {
                throw OpenAITrackerError.invalidResponse("Invalid base URL")
            }

            var queryItems = [
                URLQueryItem(name: "start_time", value: String(startTime)),
                URLQueryItem(name: "end_time", value: String(endTime)),
                URLQueryItem(name: "bucket_width", value: "1d"), // Daily buckets
            ]

            // Add pagination parameter if we have a next page cursor
            if let page = nextPage {
                queryItems.append(URLQueryItem(name: "page", value: page))
            }

            urlComponents.queryItems = queryItems

            guard let url = urlComponents.url else {
                throw OpenAITrackerError.invalidResponse("Invalid URL")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
            request.setValue("Bearer \(adminApiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAITrackerError.invalidResponse("Non-HTTP response")
                }

                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw OpenAITrackerError.unauthorized
                }

                guard httpResponse.statusCode == 200 else {
                    let errorMessage = String(data: data, encoding: .utf8)
                    throw OpenAITrackerError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
                }

                // Debug: log raw response (only first page to avoid spam)
                if pageCount == 0, let responseStr = String(data: data, encoding: .utf8) {
                    Log.debug(category, "Usage response: \(responseStr.prefix(500))")
                }

                let usageResponse = try JSONDecoder().decode(OpenAIUsageResponse.self, from: data)

                // Append this page's data
                if let buckets = usageResponse.data {
                    allBuckets.append(contentsOf: buckets)
                }

                // Check if there are more pages
                if usageResponse.hasMore == true, let page = usageResponse.nextPage {
                    nextPage = page
                    Log.debug(category, "Fetching next page of usage data (page \(pageCount + 2))")
                } else {
                    // No more pages
                    break
                }

            } catch let error as OpenAITrackerError {
                throw error
            } catch {
                throw OpenAITrackerError.networkError(error)
            }
        }

        return allBuckets
    }

    /// Fetch organization name
    private func fetchOrgName(adminApiKey: String) async -> String? {
        guard let url = URL(string: orgURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Constants.Timeouts.networkRequestTimeout
        request.setValue("Bearer \(adminApiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            let orgResponse = try JSONDecoder().decode(OpenAIOrgResponse.self, from: data)
            return orgResponse.name ?? orgResponse.title

        } catch {
            Log.warning(category, "Failed to fetch org name: \(error)")
            return nil
        }
    }

    /// Estimate cost based on token usage.
    /// WARNING: These are approximate prices as of May 2025 and will become outdated.
    /// OpenAI frequently updates pricing. Check https://openai.com/pricing for current rates.
    /// This estimate uses a weighted average across common models (GPT-4, GPT-4o, etc.)
    /// Actual costs may vary significantly based on specific models used.
    private func estimateCost(inputTokens: Int, outputTokens: Int) -> Double {
        // Approximate pricing (varies by model, this is a rough average as of May 2025)
        // GPT-4 Turbo: $10/1M input, $30/1M output
        // GPT-4o: $5/1M input, $15/1M output
        // GPT-4o-mini: $0.15/1M input, $0.60/1M output
        // Using a middle-ground estimate weighted toward GPT-4o
        // TODO: Consider fetching model-specific usage and applying per-model pricing
        let inputCostPer1M = 7.5 // $7.50 per 1M input tokens (approximate average)
        let outputCostPer1M = 22.5 // $22.50 per 1M output tokens (approximate average)

        let inputCost = Double(inputTokens) / 1_000_000 * inputCostPer1M
        let outputCost = Double(outputTokens) / 1_000_000 * outputCostPer1M

        return inputCost + outputCost
    }
}
