import SwiftUI
import Combine

@main
struct ClaudeUsageProApp: App {
    @State private var appState = AppState()
    @StateObject private var authManager = AuthManager()

    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState, authManager: authManager)
                .environment(appState)
        } label: {
            MenuBarUsageView(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarUsageView: View {
    var appState: AppState

    var body: some View {
        let displaySessions = Array(appState.sessions.prefix(4))
        let labelText = displaySessions.map { session in
            let percent = Int((session.account.usageData?.sessionPercentage ?? 0) * 100)
            return "\(percent)%"
        }.joined(separator: "  ")
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            Text(labelText.isEmpty ? "Claude" : labelText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .fontWidth(.condensed)
                .foregroundColor(.primary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}

struct AccountTypeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(isHovering ? color : .secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isHovering ? color.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isHovering ? color.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.system(.caption))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovering ? color : .secondary.opacity(0.5))
            }
            .padding(16)
            .background(Material.regular)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovering ? color.opacity(0.3) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

enum AddAccountStep {
    case menu
    case glmToken
}
 
// MARK: - Add Account View
 
struct AddAccountView: View {
    @Binding var step: AddAccountStep
    @Binding var glmTokenInput: String
    let onClaude: () -> Void
    let onCursor: () -> Void
    let onGLM: (String) -> Void

    @State private var isValidating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    if step == .menu {
                        accountTypeMenu
                    } else if step == .glmToken {
                        glmTokenEntry
                    }
                }
                .padding(20)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var accountTypeMenu: some View {
        VStack(spacing: 12) {
            AccountTypeButton(
                title: "Claude",
                subtitle: "Login via browser",
                icon: "sparkles",
                color: .orange
            ) {
                onClaude()
            }

            AccountTypeButton(
                title: "Cursor",
                subtitle: "Monitor local Cursor installation",
                icon: "arrow.triangle.turn.up.right.diamond",
                color: .blue
            ) {
                onCursor()
            }

            AccountTypeButton(
                title: "GLM Coding Plan",
                subtitle: "Zhipu AI GLM Coding Plan",
                icon: "chart.bar.doc.horizontal",
                color: .green
            ) {
                step = .glmToken
            }
        }
    }

    private var glmTokenEntry: some View {
        VStack(spacing: 16) {
            Text("GLM Coding Plan")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your API token from open.bigmodel.cn")
                .font(.subheadline)
                .foregroundColor(.secondary)

            SecureField("API Token", text: $glmTokenInput)
                .textFieldStyle(.roundedBorder)
                .onChange(of: glmTokenInput) {
                    errorMessage = nil
                }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                }
                .transition(.opacity)
            }

            HStack(spacing: 12) {
                Button("Back") {
                    step = .menu
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .disabled(isValidating)

                Button {
                    Task {
                        await validateAndSubmit()
                    }
                } label: {
                    if isValidating {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Validating...")
                        }
                    } else {
                        Text("Add Account")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(glmTokenInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating)
            }

            Spacer()
        }
    }

    @MainActor
    private func validateAndSubmit() async {
        let token = glmTokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidating = true
        errorMessage = nil

        do {
            let isValid = try await AppState.validateGLMToken(token)
            if isValid {
                onGLM(token)
                glmTokenInput = ""
            } else {
                errorMessage = "Invalid API token. Please check and try again."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isValidating = false
    }
}

struct ContentView: View {
    var appState: AppState
    @ObservedObject var authManager: AuthManager

    @State private var showSettings = false
    @State private var showAddAccount = false
    @State private var addAccountStep = AddAccountStep.menu
    @State private var glmTokenInput = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack(spacing: 8) {
                Image(systemName: showSettings ? "gearshape.fill" : (showAddAccount ? "plus.circle.fill" : "sparkles"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(showSettings ? "Settings" : (showAddAccount ? "Add Account" : "Claude Usage Pro"))
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.primary)
                Spacer()
                
                HoverIconButton(
                    image: (showSettings || showAddAccount) ? "checkmark" : "gearshape.fill",
                    helpText: (showSettings || showAddAccount) ? "Done" : "Settings"
                ) {
                    withAnimation {
                        if showSettings || showAddAccount {
                            showSettings = false
                            showAddAccount = false
                        } else {
                            showSettings = true
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Material.bar)
            
            Divider()
            
            // Main Content Area
            if showSettings {
                SettingsView()
            } else if showAddAccount {
                AddAccountView(
                    step: $addAccountStep,
                    glmTokenInput: $glmTokenInput,
                    onClaude: {
                        showAddAccount = false
                        authManager.startLogin()
                    },
                    onCursor: {
                        showAddAccount = false
                        appState.addCursorAccount()
                    },
                    onGLM: { token in
                        showAddAccount = false
                        if !token.isEmpty {
                            appState.addGLMAccount(apiToken: token)
                        }
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.sessions) { session in
                            AccountRowSessionView(session: session)
                        }
                        
                        AddAccountCardView {
                            showAddAccount = true
                            addAccountStep = .menu
                        }
                    }
                    .padding(20)

                }
            }
            
            Divider()
            
            // Bottom Toolbar
            HStack(spacing: 8) {
                if !showSettings, !showAddAccount, !appState.sessions.isEmpty {
                    HoverIconButton(image: "arrow.clockwise", helpText: "Refresh Data Now") {
                        appState.refreshAll()
                        appState.nextRefresh = Date().addingTimeInterval(appState.refreshIntervalSeconds())
                    }
                }
                
                Spacer()
                
                if !showSettings, !showAddAccount, !appState.sessions.isEmpty {
                    CountdownView(target: appState.nextRefresh)
                        .help("Time until next automatic refresh")
                        .id(appState.nextRefresh)
                }
                
                Spacer()
                
                QuitButton()
            }
            .padding(12)
            .background(Material.bar)
        }
        .frame(width: 405, height: 660)
        .background(Material.ultraThin)
        .onAppear {
            authManager.onLoginSuccess = { cookies in
                Log.info(Log.Category.app, "Login success")
                appState.addAccount(cookies: cookies)
            }
            appState.nextRefresh = Date().addingTimeInterval(appState.refreshIntervalSeconds())

            // Request notification permission on first launch
            requestNotificationPermission()
        }
    }

    // Request notification permission on app launch
    private func requestNotificationPermission() {
        let notificationManager = NotificationManager.shared

        // Only request if not determined yet
        if notificationManager.authorizationStatus == .notDetermined {
            notificationManager.onPermissionGranted = {
                Log.info(Log.Category.notifications, "Permission granted")
            }

            notificationManager.onPermissionDenied = {
                Log.info(Log.Category.notifications, "Permission denied by user")
            }

            notificationManager.onError = { error in
                Log.error(Log.Category.notifications, "Error requesting permission: \(error.localizedDescription)")
            }

            notificationManager.requestPermission()
        } else {
            Log.debug(Log.Category.notifications, "Authorization status is \(notificationManager.authorizationStatus.rawValue)")
        }
    }
}



// Custom Button Component for reliable hover
struct HoverIconButton: View {
    let image: String
    let helpText: String
    var color: Color = .primary
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .medium)) // Slightly larger icon
                .foregroundColor(isHovering ? color : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.secondary.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle()) // Ensures entire 32x32 area is clickable
        .help(helpText)
        .onHover { hover in
            isHovering = hover
        }
    }
}

struct QuitButton: View {
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isHovering ? .red : .secondary) // Red on hover to indicate destructive/quit
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.red.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isHovering ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1), lineWidth: 1)
                )
                .scaleEffect(isHovering ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.1), value: isHovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help("Quit Application")
        .onHover { hover in
            isHovering = hover
        }
    }
}

struct AddAccountCardView: View {
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text("Add Account")
                        .font(.system(.body, design: .rounded).bold())
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .background(Material.regular)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [5]))
                    .foregroundColor(isHovering ? .primary.opacity(0.5) : .secondary.opacity(0.3))
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

@Observable
@MainActor
class AppState {
    var sessions: [AccountSession] = []
    var nextRefresh: Date = Date()
    var iconRefreshTrigger = UUID()

    private let defaults = UserDefaults.standard
    private let accountsKey = Constants.UserDefaultsKeys.savedAccounts
    
    init() {
        loadAccounts()
    }
    
    func addAccount(cookies: [HTTPCookie]) {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Account \(sessions.count + 1)",
            cookies: cookies,
            usageData: nil,
            type: .claude
        )
        // Save cookies to Keychain
        newAccount.saveCredentialsToKeychain()

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    func addCursorAccount() {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "Cursor Monitoring",
            cookies: [],
            usageData: nil,
            type: .cursor
        )
        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    func addGLMAccount(apiToken: String) {
        let newAccount = ClaudeAccount(
            id: UUID(),
            name: "GLM Coding Plan",
            apiToken: apiToken,
            usageData: nil
        )
        // Save API token to Keychain
        newAccount.saveCredentialsToKeychain()

        let session = AccountSession(account: newAccount)
        sessions.append(session)
        saveAccounts()
        subscribeToSessionChanges(session)
        session.startMonitoring()
    }

    static func validateGLMToken(_ token: String) async throws -> Bool {
        let tracker = GLMTrackerService()
        let info = try await tracker.fetchGLMUsage(apiToken: token)
        return info.sessionLimit > 0 || info.monthlyLimit > 0 || info.sessionPercentage >= 0
    }

    private func subscribeToSessionChanges(_ session: AccountSession) {
        // With @Observable, SwiftUI automatically tracks changes to session properties
        // We just need to set up the refresh tick callback
        session.onRefreshTick = { [weak self] in
            Task { @MainActor in
                self?.nextRefresh = Date().addingTimeInterval(self?.refreshIntervalSeconds() ?? Constants.Timeouts.defaultRefreshInterval)
            }
        }
    }
    
    func removeAccount(id: UUID) {
        // Find the account and delete its credentials from Keychain
        if let session = sessions.first(where: { $0.account.id == id }) {
            session.account.deleteCredentialsFromKeychain()
        }
        sessions.removeAll { $0.account.id == id }
        saveAccounts()
    }
    
    func refreshAll() {
        let nextInterval = refreshIntervalSeconds()
        Log.debug(Log.Category.appState, "Refreshing all accounts... Next in \(Int(nextInterval))s")
        for session in sessions {
            session.fetchNow()
        }
        nextRefresh = Date().addingTimeInterval(nextInterval)
    }
    
    func rescheduleAllSessions() {
        for session in sessions {
            session.scheduleRefreshTimer()
        }
        nextRefresh = Date().addingTimeInterval(refreshIntervalSeconds())
    }
    
    func refreshIntervalSeconds() -> TimeInterval {
        let interval = defaults.double(forKey: Constants.UserDefaultsKeys.refreshInterval)
        return interval > 0 ? interval : Constants.Timeouts.defaultRefreshInterval
    }
    
    private func saveAccounts() {
        let accounts = sessions.map { $0.account }
        if let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: accountsKey)
        }
    }
    
    private func loadAccounts() {
        // First, try to migrate any legacy data from UserDefaults
        migrateCredentialsFromUserDefaults()

        if let data = defaults.data(forKey: accountsKey),
           var accounts = try? JSONDecoder().decode([ClaudeAccount].self, from: data) {
            for i in accounts.indices {
                accounts[i].usageData = nil
                // Load credentials from Keychain
                accounts[i].loadCredentialsFromKeychain()
            }

            self.sessions = accounts.map { AccountSession(account: $0) }

            for session in self.sessions {
                subscribeToSessionChanges(session)
                session.startMonitoring()
            }
        }
    }

    /// Migrate credentials from old UserDefaults storage to Keychain (one-time migration)
    /// Only marks migration complete if ALL credentials are successfully migrated.
    /// If any migration fails, it will be retried on subsequent launches.
    private func migrateCredentialsFromUserDefaults() {
        let migrationKey = Constants.UserDefaultsKeys.keychainMigrationComplete
        guard !defaults.bool(forKey: migrationKey) else { return }

        Log.info(Log.Category.keychain, "Starting migration from UserDefaults to Keychain...")

        var allMigrationsSucceeded = true

        // Try to load old-format accounts that included credentials
        if let data = defaults.data(forKey: accountsKey) {
            // Decode with a temporary struct that includes the old fields
            struct LegacyAccount: Codable {
                var id: UUID
                var name: String
                var type: AccountType?
                var cookieProps: [[String: String]]?
                var apiToken: String?
            }

            do {
                let legacyAccounts = try JSONDecoder().decode([LegacyAccount].self, from: data)
                for legacy in legacyAccounts {
                    // Migrate cookies if present
                    if let cookies = legacy.cookieProps, !cookies.isEmpty {
                        do {
                            try KeychainService.save(cookies, forKey: KeychainService.cookiesKey(for: legacy.id))
                            Log.info(Log.Category.keychain, "Migrated cookies for account \(legacy.id)")
                        } catch {
                            Log.error(Log.Category.keychain, "Failed to migrate cookies for \(legacy.id): \(error)")
                            allMigrationsSucceeded = false
                        }
                    }

                    // Migrate API token if present
                    if let token = legacy.apiToken {
                        do {
                            try KeychainService.save(token, forKey: KeychainService.apiTokenKey(for: legacy.id))
                            Log.info(Log.Category.keychain, "Migrated API token for account \(legacy.id)")
                        } catch {
                            Log.error(Log.Category.keychain, "Failed to migrate API token for \(legacy.id): \(error)")
                            allMigrationsSucceeded = false
                        }
                    }
                }
            } catch {
                Log.error(Log.Category.keychain, "Failed to decode legacy accounts: \(error)")
                allMigrationsSucceeded = false
            }
        }

        // Only mark migration complete if ALL credentials migrated successfully
        // This allows retry on subsequent launches if Keychain was temporarily unavailable
        if allMigrationsSucceeded {
            defaults.set(true, forKey: migrationKey)
            Log.info(Log.Category.keychain, "Migration complete")
        } else {
            Log.warning(Log.Category.keychain, "Migration incomplete - will retry on next launch")
        }
    }

    var menuBarIconState: MenuBarIconState {
        guard !sessions.isEmpty else { return .noAccounts }

        if sessions.contains(where: { $0.isFetching }) {
            return .loading
        }

        let accountsWithData = sessions.compactMap { $0.account.usageData }

        if accountsWithData.isEmpty {
            return .noData
        }

        let maxSessionPercentage = accountsWithData.map { $0.sessionPercentage }.max() ?? 0

        let hasReadyState = accountsWithData.contains {
            $0.sessionPercentage == 0 && $0.sessionReset == "Ready"
        }

        if hasReadyState && maxSessionPercentage == 0 {
            return .ready
        } else if maxSessionPercentage < 0.5 {
            return .lowUsage
        } else if maxSessionPercentage < 0.75 {
            return .mediumUsage
        } else {
            return .highUsage
        }
    }

    /// Reset all app data to factory state
    /// Clears UserDefaults, Keychain, and in-memory sessions
    func resetAllData() {
        Log.info(Log.Category.app, "Resetting all app data...")

        // Stop all session monitors
        for session in sessions {
            session.stopMonitoring()
        }

        // Clear in-memory sessions
        sessions.removeAll()

        // Clear Keychain (credentials)
        KeychainService.deleteAll()

        // Clear UserDefaults for this app
        if let bundleId = Bundle.main.bundleIdentifier {
            defaults.removePersistentDomain(forName: bundleId)
            defaults.synchronize()
        }

        Log.info(Log.Category.app, "All app data has been reset")
    }
}

struct CountdownView: View {
    let target: Date
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let diff = target.timeIntervalSince(context.date)
            if diff > 0 {
                Text("Refresh: \(timeString(from: diff))")
                    .font(.system(.caption2, design: .rounded).monospacedDigit())
                    .foregroundColor(.secondary)
            } else {
                Text("Refreshing...")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

enum MenuBarIconState {
    case noAccounts
    case loading
    case noData
    case ready
    case lowUsage
    case mediumUsage
    case highUsage

    var iconName: String {
        switch self {
        case .noAccounts: return "xmark.circle"
        case .loading: return "circle.dotted"
        case .noData: return "questionmark.circle"
        case .ready: return "play.circle.fill"
        case .lowUsage, .mediumUsage, .highUsage: return "checkmark.circle"
        }
    }

    var iconColor: Color {
        switch self {
        case .noAccounts: return .secondary
        case .loading: return .blue
        case .noData: return .gray
        case .ready: return .green
        case .lowUsage: return .green
        case .mediumUsage: return .orange
        case .highUsage: return .red
        }
    }
}

struct AccountRowSessionView: View {
    var session: AccountSession

    var body: some View {
        UsageView(
            account: session.account,
            isFetching: session.isFetching,
            lastError: session.lastError,
            onPing: {
                Log.debug(Log.Category.app, "Ping clicked for \(session.account.name)")
                session.ping()
            },
            onRetry: {
                Log.debug(Log.Category.app, "Retry clicked for \(session.account.name)")
                session.fetchNow()
            }
        )
        .padding(.vertical, 4)
    }
}
