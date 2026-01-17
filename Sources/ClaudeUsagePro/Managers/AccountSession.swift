import Foundation
import os
import SwiftUI

/// Manages a single account's usage monitoring session.
/// Handles periodic fetching, threshold notifications, and auto-wake functionality.
@Observable
@MainActor
class AccountSession: Identifiable {
    private let category = Log.Category.session
    /// Unique identifier matching the associated account's ID
    let id: UUID
    /// The account being monitored
    var account: ClaudeAccount
    /// Whether a fetch operation is currently in progress
    var isFetching: Bool = false
    /// The most recent error encountered during fetching, if any
    var lastError: Error?

    private var previousSessionPercentage: Double?
    private var previousWeeklyPercentage: Double?
    private var hasReceivedFirstUpdate: Bool = false

    private var tracker: TrackerService?
    private var cursorTracker: CursorTrackerService?
    private var glmTracker: GLMTrackerService?
    private var oauthService: AnthropicOAuthService?
    private var geminiTracker: GeminiTrackerService?
    private var antigravityTracker: AntigravityTrackerService?
    private var openaiTracker: OpenAITrackerService?
    private var codexTracker: CodexTrackerService?

    // MARK: - Thread-Safe Timer/Task Management

    // These properties are accessed from both @MainActor context and nonisolated deinit.
    // We use a lock to ensure thread-safe access, even though Timer.invalidate() and
    // Task.cancel() are themselves thread-safe operations.

    /// Lock protecting timer and fetchTask access
    @ObservationIgnored private let resourceLock = NSLock()
    /// Timer for periodic refresh (protected by resourceLock)
    @ObservationIgnored private var _timer: Timer?
    /// Current fetch task (protected by resourceLock)
    @ObservationIgnored private var _fetchTask: Task<Void, Never>?

    /// Thread-safe access to timer
    private var timer: Timer? {
        get { resourceLock.withLock { _timer } }
        set { resourceLock.withLock { _timer = newValue } }
    }

    /// Thread-safe access to fetchTask
    private var fetchTask: Task<Void, Never>? {
        get { resourceLock.withLock { _fetchTask } }
        set { resourceLock.withLock { _fetchTask = newValue } }
    }

    var onRefreshTick: (() -> Void)?

    /// Creates a new session for monitoring an account's usage.
    /// - Parameter account: The account to monitor
    init(account: ClaudeAccount) {
        id = account.id
        self.account = account

        switch account.type {
        case .claude:
            // Prefer OAuth service if available, fall back to WebView tracker
            if account.usesOAuth {
                oauthService = AnthropicOAuthService()
                Log.debug(
                    category,
                    "Using OAuth API for \(account.name) (token: \(Log.sanitize(account.oauthToken)))"
                )
            } else {
                tracker = TrackerService()
                Log.debug(
                    category,
                    "Using WebView tracker for \(account.name) (usesOAuth=false, token=\(account.oauthToken != nil ? "present" : "nil"))"
                )
            }
        case .cursor:
            cursorTracker = CursorTrackerService()
        case .glm:
            glmTracker = GLMTrackerService()
        case .gemini:
            geminiTracker = GeminiTrackerService()
            Log.debug(category, "Using Gemini tracker for \(account.name)")
        case .antigravity:
            antigravityTracker = AntigravityTrackerService()
            Log.debug(category, "Using Antigravity tracker for \(account.name)")
        case .openai:
            openaiTracker = OpenAITrackerService()
            Log.debug(category, "Using OpenAI tracker for \(account.name)")
        case .codex:
            codexTracker = CodexTrackerService()
            Log.debug(category, "Using Codex tracker for \(account.name)")
        }

        setupTracker()
    }

    deinit {
        // Thread-safe cleanup - manual lock/unlock is used here instead of withLock
        // because we need to perform multiple operations atomically (cancel task,
        // invalidate timer, set both to nil). The lock/defer pattern is clearer
        // for grouping these atomic teardown steps in deinit.
        resourceLock.lock()
        defer { resourceLock.unlock() }
        _fetchTask?.cancel()
        _timer?.invalidate()
        _fetchTask = nil
        _timer = nil
    }

    /// Starts monitoring the account's usage with periodic refreshes.
    /// Performs an immediate fetch and schedules recurring updates.
    func startMonitoring() {
        Log.debug(category, "Starting monitoring for \(account.name)")
        fetchNow()
        scheduleRefreshTimer()
    }

    /// Stops monitoring and cancels all pending operations.
    /// Safe to call multiple times.
    func stopMonitoring() {
        Log.debug(category, "Stopping monitoring for \(account.name)")
        fetchTask?.cancel()
        fetchTask = nil
        timer?.invalidate()
        timer = nil
    }

    /// Schedules or reschedules the refresh timer based on user settings.
    func scheduleRefreshTimer() {
        timer?.invalidate()
        let interval = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        let time = interval > 0 ? interval : Constants.Timeouts.defaultRefreshInterval

        timer = Timer.scheduledTimer(withTimeInterval: time, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchNow()
                self?.onRefreshTick?()
            }
        }
    }

    /// Sends a ping to wake up a ready session or trigger minimal usage.
    /// - Parameter isAuto: Whether this is an automatic ping (respects auto-wake setting)
    func ping(isAuto: Bool = false) {
        if isAuto, !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoWakeUp) {
            Log.debug(category, "Auto-ping cancelled (setting disabled)")
            return
        }

        // For Claude accounts, only ping when session is ready
        // For GLM accounts, allow pinging anytime (no "ready" state concept)
        if account.type == .claude {
            guard let usageData = account.usageData,
                  usageData.sessionPercentage == 0,
                  usageData.sessionReset == Constants.Status.ready
            else {
                Log.debug(category, "Ping skipped (session not ready)")
                return
            }
        }

        Log.debug(category, "\(isAuto ? "Auto" : "Manual") ping requested")

        // Use OAuth service for OAuth accounts, TrackerService for cookie-based accounts
        if let oauthService, let token = account.oauthToken {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let success = await oauthService.pingSession(token: token)
                if success {
                    Log.debug(category, "OAuth ping finished, refreshing data...")
                    try? await Task.sleep(for: .seconds(2))
                    fetchNow()
                } else {
                    Log.error(category, "OAuth ping failed")
                }
            }
        } else if let tracker {
            tracker.onPingComplete = { [weak self] success in
                guard let self else { return }
                if success {
                    Log.debug(category, "Ping finished, refreshing data...")
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(2))
                        self?.fetchNow()
                    }
                } else {
                    Log.error(category, "Ping failed")
                }
            }
            tracker.pingSession()
        } else {
            Log.warning(category, "Ping unavailable: no OAuth service or tracker configured")
        }
    }

    /// Immediately fetches usage data for the account.
    /// Cancels any in-progress fetch and starts a new one.
    func fetchNow() {
        guard !isFetching else { return }
        isFetching = true

        // Cancel any previous fetch task
        fetchTask?.cancel()

        switch account.type {
        case .claude:
            if let oauthService, let token = account.oauthToken {
                // Use OAuth API (preferred, faster, more reliable)
                fetchTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let usageData = try await oauthService.fetchUsage(token: token)
                        guard !Task.isCancelled else { return }
                        handleOAuthUsageResult(.success(usageData))
                    } catch {
                        guard !Task.isCancelled else { return }
                        handleOAuthUsageResult(.failure(error))
                    }
                }
            } else {
                // Fall back to WebView-based tracking
                tracker?.fetchUsage(cookies: account.cookies)
            }
        case .cursor:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await cursorTracker?.fetchCursorUsage()
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleCursorUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleCursorUsageResult(.failure(error))
                }
            }
        case .glm:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                guard let apiToken = account.apiToken else {
                    handleGLMUsageResult(.failure(GLMTrackerError.tokenNotFound))
                    return
                }
                do {
                    let info = try await glmTracker?.fetchGLMUsage(apiToken: apiToken)
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleGLMUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleGLMUsageResult(.failure(error))
                }
            }
        case .gemini:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                guard let accessToken = account.geminiAccessToken else {
                    handleGeminiUsageResult(.failure(GeminiTrackerError.credentialsNotFound))
                    return
                }

                do {
                    // Check if token needs refresh
                    if let expiry = account.geminiTokenExpiry, expiry < Date(),
                       let refreshToken = account.geminiRefreshToken
                    {
                        Log.info(category, "Gemini token expired, attempting refresh")
                        let newTokens = try await geminiTracker?.refreshToken(refreshToken: refreshToken)
                        if let newTokens {
                            // Update account with new tokens
                            account.geminiAccessToken = newTokens.accessToken
                            account.geminiIdToken = newTokens.idToken
                            if let expiry = newTokens.expiryDate {
                                account.geminiTokenExpiry = Date(timeIntervalSince1970: Double(expiry) / 1000.0)
                            }
                            if !account.saveCredentialsToKeychain() {
                                Log.warning(category, "Failed to save refreshed Gemini credentials to Keychain")
                            }
                        }
                    }

                    let currentToken = account.geminiAccessToken ?? accessToken
                    let info = try await geminiTracker?.fetchUsage(accessToken: currentToken)
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleGeminiUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleGeminiUsageResult(.failure(error))
                }
            }
        case .antigravity:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await antigravityTracker?.fetchUsage()
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleAntigravityUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleAntigravityUsageResult(.failure(error))
                }
            }
        case .openai:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                guard let adminApiKey = account.openaiAdminApiKey else {
                    handleOpenAIUsageResult(.failure(OpenAITrackerError.apiKeyNotFound))
                    return
                }
                do {
                    let info = try await openaiTracker?.fetchUsage(adminApiKey: adminApiKey)
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleOpenAIUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleOpenAIUsageResult(.failure(error))
                }
            }
        case .codex:
            fetchTask = Task { [weak self] in
                guard let self else { return }
                guard let authToken = account.codexAuthToken else {
                    handleCodexUsageResult(.failure(CodexTrackerError.tokenNotFound))
                    return
                }
                do {
                    let info = try await codexTracker?.fetchUsage(authToken: authToken)
                    guard !Task.isCancelled else { return }
                    if let info {
                        handleCodexUsageResult(.success(info))
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    handleCodexUsageResult(.failure(error))
                }
            }
        }
    }

    private func handleOAuthUsageResult(_ result: Result<UsageData, Error>) {
        isFetching = false
        switch result {
        case var .success(usageData):
            // Clear needsReauth on successful fetch
            account.needsReauth = false

            // Copy email from previous data if OAuth didn't return it
            if usageData.email == nil, let existingEmail = account.usageData?.email {
                usageData.email = existingEmail
            }
            usageData.sessionResetDisplay = UsageData.formatSessionResetDisplay(usageData.sessionReset)
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            // Update account name if we have email and name is generic
            if let email = usageData.email,
               account.name.starts(with: "Account ") || account.name.starts(with: "Claude Code")
            {
                account.name = email
            }
            Log.debug(category, "OAuth fetch successful for \(account.name)")
        case let .failure(error):
            // Check if this is a 401 error that might be recoverable via refresh
            if case let AnthropicOAuthError.httpError(statusCode, _) = error, statusCode == 401 {
                // Try to refresh the token
                attemptTokenRefresh()
                return
            }

            lastError = error
            Log.error(category, "OAuth fetch failed for \(account.name): \(error.localizedDescription)")
            // No cached data fallback - show error state to user
        }
    }

    /// Attempts to refresh the OAuth access token using the refresh token.
    /// If successful, updates the account and retries the fetch.
    /// If failed, marks the account as needing re-authentication and sends notification.
    private func attemptTokenRefresh() {
        guard let refreshToken = account.oauthRefreshToken else {
            Log.warning(category, "No refresh token available for \(account.name), marking as needs re-auth")
            markNeedsReauthWithNotification()
            lastError = AnthropicOAuthError.httpError(
                statusCode: 401,
                message: "Token expired and no refresh token available"
            )
            return
        }

        guard let oauthService else {
            Log.error(category, "No OAuth service available for refresh")
            markNeedsReauthWithNotification()
            return
        }

        Log.info(category, "Attempting to refresh token for \(account.name)...")

        Task { @MainActor in
            do {
                let tokenResponse = try await oauthService.refreshAccessToken(refreshToken: refreshToken)

                // Update account with new tokens
                self.account.oauthToken = tokenResponse.accessToken
                if let newRefreshToken = tokenResponse.refreshToken {
                    self.account.oauthRefreshToken = newRefreshToken
                }
                self.account.saveCredentialsToKeychain()

                Log.info(self.category, "Token refresh successful for \(self.account.name), retrying fetch...")

                // Retry the fetch with the new token
                self.fetchNow()

            } catch {
                Log.error(self.category, "Token refresh failed for \(self.account.name): \(error.localizedDescription)")
                self.markNeedsReauthWithNotification()
                self.lastError = error
                // No cached data fallback - show re-auth UI to user
            }
        }
    }

    /// Marks the account as needing re-authentication and sends a system notification.
    private func markNeedsReauthWithNotification() {
        // Only notify if not already marked (prevents duplicate notifications)
        guard !account.needsReauth else { return }

        account.needsReauth = true
        NotificationManager.shared.sendNotification(
            type: .needsReauthentication,
            accountId: account.id,
            accountName: account.name
        )
    }

    private func handleCursorUsageResult(_ result: Result<CursorUsageInfo, Error>) {
        // Already on @MainActor, no need for DispatchQueue.main
        isFetching = false
        switch result {
        case let .success(info):
            let sessionPercentage = info.planLimit > 0 ? Double(info.planUsed) / Double(info.planLimit) : 0.0

            let usageData = UsageData(
                sessionPercentage: sessionPercentage,
                sessionReset: Constants.Status.ready,
                sessionResetDisplay: "\(info.planUsed) / \(info.planLimit)",
                weeklyPercentage: 0,
                weeklyReset: Constants.Status.ready,
                weeklyResetDisplay: "\(info.planUsed) / \(info.planLimit)",
                tier: info.planType ?? "Pro",
                email: info.email,
                fullName: nil,
                orgName: "Cursor",
                planType: info.planType,
                cursorUsed: info.planUsed,
                cursorLimit: info.planLimit
            )
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if let email = info.email,
               account.name.starts(with: "Account ") || self.account.name.starts(with: "Cursor")
            {
                account.name = "Cursor (\(email))"
            }
        case let .failure(error):
            lastError = error
            Log.error(Log.Category.cursorTracker, "Fetch failed: \(error)")
            // No cached data fallback - show error state to user
        }
    }

    private func handleGLMUsageResult(_ result: Result<GLMUsageInfo, Error>) {
        // Already on @MainActor, no need for DispatchQueue.main
        isFetching = false
        switch result {
        case let .success(info):
            // Use shared helper methods for consistent formatting
            let sessionResetDisplay = GLMUsageInfo.formatSessionResetDisplay(sessionPercentage: info.sessionPercentage)
            let weeklyResetDisplay = GLMUsageInfo.formatMonthlyResetDisplay(
                monthlyUsed: info.monthlyUsed,
                monthlyLimit: info.monthlyLimit,
                monthlyPercentage: info.monthlyPercentage
            )

            let usageData = UsageData(
                sessionPercentage: info.sessionPercentage,
                sessionReset: Constants.Status.ready,
                sessionResetDisplay: sessionResetDisplay,
                weeklyPercentage: info.monthlyPercentage,
                weeklyReset: Constants.Status.ready,
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
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if account.name.starts(with: "Account ") || account.name.starts(with: "GLM") {
                account.name = "GLM Coding Plan"
            }
        case let .failure(error):
            lastError = error
            Log.error(Log.Category.glmTracker, "Fetch failed: \(error)")
            // No cached data fallback - show error state to user
        }
    }

    private func handleGeminiUsageResult(_ result: Result<GeminiUsageInfo, Error>) {
        isFetching = false
        switch result {
        case let .success(info):
            let sessionResetDisplay = info.resetTime ?? Constants.Status.ready

            let usageData = UsageData(
                sessionPercentage: info.sessionPercentage,
                sessionReset: info.resetTime ?? Constants.Status.ready,
                sessionResetDisplay: sessionResetDisplay,
                weeklyPercentage: 0, // Gemini doesn't have weekly limits
                weeklyReset: Constants.Status.ready,
                weeklyResetDisplay: Constants.Status.ready,
                tier: info.tier,
                email: nil,
                fullName: nil,
                orgName: "Gemini",
                planType: info.tier,
                geminiRemainingFraction: info.remainingFraction,
                geminiModelId: info.modelId
            )
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if account.name.starts(with: "Account ") || account.name.starts(with: "Gemini") {
                account.name = "Gemini (\(info.tier))"
            }

            Log.info(category, "Gemini fetch successful for \(account.name)")

        case let .failure(error):
            // Check if token expired and needs refresh
            if case GeminiTrackerError.tokenExpired = error,
               let refreshToken = account.geminiRefreshToken
            {
                Log.info(category, "Gemini token expired, attempting refresh...")
                attemptGeminiTokenRefresh(refreshToken: refreshToken)
                return
            }

            lastError = error
            Log.error(category, "Gemini fetch failed: \(error)")
        }
    }

    private func handleAntigravityUsageResult(_ result: Result<AntigravityUsageInfo, Error>) {
        isFetching = false
        switch result {
        case let .success(info):
            let sessionResetDisplay = info.resetTime ?? Constants.Status.ready

            let usageData = UsageData(
                sessionPercentage: info.sessionPercentage,
                sessionReset: info.resetTime ?? Constants.Status.ready,
                sessionResetDisplay: sessionResetDisplay,
                weeklyPercentage: info.weeklyPercentage,
                weeklyReset: info.resetTime ?? Constants.Status.ready,
                weeklyResetDisplay: sessionResetDisplay,
                tier: info.tier,
                email: nil,
                fullName: nil,
                orgName: "Antigravity",
                planType: info.tier,
                antigravityModelName: info.modelName
            )
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if account.name.starts(with: "Account ") || account.name.starts(with: "Antigravity") {
                account.name = "Antigravity (\(info.tier))"
            }

            Log.info(category, "Antigravity fetch successful for \(account.name)")

        case let .failure(error):
            lastError = error
            Log.error(category, "Antigravity fetch failed: \(error)")
        }
    }

    private func handleOpenAIUsageResult(_ result: Result<OpenAIUsageInfo, Error>) {
        isFetching = false
        switch result {
        case let .success(info):
            // OpenAI doesn't have session/weekly limits like Claude
            // We display tokens used and estimated cost
            let usageData = UsageData(
                sessionPercentage: 0, // Pay-per-token has no percentage
                sessionReset: Constants.Status.ready,
                sessionResetDisplay: "\(info.tokensUsed.formatted()) tokens",
                weeklyPercentage: 0,
                weeklyReset: Constants.Status.ready,
                weeklyResetDisplay: "$\(String(format: "%.4f", info.estimatedCost))",
                tier: "Pay-per-token",
                email: nil,
                fullName: nil,
                orgName: info.orgName ?? "OpenAI",
                planType: "API Usage",
                openaiTokensUsed: info.tokensUsed,
                openaiCost: info.estimatedCost
            )
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if account.name.starts(with: "Account ") || account.name.starts(with: "OpenAI") {
                if let orgName = info.orgName {
                    account.name = "OpenAI (\(orgName))"
                } else {
                    account.name = "OpenAI API"
                }
            }

            Log.info(category, "OpenAI fetch successful for \(account.name)")

        case let .failure(error):
            lastError = error
            Log.error(category, "OpenAI fetch failed: \(error)")
        }
    }

    private func handleCodexUsageResult(_ result: Result<CodexUsageInfo, Error>) {
        isFetching = false
        switch result {
        case let .success(info):
            let sessionResetDisplay = info.sessionResetTime ?? "\(info.sessionUsed) / \(info.sessionLimit) msgs"
            let weeklyResetDisplay = info.weeklyResetTime ?? "\(info.weeklyUsed) / \(info.weeklyLimit) msgs"

            let usageData = UsageData(
                sessionPercentage: info.sessionPercentage,
                sessionReset: info.sessionResetTime ?? Constants.Status.ready,
                sessionResetDisplay: sessionResetDisplay,
                weeklyPercentage: info.weeklyPercentage,
                weeklyReset: info.weeklyResetTime ?? Constants.Status.ready,
                weeklyResetDisplay: weeklyResetDisplay,
                tier: info.planType,
                email: nil,
                fullName: nil,
                orgName: "Codex",
                planType: info.planType,
                codexSessionUsed: info.sessionUsed,
                codexSessionLimit: info.sessionLimit,
                codexWeeklyUsed: info.weeklyUsed,
                codexWeeklyLimit: info.weeklyLimit
            )
            updateWithUsageData(usageData)

            // Cache the successful result
            Task {
                await UsageCache.shared.set(usageData, for: account.id)
            }

            if account.name.starts(with: "Account ") || account.name.starts(with: "Codex") {
                account.name = "Codex (\(info.planType))"
            }

            Log.info(category, "Codex fetch successful for \(account.name)")

        case let .failure(error):
            lastError = error
            Log.error(category, "Codex fetch failed: \(error)")
        }
    }

    /// Attempt to refresh Gemini OAuth token
    private func attemptGeminiTokenRefresh(refreshToken: String) {
        guard let geminiTracker else {
            Log.error(category, "No Gemini tracker available for refresh")
            markNeedsReauthWithNotification()
            return
        }

        Task { @MainActor in
            do {
                let newTokens = try await geminiTracker.refreshToken(refreshToken: refreshToken)

                // Update account with new tokens
                self.account.geminiAccessToken = newTokens.accessToken
                self.account.geminiIdToken = newTokens.idToken
                if let expiry = newTokens.expiryDate {
                    self.account.geminiTokenExpiry = Date(timeIntervalSince1970: Double(expiry) / 1000.0)
                }
                self.account.saveCredentialsToKeychain()

                Log.info(self.category, "Gemini token refresh successful, retrying fetch...")
                self.fetchNow()

            } catch {
                Log.error(self.category, "Gemini token refresh failed: \(error.localizedDescription)")
                self.markNeedsReauthWithNotification()
                self.lastError = error
            }
        }
    }

    private func updateWithUsageData(_ usageData: UsageData) {
        // Clear any previous error on successful update
        lastError = nil

        if hasReceivedFirstUpdate {
            previousSessionPercentage = account.usageData?.sessionPercentage
            previousWeeklyPercentage = account.usageData?.weeklyPercentage
        } else {
            hasReceivedFirstUpdate = true
        }

        account.usageData = usageData

        // Log formatted provider stats
        Log.providerStats(accountName: account.name, accountType: account.type, usageData: usageData)

        checkThresholdCrossingsAndNotify(usageData: usageData)

        if didTransitionToReady(
            previousPercentage: previousSessionPercentage,
            currentPercentage: usageData.sessionPercentage,
            currentReset: usageData.sessionReset
        ) {
            if UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.autoWakeUp) {
                Log.debug(category, "Auto-waking up \(account.name)...")
                ping(isAuto: true)
            }
        }

        if let email = usageData.email, account.name.starts(with: "Account ") {
            account.name = email
        }
    }

    private func didCrossThreshold(previous: Double?, current: Double, threshold: Double) -> Bool {
        guard let prev = previous else { return false }
        return prev < threshold && current >= threshold
    }

    private func didTransitionToReady(
        previousPercentage: Double?,
        currentPercentage: Double,
        currentReset: String
    ) -> Bool {
        guard let prev = previousPercentage else { return false }
        return prev > 0 && currentPercentage == 0 && currentReset == Constants.Status.ready
    }

    private func checkThresholdCrossingsAndNotify(usageData: UsageData) {
        let accountId = account.id
        let accountName = account.name

        for config in ThresholdDefinitions.sessionThresholds
            where didCrossThreshold(
                previous: previousSessionPercentage,
                current: usageData.sessionPercentage,
                threshold: config.threshold
            )
            && NotificationSettings.shouldSend(type: config.notificationType)
        {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(
                type: config.notificationType,
                accountId: accountId,
                accountName: accountName,
                thresholdPercent: thresholdPercent
            )
        }

        for config in ThresholdDefinitions.weeklyThresholds
            where didCrossThreshold(
                previous: previousWeeklyPercentage,
                current: usageData.weeklyPercentage,
                threshold: config.threshold
            )
            && NotificationSettings.shouldSend(type: config.notificationType)
        {
            let thresholdPercent = Int(config.threshold * 100)
            NotificationManager.shared.sendNotification(
                type: config.notificationType,
                accountId: accountId,
                accountName: accountName,
                thresholdPercent: thresholdPercent
            )
        }

        if didTransitionToReady(
            previousPercentage: previousSessionPercentage,
            currentPercentage: usageData.sessionPercentage,
            currentReset: usageData.sessionReset
        ) {
            if NotificationSettings.shouldSend(type: .sessionReady) {
                NotificationManager.shared.sendNotification(
                    type: .sessionReady,
                    accountId: accountId,
                    accountName: accountName
                )
            }
        }
    }

    private func setupTracker() {
        tracker?.onUpdate = { [weak self] usageData in
            guard let self else { return }
            Task { @MainActor in
                self.isFetching = false
                var data = usageData
                data.sessionResetDisplay = UsageData.formatSessionResetDisplay(usageData.sessionReset)
                self.updateWithUsageData(data)
            }
        }

        tracker?.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.isFetching = false
                self.lastError = error
                Log.error(self.category, "Fetch failed for \(self.account.name): \(error)")
            }
        }
    }
}
