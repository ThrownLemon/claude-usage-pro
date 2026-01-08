import SwiftUI

/// Displays usage statistics for an account with circular and linear gauges.
/// Shows session and weekly usage percentages with color-coded thresholds.
struct UsageView: View {
    /// The account to display usage for
    let account: ClaudeAccount
    /// Whether usage data is currently being fetched
    let isFetching: Bool
    /// The most recent error, if any
    var lastError: Error?
    /// Callback to trigger a session ping
    var onPing: (() -> Void)?
    /// Callback to retry fetching after an error
    var onRetry: (() -> Void)?

    /// Creates a new usage view for an account.
    /// - Parameters:
    ///   - account: The account to display
    ///   - isFetching: Whether a fetch is in progress
    ///   - lastError: The most recent error, if any
    ///   - onPing: Optional callback for ping actions
    ///   - onRetry: Optional callback for retry actions
    init(account: ClaudeAccount, isFetching: Bool, lastError: Error? = nil, onPing: (() -> Void)? = nil, onRetry: (() -> Void)? = nil) {
        self.account = account
        self.isFetching = isFetching
        self.lastError = lastError
        self.onPing = onPing
        self.onRetry = onRetry
    }
    
    @State private var isHovering = false
    @State private var showStartText = false
    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    
    private let gaugeLineThickness: CGFloat = 5
    
    /// Returns the color associated with the account's tier
    var tierColor: Color {
        let tier = account.usageData?.tier.lowercased() ?? ""
        if tier.contains("max") { return .yellow }
        if tier.contains("team") { return .purple }
        if tier.contains("free") { return .gray }
        return .blue // Default/Pro
    }
    
    /// Returns a color based on session usage percentage (green → yellow → red).
    /// - Parameter percentage: Usage percentage from 0.0 to 1.0
    /// - Returns: Color representing usage severity
    func sessionColor(for percentage: Double) -> Color {
        if percentage < 0.5 {
            return .green
        } else if percentage < 0.75 {
            return .yellow
        } else {
            return .red
        }
    }
    
    /// Returns a gradient for the session gauge based on usage level.
    /// - Parameter percentage: Usage percentage from 0.0 to 1.0
    /// - Returns: Gradient transitioning between appropriate colors
    func sessionGradient(for percentage: Double) -> Gradient {
        if percentage < 0.5 {
            return Gradient(colors: [.green, .yellow])
        } else if percentage < 0.75 {
            return Gradient(colors: [.yellow, .orange])
        } else {
            return Gradient(colors: [.orange, .red])
        }
    }
    
    /// Formats a percentage value for display.
    /// - Parameter percentage: Value from 0.0 to 1.0
    /// - Returns: Formatted string like "75%"
    func percentageText(for percentage: Double) -> String {
        let value = Int((percentage * 100).rounded())
        return "\(value)%"
    }
    
    /// Returns a color for the weekly gauge based on usage percentage.
    /// Uses a gradient from green to red based on 10% increments.
    /// - Parameter percentage: Usage percentage from 0.0 to 1.0
    /// - Returns: Color representing usage severity
    func weeklyColor(for percentage: Double) -> Color {
        let hues: [Double] = [
            0.33,
            0.28,
            0.23,
            0.18,
            0.13,
            0.08,
            0.03,
            0.98,
            0.92,
            0.86,
            0.80
        ]
        let clamped = max(0.0, min(1.0, percentage))
        let index = min(hues.count - 1, Int((clamped * 10.0).rounded(.down)))
        return Color(hue: hues[index], saturation: 0.85, brightness: 0.95)
    }
    
    var body: some View {
        Group {
            if let error = lastError, account.usageData == nil {
                // Error state - no data available
                ErrorCardView(error: error, accountName: account.name, onRetry: onRetry)
            } else if let usage = account.usageData {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        VStack(alignment: .center, spacing: 6) {
                            Text(account.type == .glm ? "Monthly" : "Weekly")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.bottom, 10)
                            
                            Gauge(value: usage.weeklyPercentage) {
                                EmptyView()
                            } currentValueLabel: {
                                Text(percentageText(for: usage.weeklyPercentage))
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(weeklyColor(for: usage.weeklyPercentage))
                            .frame(width: 28, height: 28)
                            
                            if account.type == .glm, let used = usage.glmMonthlyUsed, let limit = usage.glmMonthlyLimit {
                                Text(String(format: "%.0f/%.0f", used, limit))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.top, 8)
                            } else {
                                Text(usage.weeklyReset)
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                    .padding(.top, 8)
                            }
                        }
                        .frame(width: 64, alignment: .center)
                        .padding(.top, 0)
                        .padding(.trailing, 2)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                HStack(spacing: 4) {
                                    if account.type == .cursor {
                                        Image(systemName: "cpu")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(account.name)
                                        .font(.system(.headline, design: .rounded).weight(.semibold))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .layoutPriority(1)
                                .padding(.bottom, 6)
                                
                                Spacer()
                                
                                Text(usage.tier.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.system(.caption2, design: .rounded).bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(tierColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .layoutPriority(2)
                            }
                            
                             HStack(spacing: 6) {
                                 if account.type == .glm {
                                     Text(Constants.GLM.sessionWindowLabel)
                                         .font(.system(.caption, design: .rounded).weight(.semibold))
                                         .foregroundColor(.secondary)
                                         .lineLimit(1)
                                         .truncationMode(.tail)
                                         .layoutPriority(1)
                                 } else {
                                     Text(account.type == .cursor ? "Request Usage" : "Session Usage")
                                         .font(.system(.caption, design: .rounded).weight(.semibold))
                                         .foregroundColor(.secondary)
                                         .lineLimit(1)
                                         .truncationMode(.tail)
                                         .layoutPriority(1)
                                 }

                                 Spacer()

                                 if account.type == .claude && usage.sessionReset == "Ready" {
                                     Button(action: { onPing?() }) {
                                         Image(systemName: "play.circle.fill")
                                             .font(.system(size: 14))
                                             .foregroundColor(.green)
                                     }
                                     .buttonStyle(.plain)
                                 }

                                 Text(percentageText(for: usage.sessionPercentage))
                                     .font(.system(.caption, design: .rounded).weight(.semibold))
                                     .foregroundColor(.secondary)
                             }

                             HStack(spacing: 6) {
                                 Text(usage.sessionResetDisplay == "Ready" ? "Ready to start new session" : usage.sessionResetDisplay)
                                     .font(.system(.caption, design: .rounded))
                                     .foregroundColor(.secondary)
                                 Spacer()
                                 if isFetching {
                                     ProgressView()
                                         .progressViewStyle(.circular)
                                         .controlSize(.mini)
                                 } else if lastError != nil {
                                     // Subtle warning when cached data shown but latest fetch failed
                                     Image(systemName: "exclamationmark.triangle.fill")
                                         .font(.system(size: 12))
                                         .foregroundColor(.orange)
                                         .help("Last fetch failed - showing cached data")
                                 } else {
                                     Image(systemName: "checkmark.circle.fill")
                                         .font(.system(size: 12))
                                         .foregroundColor(.green)
                                 }
                             }

                             Gauge(value: usage.sessionPercentage) {
                                 EmptyView()
                             }
                             .gaugeStyle(.accessoryLinear)
                             .tint(sessionGradient(for: usage.sessionPercentage))
                             .controlSize(.small)
                             .scaleEffect(y: 1.35)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                LoadingCardView()
            }
        }
        .padding(16)
        .background(Material.regular)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1) // Subtle border for definition
        )
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2) // Deeper shadow for pop
    }
}

/// Displays an animated skeleton loading placeholder for usage cards.
struct LoadingCardView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .center, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 36, height: 10)

                Circle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 42, height: 42)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 48, height: 10)
            }
            .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 140, height: 16)

                    Spacer()

                    Circle()
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 12, height: 12)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.1))
                        .frame(width: 48, height: 14)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 180, height: 12)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(width: 120, height: 10)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 6)
            }
        }
        .opacity(isAnimating ? 0.5 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

/// Displays an error state with retry button when usage fetch fails.
struct ErrorCardView: View {
    /// The error that occurred
    let error: Error
    /// The name of the account that failed
    let accountName: String
    /// Optional callback to retry the failed operation
    var onRetry: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(.orange)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(accountName)
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)

                Text("Failed to fetch usage data")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)

                Text(error.localizedDescription)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isHovering ? Color.blue : Color.blue.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovering = hovering
                }
            }
        }
    }
}
