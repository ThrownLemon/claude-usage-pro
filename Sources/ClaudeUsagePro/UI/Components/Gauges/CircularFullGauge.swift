import SwiftUI

/// A circular gauge showing usage as a full ring.
/// This is the default weekly gauge style.
struct CircularFullGauge: View {
    let percentage: Double
    let label: String
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
                    if let iconName = theme.gaugeIcon {
                        Image(systemName: iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(theme.gaugeIconColor ?? color)
                    } else if theme.components.showPercentageInGauge {
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

/// A circular arc gauge showing usage as a partial circle (270 degrees).
/// Elegant style for themes like Rose Gold.
struct CircularArcGauge: View {
    let percentage: Double
    let label: String
    let resetDisplay: String
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    private let startAngle: Double = 135  // Start from bottom-left
    private let endAngle: Double = 405    // End at bottom-right (270° arc)

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 11, weight: .semibold))
                .foregroundColor(color)

            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0, to: 0.75)
                    .stroke(
                        color.opacity(0.2),
                        style: StrokeStyle(lineWidth: theme.gaugeLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: theme.gaugeSize, height: theme.gaugeSize)

                // Progress arc
                Circle()
                    .trim(from: 0, to: percentage * 0.75)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: theme.gaugeLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(startAngle))
                    .frame(width: theme.gaugeSize, height: theme.gaugeSize)
                    .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)

                // Center text
                Text(percentage.formattedPercentage)
                    .font(theme.fontConfig.numberFont(size: 11, weight: .bold))
                    .foregroundColor(theme.primaryText(for: colorScheme))
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

/// A circular gauge with segmented ring display.
/// Shows discrete segments that fill as usage increases.
struct CircularSegmentedGauge: View {
    let percentage: Double
    let label: String
    let resetDisplay: String
    let color: Color
    let segmentCount: Int
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            Text(label)
                .font(theme.fontConfig.labelFont(size: 11, weight: .semibold))
                .foregroundColor(color)

            ZStack {
                // Draw segmented ring
                ForEach(0..<segmentCount, id: \.self) { index in
                    SegmentArc(
                        index: index,
                        total: segmentCount
                    )
                    .stroke(
                        Double(index) / Double(segmentCount) < percentage ? color : color.opacity(0.2),
                        style: StrokeStyle(lineWidth: theme.gaugeLineWidth, lineCap: .butt)
                    )
                    .frame(width: theme.gaugeSize, height: theme.gaugeSize)
                }

                // Center percentage
                Text(percentage.formattedPercentage)
                    .font(theme.fontConfig.numberFont(size: 10, weight: .bold))
                    .foregroundColor(theme.primaryText(for: colorScheme))
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

/// Helper shape for drawing segment arcs
struct SegmentArc: Shape {
    let index: Int
    let total: Int

    func path(in rect: CGRect) -> Path {
        let gapAngle: Double = 3  // Gap between segments in degrees
        let totalAngle: Double = 270  // Total arc span
        let segmentAngle = (totalAngle - Double(total) * gapAngle) / Double(total)

        let startAngle = 135 + Double(index) * (segmentAngle + gapAngle)
        let endAngle = startAngle + segmentAngle

        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(startAngle),
            endAngle: .degrees(endAngle),
            clockwise: false
        )
        return path
    }
}

/// A thin ring gauge without fill - just an outline that shows progress.
struct RingGauge: View {
    let percentage: Double
    let label: String
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
                // Background ring
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 2)
                    .frame(width: theme.gaugeSize, height: theme.gaugeSize)

                // Progress ring
                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: theme.gaugeSize, height: theme.gaugeSize)
                    .animation(.easeInOut(duration: theme.components.animationDuration), value: percentage)

                // Center percentage
                Text(percentage.formattedPercentage)
                    .font(theme.fontConfig.numberFont(size: 11, weight: .semibold))
                    .foregroundColor(theme.primaryText(for: colorScheme))
            }

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
