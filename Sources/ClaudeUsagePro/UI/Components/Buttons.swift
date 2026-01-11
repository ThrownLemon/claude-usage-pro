import AppKit
import SwiftUI

/// A button with an SF Symbol icon that responds to hover state.
struct HoverIconButton: View {
    /// SF Symbol name for the icon
    let image: String
    /// Tooltip text shown on hover
    let helpText: String
    /// Color to use when hovered
    var color: Color = .primary
    /// Action to perform when tapped
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .medium))
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
        .contentShape(Rectangle())
        .help(helpText)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// A styled quit button that terminates the application.
struct QuitButton: View {
    @State private var isHovering = false

    var body: some View {
        Button(action: {
            NSApplication.shared.terminate(nil)
        }) {
            Image(systemName: "power")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(isHovering ? .red : .secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHovering ? Color.red.opacity(0.1) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isHovering ? Color.red.opacity(0.2) : Color.secondary.opacity(0.1),
                            lineWidth: 1)
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

/// A styled button for selecting an account type during account creation.
struct AccountTypeButton: View {
    /// The button's primary label
    let title: String
    /// Secondary description text
    let subtitle: String
    /// SF Symbol name for the icon
    let icon: String
    /// Accent color for hover state
    let color: Color
    /// Action to perform when tapped
    let action: () -> Void

    @State private var isHovering = false
    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

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
                            .stroke(
                                isHovering ? color.opacity(0.3) : Color.secondary.opacity(0.1),
                                lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.body, design: theme.fontDesign.design).bold())
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
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isHovering ? color.opacity(0.3) : theme.cardBorder(for: colorScheme),
                        lineWidth: 1)
            )
            .themeOverlay(theme)
            .scaleEffect(isHovering ? 1.015 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// A card with a dashed border for adding new accounts.
struct AddAccountCardView: View {
    /// Action to perform when the card is tapped
    let action: () -> Void
    @State private var isHovering = false

    @AppStorage(ThemeManager.themeKey) private var selectedTheme: String = AppTheme.standard
        .rawValue
    @Environment(\.colorScheme) private var colorScheme

    private var theme: ThemeColors {
        ThemeManager.colors(for: AppTheme(rawValue: selectedTheme) ?? .standard)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(theme.accentPrimary.opacity(0.8))
                    Text("Add Account")
                        .font(.system(.body, design: theme.fontDesign.design).bold())
                        .foregroundColor(theme.accentPrimary.opacity(0.8))
                }
                Spacer()
            }
            .padding(.vertical, 24)
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        isHovering ? theme.accentPrimary : theme.accentPrimary.opacity(0.5),
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: theme.addAccountBorderStyle == .dashed ? [8, 4] : []
                        )
                    )
            )
            .themeOverlay(theme)
            .shadow(
                color: theme.cardHasShadow ? theme.cardShadowColor : .clear,
                radius: theme.cardShadowRadius
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hover in
            isHovering = hover
        }
    }
}

/// Displays a countdown timer to the next automatic refresh.
struct CountdownView: View {
    /// The target date/time for the countdown
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
