import SwiftUI

/// A large, elegant numeric display for percentage.
/// Perfect for Rose Gold theme's refined aesthetic.
struct NumericLargeGauge: View {
    let percentage: Double
    let label: String
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 10, weight: .medium))
                .foregroundColor(theme.secondaryText(for: colorScheme))
                .textCase(.uppercase)
                .tracking(theme.fontConfig.letterSpacing)

            Text(percentage.formattedPercentage)
                .font(theme.fontConfig.numberFont(size: 28, weight: .light))
                .foregroundColor(color)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)

            // Thin progress indicator
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.2))

                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: geometry.size.width * min(1.0, max(0.0, percentage)))
                        .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)
                }
            }
            .frame(height: 2)
            .frame(maxWidth: 60)
        }
        .frame(width: 80)
    }
}

/// A digital/LCD-style numeric display.
/// Perfect for Terminal theme's retro computer aesthetic.
struct NumericDigitalGauge: View {
    let percentage: Double
    let label: String
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 9, weight: .regular))
                .foregroundColor(color.opacity(0.7))
                .tracking(2)

            // Digital-style percentage
            HStack(spacing: 0) {
                Text(String(format: "%03d", Int((percentage * 100).rounded())))
                    .font(.custom("Menlo", size: 24).weight(.bold).monospacedDigit())
                    .foregroundColor(color)
                    .contentTransition(.numericText())

                Text("%")
                    .font(.custom("Menlo", size: 14).weight(.bold))
                    .foregroundColor(color.opacity(0.8))
                    .offset(y: 2)
            }
            .shadow(color: theme.glowEnabled ? color.opacity(0.5) : .clear, radius: 4)

            // LED-style indicator bar
            HStack(spacing: 2) {
                ForEach(0..<10, id: \.self) { index in
                    let blockPercentage = Double(index) / 10.0
                    Rectangle()
                        .fill(blockPercentage < percentage ? color : color.opacity(0.15))
                        .frame(width: 6, height: 4)
                        .shadow(
                            color: blockPercentage < percentage && theme.glowEnabled ? color.opacity(0.5) : .clear,
                            radius: 2
                        )
                }
            }
        }
        .frame(width: 80)
    }
}

/// A minimal numeric-only display.
/// Shows just the percentage with minimal decoration.
struct NumericMinimalGauge: View {
    let percentage: Double
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(percentage.formattedPercentage)
            .font(theme.fontConfig.numberFont(size: 14, weight: .semibold))
            .foregroundColor(color)
            .contentTransition(.numericText())
            .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)
    }
}

/// A compact inline percentage display with a small progress bar.
/// Used for inline layouts where space is limited.
struct InlinePercentageGauge: View {
    let percentage: Double
    let label: String
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 11, weight: .medium))
                .foregroundColor(theme.secondaryText(for: colorScheme))

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.2))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * min(1.0, max(0.0, percentage)))
                }
            }
            .frame(width: 40, height: 4)

            Text(percentage.formattedPercentage)
                .font(theme.fontConfig.numberFont(size: 11, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
