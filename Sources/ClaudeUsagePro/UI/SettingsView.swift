import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300 // Default 5 mins
    @AppStorage("autoWakeUp") private var autoWakeUp: Bool = false
    @EnvironmentObject var appState: AppState
    @State private var lastRefreshInterval: Double = 300
    @State private var notificationSettings: NotificationSettings = .default
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Data Fetching Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Fetching")
                        .font(.headline)
                    
                    Picker("Refresh Interval", selection: $refreshInterval) {
                        Text("30 Seconds").tag(30.0)
                        Text("1 Minute").tag(60.0)
                        Text("5 Minutes").tag(300.0)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: refreshInterval) { newValue in
                        lastRefreshInterval = newValue
                        appState.rescheduleAllSessions()
                    }
                    
                    Toggle("Auto-Wake Up Sessions", isOn: $autoWakeUp)
                    
                    Text("Automatically sends a ping to start a new session when usage resets to 0%.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(8)

                // Notifications Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Notifications")
                        .font(.headline)

                    Toggle("Enable Notifications", isOn: $notificationSettings.enabled)

                    if notificationSettings.enabled {
                        Divider()

                        // Session Alerts
                        Text("Session Alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Toggle("Session 75% Threshold", isOn: $notificationSettings.sessionThreshold75Enabled)
                        Toggle("Session 90% Threshold", isOn: $notificationSettings.sessionThreshold90Enabled)
                        Toggle("Session Ready", isOn: $notificationSettings.sessionReadyEnabled)

                        Text("Get notified when a session is ready to start.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)

                        Divider()

                        // Weekly Alerts
                        Text("Weekly Alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Toggle("Weekly 75% Threshold", isOn: $notificationSettings.weeklyThreshold75Enabled)
                        Toggle("Weekly 90% Threshold", isOn: $notificationSettings.weeklyThreshold90Enabled)
                    }
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(8)

                // Accounts Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accounts (\(appState.sessions.count))")
                        .font(.headline)
                    
                    ForEach(appState.sessions) { session in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(session.account.name)
                                    .font(.body)
                                if let plan = session.account.usageData?.planType {
                                    Text(plan.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                if let index = appState.sessions.firstIndex(where: { $0.id == session.id }) {
                                    appState.sessions.remove(at: index)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(8)
            }
            .padding(20)
        }
        .onAppear {
            lastRefreshInterval = refreshInterval
            notificationSettings = NotificationSettings.load()
            print("[DEBUG] SettingsView appeared")
        }
        .onChange(of: notificationSettings) { newValue in
            newValue.save()
        }
    }
}
