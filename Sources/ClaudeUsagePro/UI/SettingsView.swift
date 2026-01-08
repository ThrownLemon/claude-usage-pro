import SwiftUI

/// Displays and manages application settings including refresh intervals,
/// notification preferences, account management, and developer options.
struct SettingsView: View {
    @AppStorage("refreshInterval") private var refreshInterval: Double = 300 // Default 5 mins
    @AppStorage("autoWakeUp") private var autoWakeUp: Bool = false
    @AppStorage(Log.debugModeKey) private var debugModeEnabled: Bool = false
    @Environment(AppState.self) var appState

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
                    .onChange(of: refreshInterval) {
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
                                HStack {
                                    Image(systemName: session.account.type == .cursor ? "cpu" : "sparkles")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Text(session.account.name)
                                        .font(.body)
                                }
                                if let plan = session.account.usageData?.planType {
                                    Text(plan.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("Remove", role: .destructive) {
                                appState.removeAccount(id: session.account.id)
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

                // Developer Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Developer")
                        .font(.headline)

                    Toggle("Debug Logging", isOn: $debugModeEnabled)

                    Text("Logs to Console.app. Filter by subsystem: com.claudeusagepro")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if debugModeEnabled {
                        HStack(spacing: 8) {
                            Text("View logs:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("Open Console") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(8)

                // Data Management Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Data Management")
                        .font(.headline)

                    Text("Clear all stored data including accounts, credentials, and settings. The app will restart in a fresh state.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if showingResetConfirmation {
                        // Inline confirmation UI
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Are you sure?")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)

                            Text("This will delete all accounts, credentials, and settings. This action cannot be undone.")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                Button("Cancel") {
                                    withAnimation {
                                        showingResetConfirmation = false
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Reset") {
                                    appState.resetAllData()
                                    showingResetConfirmation = false
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        Button(role: .destructive) {
                            withAnimation {
                                showingResetConfirmation = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Reset All Data")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(Material.regular)
                .cornerRadius(8)
            }
            .padding(20)
        }
        .onAppear {
            Log.debug(Log.Category.settings, "SettingsView appeared")
        }
    }

    @State private var showingResetConfirmation = false
}

// MARK: - Threshold Slider Component

/// A slider component for configuring notification threshold values.
struct ThresholdSlider: View {
    /// Label displayed next to the slider
    let label: String
    /// The current threshold value (0.0 to 1.0)
    @Binding var value: Double
    /// The allowed range for the slider
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
