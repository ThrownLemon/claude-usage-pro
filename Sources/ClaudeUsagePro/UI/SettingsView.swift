import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300 // Default 5 mins
    @ObservedObject var windowManager: WindowSizeManager
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        TabView {
            GeneralSettingsView(refreshInterval: $refreshInterval, windowManager: windowManager)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
            
            AccountsSettingsView()
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }
        }
        // .frame(width: 450, height: 300) // Removed for embedded use
        .padding()
        .onAppear {
            print("[DEBUG] SettingsView appeared")
        }
    }
}

struct GeneralSettingsView: View {
    @Binding var refreshInterval: Double
    @ObservedObject var windowManager: WindowSizeManager
    @AppStorage("autoWakeUp") private var autoWakeUp: Bool = false
    
    var body: some View {
        Form {
            Section(header: Text("Data Fetching")) {
                Picker("Refresh Interval", selection: $refreshInterval) {
                    Text("1 Minute").tag(60.0)
                    Text("5 Minutes").tag(300.0)
                    Text("15 Minutes").tag(900.0)
                    Text("30 Minutes").tag(1800.0)
                    Text("1 Hour").tag(3600.0)
                }
                .pickerStyle(.menu)
                
                Toggle("Auto-Wake Up Sessions", isOn: $autoWakeUp)
                Text("Automatically sends a ping to start a new session when usage resets to 0%.")
                     .font(.caption)
                     .foregroundColor(.secondary)
                
                Text("Changes to refresh interval take effect on next app launch or account refresh.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section(header: Text("Window Management")) {
                Button("Reset Window Size") {
                    windowManager.resetSize()
                }
                Text("Restores the default compact window size.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

struct AccountsSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Form {
            Section {
                ForEach(appState.sessions) { session in
                    AccountSettingsRow(session: session) {
                        deleteSession(session)
                    }
                }
            } header: {
                Text("Connected Accounts")
            } footer: {
                Text("\(appState.sessions.count) account(s) active")
            }
        }
        .formStyle(.grouped)
    }
    
    private func deleteSession(_ session: AccountSession) {
        if let index = appState.sessions.firstIndex(where: { $0.id == session.id }) {
            appState.sessions.remove(at: index)
        }
    }
}

struct AccountSettingsRow: View {
    let session: AccountSession
    let onDelete: () -> Void
    
    var body: some View {
        LabeledContent {
            // Content (Right Side)
            VStack(alignment: .trailing, spacing: 4) {
                 if let plan = session.account.usageData?.planType {
                    Text(plan.replacingOccurrences(of: "_", with: " ").capitalized)
                         .font(.caption.bold())
                         .foregroundColor(.blue)
                }
                
                Menu("Actions") {
                    Button("Manage Subscription") {
                        if let url = URL(string: "https://claude.ai/settings/billing") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Divider()
                    Button("Remove Account", role: .destructive) {
                        onDelete()
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            // Label (Left Side)
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.check")
                    .font(.title2)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.account.name)
                        .font(.body.weight(.medium))
                    
                    if let org = session.account.usageData?.orgName {
                        Text(org)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
