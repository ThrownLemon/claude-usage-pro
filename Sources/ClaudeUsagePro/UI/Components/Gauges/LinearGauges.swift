import SwiftUI

/// A standard linear progress bar gauge.
/// This is the default session gauge style.
struct LinearBarGauge: View {
    let percentage: Double
    let color: Color
    let theme: ThemeColors

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
                    .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)
            }
        }
        .frame(height: 8)
        .themeGlow(color: color, theme: theme)
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
            return AnyShapeStyle(color)
        }
    }
}

/// An LED-style progress bar with discrete blocks.
/// Perfect for Terminal theme's retro hacker aesthetic.
struct LinearLEDGauge: View {
    let percentage: Double
    let color: Color
    let blockCount: Int
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    private let spacing: CGFloat = 2

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(0..<blockCount, id: \.self) { index in
                    let blockPercentage = Double(index) / Double(blockCount)
                    let isFilled = blockPercentage < percentage

                    RoundedRectangle(cornerRadius: 1)
                        .fill(isFilled ? blockColor(for: blockPercentage) : color.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .shadow(
                            color: isFilled && theme.glowEnabled ? color.opacity(0.6) : .clear,
                            radius: 2
                        )
                }
            }
        }
        .frame(height: 12)
    }

    private func blockColor(for blockPercentage: Double) -> Color {
        // Color progression: green → yellow → red
        if blockPercentage < 0.5 {
            return color
        } else if blockPercentage < 0.75 {
            return theme.totalGaugeWarning
        } else {
            return theme.totalGaugeCritical
        }
    }
}

/// A segmented linear progress bar with distinct sections.
struct LinearSegmentedGauge: View {
    let percentage: Double
    let color: Color
    let segmentCount: Int
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    private let spacing: CGFloat = 3

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: spacing) {
                ForEach(0..<segmentCount, id: \.self) { index in
                    let segmentPercentage = Double(index) / Double(segmentCount)
                    let fillAmount = min(1.0, max(0, (percentage - segmentPercentage) * Double(segmentCount)))

                    GeometryReader { segmentGeometry in
                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color.opacity(0.15))

                            // Fill
                            RoundedRectangle(cornerRadius: 2)
                                .fill(segmentColor(for: segmentPercentage))
                                .frame(width: segmentGeometry.size.width * fillAmount)
                        }
                    }
                }
            }
        }
        .frame(height: 10)
        .themeGlow(color: color, theme: theme)
    }

    private func segmentColor(for segmentPercentage: Double) -> Color {
        if segmentPercentage < 0.5 {
            return theme.totalGaugeHealthy
        } else if segmentPercentage < 0.75 {
            return theme.totalGaugeWarning
        } else {
            return theme.totalGaugeCritical
        }
    }
}
