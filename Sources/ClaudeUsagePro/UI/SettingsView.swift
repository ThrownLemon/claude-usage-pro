import SwiftUI

struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300 // Default 5 mins
    @AppStorage("autoWakeUp") private var autoWakeUp: Bool = false
    @EnvironmentObject var appState: AppState

    // Notification settings using @AppStorage for reactive updates
    @AppStorage(NotificationSettings.enabledKey) private var notificationsEnabled: Bool = NotificationSettings.defaultEnabled
    @AppStorage(NotificationSettings.sessionReadyEnabledKey) private var sessionReadyEnabled: Bool = NotificationSettings.defaultSessionReadyEnabled

    // Session threshold toggles
    @AppStorage(NotificationSettings.sessionThreshold1EnabledKey) private var sessionThreshold1Enabled: Bool = NotificationSettings.defaultSessionThreshold1Enabled
    @AppStorage(NotificationSettings.sessionThreshold2EnabledKey) private var sessionThreshold2Enabled: Bool = NotificationSettings.defaultSessionThreshold2Enabled

    // Weekly threshold toggles
    @AppStorage(NotificationSettings.weeklyThreshold1EnabledKey) private var weeklyThreshold1Enabled: Bool = NotificationSettings.defaultWeeklyThreshold1Enabled
    @AppStorage(NotificationSettings.weeklyThreshold2EnabledKey) private var weeklyThreshold2Enabled: Bool = NotificationSettings.defaultWeeklyThreshold2Enabled

    // Threshold values (shared between session and weekly for consistency)
    @AppStorage(NotificationSettings.threshold1ValueKey) private var threshold1Value: Double = NotificationSettings.defaultThreshold1
    @AppStorage(NotificationSettings.threshold2ValueKey) private var threshold2Value: Double = NotificationSettings.defaultThreshold2
    
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
                    .onChange(of: refreshInterval) { _ in
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

                    Toggle("Enable Notifications", isOn: $notificationsEnabled)

                    if notificationsEnabled {
                        Divider()

                        // Threshold Values Configuration
                        Text("Threshold Values")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        ThresholdSlider(
                            label: "Lower",
                            value: $threshold1Value,
                            range: 0.50...0.85
                        )

                        ThresholdSlider(
                            label: "Higher",
                            value: $threshold2Value,
                            range: 0.70...0.99
                        )

                        Text("Get notified when usage reaches these thresholds.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Divider()

                        // Session Alerts
                        Text("Session Alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Toggle("Session at \(Int(threshold1Value * 100))% (Lower)", isOn: $sessionThreshold1Enabled)
                        Toggle("Session at \(Int(threshold2Value * 100))% (Higher)", isOn: $sessionThreshold2Enabled)
                        Toggle("Session Ready", isOn: $sessionReadyEnabled)

                        Text("Get notified when a session is ready to start.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 4)

                        Divider()

                        // Weekly Alerts
                        Text("Weekly Alerts")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Toggle("Weekly at \(Int(threshold1Value * 100))% (Lower)", isOn: $weeklyThreshold1Enabled)
                        Toggle("Weekly at \(Int(threshold2Value * 100))% (Higher)", isOn: $weeklyThreshold2Enabled)
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
            print("[DEBUG] SettingsView appeared")
        }
    }
}

// MARK: - Threshold Slider Component

struct ThresholdSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .leading)

            Slider(value: $value, in: range, step: 0.05)

            Text("\(Int(value * 100))%")
                .font(.system(.body, design: .monospaced))
                .frame(width: 40, alignment: .trailing)
        }
    }
}
