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
    /// Callback to re-authenticate the account when token expires
    var onReauthenticate: (() -> Void)?

    /// Current theme selection
    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue

    /// Effective color scheme from our custom environment (respects user's mode selection)
    @Environment(\.colorScheme) private var colorScheme

    /// Current theme colors
    private var theme: ThemeColors {
        let appTheme = AppTheme(rawValue: selectedTheme) ?? .standard
        return ThemeManager.colors(for: appTheme)
    }

    /// Creates a new usage view for an account.
    /// - Parameters:
    ///   - account: The account to display
    ///   - isFetching: Whether a fetch is in progress
    ///   - lastError: The most recent error, if any
    ///   - onPing: Optional callback for ping actions
    ///   - onRetry: Optional callback for retry actions
    ///   - onReauthenticate: Optional callback to re-authenticate when token expires
    init(
        account: ClaudeAccount, isFetching: Bool, lastError: Error? = nil,
        onPing: (() -> Void)? = nil, onRetry: (() -> Void)? = nil,
        onReauthenticate: (() -> Void)? = nil
    ) {
        self.account = account
        self.isFetching = isFetching
        self.lastError = lastError
        self.onPing = onPing
        self.onRetry = onRetry
        self.onReauthenticate = onReauthenticate
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
        return .blue  // Default/Pro
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
    /// Uses theme colors with thresholds at 75% and 90%.
    /// - Parameter percentage: Usage percentage from 0.0 to 1.0
    /// - Returns: Color representing usage severity
    func weeklyColor(for percentage: Double) -> Color {
        if percentage < 0.75 {
            return theme.totalGaugeHealthy
        } else if percentage < 0.90 {
            return theme.totalGaugeWarning
        } else {
            return theme.totalGaugeCritical
        }
    }

    /// Returns a color for the session gauge based on usage percentage.
    func sessionThemeColor(for percentage: Double) -> Color {
        if percentage < 0.50 {
            return theme.totalGaugeHealthy
        } else if percentage < 0.75 {
            return theme.totalGaugeWarning
        } else {
            return theme.totalGaugeCritical
        }
    }

    /// Returns a gradient for the session gauge based on usage and theme.
    func sessionThemeGradient(for percentage: Double) -> Gradient {
        if percentage < 0.5 {
            return Gradient(colors: [theme.totalGaugeHealthy, theme.totalGaugeWarning])
        } else if percentage < 0.75 {
            return Gradient(colors: [
                theme.totalGaugeWarning, theme.totalGaugeCritical.opacity(0.8),
            ])
        } else {
            return Gradient(colors: [
                theme.totalGaugeWarning.opacity(0.8), theme.totalGaugeCritical,
            ])
        }
    }

    var body: some View {
        Group {
            if let error = lastError, account.usageData == nil {
                // Error state - no data available
                ErrorCardView(
                    error: error,
                    accountName: account.name,
                    needsReauth: account.needsReauth,
                    onRetry: onRetry,
                    onReauthenticate: onReauthenticate,
                    theme: theme
                )
            } else if let usage = account.usageData {
                layoutContent(for: usage)
            } else {
                LoadingCardView()
            }
        }
        .padding(theme.layout.effectivePadding)
        .background(theme.cardBackground(for: colorScheme))
        .cornerRadius(theme.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius)
                .stroke(theme.cardBorder(for: colorScheme), lineWidth: max(theme.borderWidth, 0.5))
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.2) : .black.opacity(0.1), radius: 4,
            x: 0, y: 2)
    }

    // MARK: - Layout Builder

    /// Builds the main layout based on theme configuration
    @ViewBuilder
    private func layoutContent(for usage: UsageData) -> some View {
        switch theme.layout.gaugePosition {
        case .left:
            HStack(alignment: .top, spacing: theme.layout.sectionSpacing) {
                weeklyGaugesSection(usage: usage)
                accountInfoSection(usage: usage)
            }
        case .right:
            HStack(alignment: .top, spacing: theme.layout.sectionSpacing) {
                accountInfoSection(usage: usage)
                weeklyGaugesSection(usage: usage)
            }
        case .top:
            VStack(alignment: .leading, spacing: theme.layout.sectionSpacing) {
                HStack {
                    Spacer()
                    weeklyGaugesSection(usage: usage)
                    Spacer()
                }
                accountInfoSection(usage: usage)
            }
        case .bottom:
            VStack(alignment: .leading, spacing: theme.layout.sectionSpacing) {
                accountInfoSection(usage: usage)
                HStack {
                    Spacer()
                    weeklyGaugesSection(usage: usage)
                    Spacer()
                }
            }
        case .inline:
            inlineLayout(usage: usage)
        }
    }

    // MARK: - Weekly Gauges Section

    /// Builds the weekly gauges area using GaugeFactory
    @ViewBuilder
    private func weeklyGaugesSection(usage: UsageData) -> some View {
        if theme.layout.showWeeklyGauge {
            if let sonnetPct = usage.sonnetPercentage {
                // Claude Max: Show Sonnet and Combined gauges
                VStack(alignment: .center, spacing: theme.layout.gaugeSpacing) {
                    if theme.layout.labelPosition == .above {
                        Text("Weekly")
                            .font(theme.fontConfig.labelFont(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    gaugeArrangementView {
                        GaugeFactory.makeSonnetGauge(
                            percentage: sonnetPct,
                            label: "Sonnet",
                            resetDisplay: usage.sonnetReset ?? usage.weeklyReset,
                            color: theme.sonnetGaugeColor,
                            theme: theme
                        )

                        GaugeFactory.makeWeeklyGauge(
                            percentage: usage.weeklyPercentage,
                            label: "Total",
                            resetDisplay: usage.weeklyReset,
                            color: weeklyColor(for: usage.weeklyPercentage),
                            theme: theme
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else {
                // Standard: Single weekly gauge
                GaugeFactory.makeWeeklyGauge(
                    percentage: usage.weeklyPercentage,
                    label: account.type == .glm ? "Tool Use" : "Weekly",
                    resetDisplay: weeklyResetDisplay(usage: usage),
                    color: weeklyColor(for: usage.weeklyPercentage),
                    theme: theme
                )
            }
        }
    }

    /// Arranges gauges based on theme's gaugeArrangement setting
    @ViewBuilder
    private func gaugeArrangementView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        switch theme.layout.gaugeArrangement {
        case .horizontal:
            HStack(alignment: .top, spacing: theme.layout.gaugeSpacing) {
                content()
            }
        case .vertical:
            VStack(alignment: .center, spacing: theme.layout.gaugeSpacing) {
                content()
            }
        case .overlapping, .single:
            // For overlapping/single, wrap in ZStack
            ZStack {
                content()
            }
        }
    }

    /// Returns the appropriate weekly reset display text
    private func weeklyResetDisplay(usage: UsageData) -> String {
        if account.type == .glm, let used = usage.glmMonthlyUsed, let limit = usage.glmMonthlyLimit {
            return String(format: "%.0f/%.0f", used, limit)
        }
        return usage.weeklyReset
    }

    // MARK: - Account Info Section

    /// Builds the account info and session gauge section
    @ViewBuilder
    private func accountInfoSection(usage: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row: Account name + tier badge
            HStack {
                HStack(spacing: 4) {
                    if account.type == .cursor {
                        Image(systemName: "cpu")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(account.name)
                        .font(theme.fontConfig.titleFont(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .layoutPriority(1)
                .padding(.bottom, 6)

                Spacer()

                Text(usage.tier.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(theme.fontConfig.labelFont(size: 10, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(tierColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }

            // Session usage row
            HStack(spacing: 6) {
                Text(sessionLabel)
                    .font(theme.fontConfig.labelFont(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

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
                    .font(theme.fontConfig.numberFont(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            // Reset time row with status indicator
            HStack(spacing: 6) {
                Text(
                    usage.sessionResetDisplay == "Ready"
                        ? "Ready to start new session" : usage.sessionResetDisplay
                )
                .font(theme.fontConfig.bodyFont(size: 12))
                .foregroundColor(.secondary)

                Spacer()

                statusIndicator
            }

            // Session gauge using GaugeFactory
            if theme.layout.showSessionGauge {
                GaugeFactory.makeSessionGauge(
                    percentage: usage.sessionPercentage,
                    resetDisplay: usage.sessionResetDisplay,
                    color: sessionThemeColor(for: usage.sessionPercentage),
                    theme: theme
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns the appropriate session label based on account type
    private var sessionLabel: String {
        switch account.type {
        case .glm:
            return Constants.GLM.sessionWindowLabel
        case .cursor:
            return "Request Usage"
        default:
            return "Session Usage"
        }
    }

    /// Status indicator showing fetch state
    @ViewBuilder
    private var statusIndicator: some View {
        if isFetching {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
        } else if lastError != nil {
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

    // MARK: - Inline Layout

    /// Compact inline layout for minimal themes
    @ViewBuilder
    private func inlineLayout(usage: UsageData) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header with account name and tier
            HStack {
                Text(account.name)
                    .font(theme.fontConfig.titleFont(size: 15, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                Text(usage.tier.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(theme.fontConfig.labelFont(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tierColor)
                    .foregroundColor(.white)
                    .cornerRadius(6)

                statusIndicator
            }

            // Inline metrics row
            HStack(spacing: 12) {
                InlinePercentageGauge(
                    percentage: usage.sessionPercentage,
                    label: "Session",
                    color: sessionThemeColor(for: usage.sessionPercentage),
                    theme: theme
                )

                if let sonnetPct = usage.sonnetPercentage {
                    InlinePercentageGauge(
                        percentage: sonnetPct,
                        label: "Sonnet",
                        color: theme.sonnetGaugeColor,
                        theme: theme
                    )
                }

                InlinePercentageGauge(
                    percentage: usage.weeklyPercentage,
                    label: account.type == .glm ? "Tool Use" : "Weekly",
                    color: weeklyColor(for: usage.weeklyPercentage),
                    theme: theme
                )

                Spacer()
            }
        }
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
    /// Whether the account needs re-authentication
    var needsReauth: Bool = false
    /// Optional callback to retry the failed operation
    var onRetry: (() -> Void)?
    /// Optional callback to re-authenticate the account
    var onReauthenticate: (() -> Void)?
    /// The current theme for styling
    let theme: ThemeColors

    @State private var isHoveringRetry = false
    @State private var isHoveringReauth = false

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: needsReauth ? "key.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundColor(needsReauth ? .red : .orange)
                .frame(width: 44, height: 44)
                .accessibilityLabel(needsReauth ? "Authentication required" : "Error")

            VStack(alignment: .leading, spacing: 6) {
                Text(accountName)
                    .font(theme.fontConfig.titleFont(size: 17, weight: .semibold))
                    .lineLimit(1)

                Text(needsReauth ? "Authentication expired" : "Failed to fetch usage data")
                    .font(theme.fontConfig.bodyFont(size: 15))
                    .foregroundColor(.secondary)

                Text(needsReauth ? "Please re-authenticate to continue" : error.localizedDescription)
                    .font(theme.fontConfig.bodyFont(size: 12))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(2)
            }

            Spacer()

            HStack(spacing: 8) {
                // Re-authenticate button (shown when auth failed)
                if needsReauth, let onReauthenticate = onReauthenticate {
                    Button(action: onReauthenticate) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(isHoveringReauth ? Color.green : Color.green.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Re-authenticate account")
                    .help("Re-authenticate")
                    .onHover { hovering in
                        isHoveringReauth = hovering
                    }
                }

                // Retry button
                if let onRetry = onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 28, height: 28)
                            .background(isHoveringRetry ? Color.blue : Color.blue.opacity(0.8))
                            .foregroundColor(.white)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry fetching usage data")
                    .help("Retry")
                    .onHover { hovering in
                        isHoveringRetry = hovering
                    }
                }
            }
        }
    }
}

/// Displays a circular gauge with label for weekly model-specific quotas.
struct WeeklyGaugeView: View {
    let label: String
    let percentage: Double
    let resetDisplay: String
    let color: Color
    let theme: ThemeColors
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 11, weight: .semibold))
                .foregroundColor(color)

            ZStack {
                Gauge(value: percentage) {
                    EmptyView()
                } currentValueLabel: {
                    // Show themed icon if available, otherwise percentage
                    if let iconName = theme.gaugeIcon {
                        Image(systemName: iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.gaugeIconColor ?? color)
                    } else {
                        Text(percentage.formattedPercentage)
                            .font(theme.fontConfig.numberFont(size: 9, weight: .bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .gaugeStyle(.accessoryCircular)
                .tint(color)
                .frame(width: theme.gaugeSize, height: theme.gaugeSize)
            }
            .themeGaugeGlow(color: color, theme: theme)

            Text(resetDisplay)
                .font(theme.fontConfig.bodyFont(size: 9, weight: .medium))
                .foregroundColor(theme.secondaryText(for: colorScheme))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 72)
        .fixedSize()
    }
}

/// Custom themed progress bar with gradient support
struct ThemedProgressBar: View {
    let percentage: Double
    let theme: ThemeColors
    let baseColor: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 4)
                    .fill(theme.cardBorder(for: colorScheme).opacity(0.3))

                // Progress fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(progressFill)
                    .frame(width: geometry.size.width * min(1.0, max(0.0, percentage)))
            }
        }
        .frame(height: 8)
    }

    private var progressFill: some ShapeStyle {
        if theme.progressBarGradient {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [theme.progressBarStartColor, theme.progressBarEndColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        } else {
            return AnyShapeStyle(baseColor)
        }
    }
}
