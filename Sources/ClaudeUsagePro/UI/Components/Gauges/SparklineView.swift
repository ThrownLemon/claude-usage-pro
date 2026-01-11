import SwiftUI

/// A mini line chart showing usage history over time.
/// Displays a sparkline visualization of historical usage percentages.
struct SparklineView: View {
    let dataPoints: [UsageDataPoint]
    let valueKeyPath: KeyPath<UsageDataPoint, Double>
    let color: Color
    let theme: ThemeColors
    let height: CGFloat
    let showArea: Bool

    @Environment(\.colorScheme) private var colorScheme

    init(
        dataPoints: [UsageDataPoint],
        valueKeyPath: KeyPath<UsageDataPoint, Double> = \.sessionPercentage,
        color: Color,
        theme: ThemeColors,
        height: CGFloat = 24,
        showArea: Bool = true
    ) {
        self.dataPoints = dataPoints
        self.valueKeyPath = valueKeyPath
        self.color = color
        self.theme = theme
        self.height = height
        self.showArea = showArea
    }

    var body: some View {
        GeometryReader { geometry in
            if dataPoints.count >= 2 {
                ZStack {
                    // Area fill (optional)
                    if showArea {
                        Path { path in
                            drawPath(in: geometry.size, path: &path, closePath: true)
                        }
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.3), color.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    // Line
                    Path { path in
                        drawPath(in: geometry.size, path: &path, closePath: false)
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .shadow(color: theme.glowEnabled ? color.opacity(0.5) : .clear, radius: 2)

                    // Current value dot
                    if let lastPoint = dataPoints.last {
                        let x = geometry.size.width
                        let y = geometry.size.height * (1 - lastPoint[keyPath: valueKeyPath])

                        Circle()
                            .fill(color)
                            .frame(width: 4, height: 4)
                            .position(x: x, y: y)
                            .shadow(color: theme.glowEnabled ? color.opacity(0.8) : .clear, radius: 3)
                    }
                }
            } else {
                // Not enough data - show placeholder
                HStack(spacing: 4) {
                    ForEach(0..<8, id: \.self) { _ in
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }

    private func drawPath(in size: CGSize, path: inout Path, closePath: Bool) {
        guard dataPoints.count >= 2 else { return }

        let stepX = size.width / CGFloat(dataPoints.count - 1)

        for (index, point) in dataPoints.enumerated() {
            let x = stepX * CGFloat(index)
            let y = size.height * (1 - point[keyPath: valueKeyPath])

            if index == 0 {
                if closePath {
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: x, y: y))
                } else {
                    path.move(to: CGPoint(x: x, y: y))
                }
            } else {
                // Use curve for smoother line
                let prevPoint = dataPoints[index - 1]
                let prevX = stepX * CGFloat(index - 1)
                let prevY = size.height * (1 - prevPoint[keyPath: valueKeyPath])

                let controlX = (prevX + x) / 2
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: controlX, y: prevY),
                    control2: CGPoint(x: controlX, y: y)
                )
            }
        }

        if closePath {
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
    }
}

/// A compact sparkline with label showing the most recent value.
struct LabeledSparklineView: View {
    let dataPoints: [UsageDataPoint]
    let label: String
    let valueKeyPath: KeyPath<UsageDataPoint, Double>
    let color: Color
    let theme: ThemeColors

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(theme.fontConfig.labelFont(size: 10, weight: .medium))
                    .foregroundColor(theme.secondaryText(for: colorScheme))

                Spacer()

                if let lastValue = dataPoints.last?[keyPath: valueKeyPath] {
                    Text("\(Int((lastValue * 100).rounded()))%")
                        .font(theme.fontConfig.numberFont(size: 10, weight: .semibold))
                        .foregroundColor(color)
                }
            }

            SparklineView(
                dataPoints: dataPoints,
                valueKeyPath: valueKeyPath,
                color: color,
                theme: theme,
                height: 20,
                showArea: true
            )
        }
    }
}

/// A bar-style sparkline showing discrete data points as vertical bars.
struct BarSparklineView: View {
    let dataPoints: [UsageDataPoint]
    let valueKeyPath: KeyPath<UsageDataPoint, Double>
    let color: Color
    let theme: ThemeColors
    let height: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    init(
        dataPoints: [UsageDataPoint],
        valueKeyPath: KeyPath<UsageDataPoint, Double> = \.sessionPercentage,
        color: Color,
        theme: ThemeColors,
        height: CGFloat = 24
    ) {
        self.dataPoints = dataPoints
        self.valueKeyPath = valueKeyPath
        self.color = color
        self.theme = theme
        self.height = height
    }

    var body: some View {
        GeometryReader { geometry in
            if !dataPoints.isEmpty {
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(dataPoints) { point in
                        let barHeight = geometry.size.height * point[keyPath: valueKeyPath]

                        RoundedRectangle(cornerRadius: 1)
                            .fill(barColor(for: point[keyPath: valueKeyPath]))
                            .frame(height: max(2, barHeight))
                    }
                }
            } else {
                // Placeholder with deterministic heights based on index
                HStack(spacing: 2) {
                    ForEach(0..<12, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(color.opacity(0.2))
                            .frame(height: placeholderBarHeight(index: index, maxHeight: height * 0.6))
                    }
                }
            }
        }
        .frame(height: height)
    }

    private func barColor(for percentage: Double) -> Color {
        if percentage < 0.5 {
            return theme.totalGaugeHealthy
        } else if percentage < 0.75 {
            return theme.totalGaugeWarning
        } else {
            return theme.totalGaugeCritical
        }
    }

    /// Generates deterministic placeholder bar heights using a simple hash
    private func placeholderBarHeight(index: Int, maxHeight: CGFloat) -> CGFloat {
        // Use a simple deterministic pattern based on index
        let pattern: [CGFloat] = [0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.5, 0.9, 0.4, 0.6, 0.7, 0.5]
        let normalizedValue = pattern[index % pattern.count]
        return max(4, maxHeight * normalizedValue)
    }
}
