import SwiftUI

@main
struct ClaudeUsageProApp: App {
    @StateObject private var appState = AppState()
    // authManager needs to be top level to handle redirects if we expand deep links, 
    // but here it's fine. We create it here to own lifecycle.
    @StateObject private var authManager = AuthManager() 
    @StateObject private var windowManager = WindowSizeManager()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState, authManager: authManager, windowManager: windowManager)
                .environmentObject(appState) // Redundant if passed explicitly, but kept for child views if needed
        } label: {
            let icon = appState.sessions.isEmpty ? "xmark.circle" : "checkmark.circle"
            Image(systemName: icon)
        }
        .menuBarExtraStyle(.window)
    }
}

class WindowSizeManager: ObservableObject {
    @Published var currentSize: CGSize?
    private let defaults = UserDefaults.standard
    private let sizeKey = "windowSize"
    
    init() {
        if let data = defaults.dictionary(forKey: sizeKey),
           let width = data["width"] as? CGFloat,
           let height = data["height"] as? CGFloat {
            self.currentSize = CGSize(width: width, height: height)
        }
    }
    
    func saveSize(_ size: CGSize) {
        if size.width > 100 && size.height > 100 {
            defaults.set(["width": size.width, "height": size.height], forKey: sizeKey)
            // We don't necessarily update currentSize here to avoid loop, 
            // unless we want to trigger other UI updates.
            // DispatchQueue.main.async { self.currentSize = size } 
        }
    }
    
    func resetSize() {
        defaults.removeObject(forKey: sizeKey)
        self.currentSize = nil
        // Trigger window update if needed, but usually next relaunch or layout pass fixes it.
        // To force immediate resize, we might need a way to tell WindowAccessor contentSize = nil invalidator
        // But simply setting currentSize = nil might not "shrink" it if user is holding it.
        // A restart is the cleanest way, or we can set a default frame.
        // Let's set it to a "default" compact size to visually confirm.
        self.currentSize = CGSize(width: 350, height: 400) // Reset to compact
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
             self.defaults.removeObject(forKey: self.sizeKey) // Ensure it's not saved as the "new" size immediately if monitor picks it up
        }
    }
}

class AppState: ObservableObject {
    @Published var sessions: [AccountSession] = [] {
        didSet {
             // If sessions change (reordered/added), we should save the underlying accounts
             save()
        }
    }
    
    @Published var nextRefresh: Date = Date()
    
    init() {
        load()
    }
    
    func addAccount(cookies: [HTTPCookie]) {
        let newAccount = ClaudeAccount(name: "Account \(sessions.count + 1)", cookies: cookies)
        let session = AccountSession(account: newAccount)
        sessions.append(session)
        session.startMonitoring()
        save()
    }
    
    func save() {
        // Extract accounts from sessions to save
        let accountsToSave = sessions.map { $0.account }
        if let encoded = try? JSONEncoder().encode(accountsToSave) {
            UserDefaults.standard.set(encoded, forKey: "savedAccounts")
        }
    }
    
    func load() {
        if let data = UserDefaults.standard.data(forKey: "savedAccounts"),
           let decoded = try? JSONDecoder().decode([ClaudeAccount].self, from: data) {
            
            self.sessions = decoded.map { account in
                let session = AccountSession(account: account)
                session.startMonitoring()
                return session
            }
        }
    }
    
    func refreshAll() {
        for session in sessions {
            session.fetchNow()
        }
        self.nextRefresh = Date().addingTimeInterval(300)
    }
}

struct ClaudeAccount: Identifiable, Hashable, Codable {
    var id = UUID()
    var name: String
    var cookieProps: [[String: String]] // Store as raw properties
    
    // Usage Data is transient, we don't save it, or we make it Codable too (let's save it for cache)
    var usageData: UsageData?
    
    var limitDetails: String {
        return usageData?.tier ?? "Fetching..."
    }
    
    var cookies: [HTTPCookie] {
        return cookieProps.compactMap { props in
            // Convert String keys back to HTTPCookiePropertyKey
            var convertedProps: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in props {
                convertedProps[HTTPCookiePropertyKey(rawValue: k)] = v
            }
            // Fix boolean/integers if needed by HTTPCookie specific keys (like secure, version)
            // But usually the string init is robust enough or we refine helper.
            // For now, let's rely on standard init from props.
            if let secure = props[HTTPCookiePropertyKey.secure.rawValue] {
                  convertedProps[.secure] = (secure == "TRUE" || secure == "true")
            }
            if let discard = props[HTTPCookiePropertyKey.discard.rawValue] {
                  convertedProps[.discard] = (discard == "TRUE" || discard == "true")
            }
            return HTTPCookie(properties: convertedProps)
        }
    }
    
    init(name: String, cookies: [HTTPCookie]) {
        self.name = name
        self.cookieProps = cookies.compactMap { $0.toCodable() }
    }
    
    // Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: ClaudeAccount, rhs: ClaudeAccount) -> Bool {
        lhs.id == rhs.id
    }
}

struct ContentView: View {
    @ObservedObject var appState: AppState // Changed from EnvironmentObject to explicit for parity with others
    @ObservedObject var authManager: AuthManager
    @ObservedObject var windowManager: WindowSizeManager
    @State private var showSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Main Content Area
            if showSettings {
                SettingsView(windowManager: windowManager)
                    .transition(.move(edge: .trailing))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(appState.sessions) { session in
                            AccountRowSessionView(session: session)
                        }
                        
                        // Add Account Card
                        AddAccountCardView {
                            authManager.startLogin()
                        }
                    }
                    .padding(12)
                }
                .transition(.move(edge: .leading))
            }
            
            Divider()
            
            // Bottom Toolbar
            HStack(spacing: 8) { // Reduce spacing slightly as buttons have internal padding
                // Left: Settings (Add is now inline)
                // We keep settings button here. We can remove Add button from toolbar if preferred, or keep as shortcut.
                // User asked for "card after last card", but didn't explicitly say remove button. 
                // But logically "Add" card replaces the need for top/bottom add button for discoverability.
                // However, user said "can we add a card...".
                // I will keep the toolbar buttons for consistency/shortcuts unless user asked to remove.
                // Re-reading: "can add a manual refresh button... move quit...".
                // Previous request: "move quick button... all other buttons left".
                // I'll keep the Add button as a shortcut, or maybe remove it since it's duplicative?
                // I'll keep it for now to avoid altering controls I wasn't asked to remove.
                
                HoverIconButton(image: showSettings ? "checkmark" : "gearshape.fill", helpText: showSettings ? "Done" : "Settings") {
                    withAnimation {
                        showSettings.toggle()
                    }
                }
                
                // Refresh (moved to left)
                if !showSettings, !appState.sessions.isEmpty {
                    HoverIconButton(image: "arrow.clockwise", helpText: "Refresh Data Now") {
                        appState.refreshAll()
                    }
                }
                
                Spacer()
                
                // Center: Countdown Text Only
                if !showSettings, !appState.sessions.isEmpty {
                    CountdownView(target: appState.nextRefresh)
                        .help("Time until next automatic refresh")
                }
                
                Spacer()
                
                // Right: Quit
                QuitButton()
            }
            .padding(12)
            .background(Material.bar)
        }
        // Dynamic sizing for window
        .frame(minWidth: 350, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .background(WindowAccessor(manager: windowManager)) // Inject window logic
        .background(Material.ultraThin)
        .onAppear {
            authManager.onLoginSuccess = { cookies in
                print("[DEBUG] App: Login success.")
                appState.addAccount(cookies: cookies)
            }
            // Initialize refresh timer logic (simple approximation since we don't have global timer yet)
            appState.nextRefresh = Date().addingTimeInterval(300) 
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
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(color)
                .frame(width: 28, height: 28) // Fixed larger hit target
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.primary.opacity(0.1) : Color.clear)
                )
                .contentShape(Rectangle()) // Make entire 28x28 area clickable/hoverable
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
        .help(helpText)
    }
}

// Special Quit Button variation
struct QuitButton: View {
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Text("Quit")
                .font(.system(.caption, design: .rounded).bold())
                .foregroundColor(.red)
                .frame(width: 44, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.red.opacity(0.15) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hover
            }
        }
        .help("Quit Application")
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

// Helper to access the underlying NSWindow and enable resizing/persistence
struct WindowAccessor: NSViewRepresentable {
    @ObservedObject var manager: WindowSizeManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async(execute: {
            if let window = view.window {
                window.styleMask.insert(.resizable)
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                
                // Set initial size if persisted
                if let savedSize = manager.currentSize {
                    window.setContentSize(savedSize)
                }
                
                // Observe resize events
                context.coordinator.monitorResize(window: window)
            }
        })
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(manager: manager)
    }
    
    class Coordinator: NSObject, NSWindowDelegate {
        var manager: WindowSizeManager
        
        init(manager: WindowSizeManager) {
            self.manager = manager
        }
        
        func monitorResize(window: NSWindow) {
            window.delegate = self
        }
        
        func windowDidResize(_ notification: Notification) {
            if let window = notification.object as? NSWindow {
                manager.saveSize(window.frame.size)
            }
        }
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

// Wrapper for the row that observes the session object
struct AccountRowSessionView: View {
    @ObservedObject var session: AccountSession
    
    var body: some View {
        UsageView(account: session.account) {
            print("Ping clicked for \(session.account.name)")
            session.ping()
        }
        .padding(.vertical, 4)
    }
}

// End of file
