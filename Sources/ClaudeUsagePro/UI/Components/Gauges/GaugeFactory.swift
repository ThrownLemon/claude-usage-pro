import SwiftUI

/// Factory for creating gauge views based on theme configuration.
/// Uses the theme's `components` property to determine which gauge styles to render.
struct GaugeFactory {

    // MARK: - Session Gauge

    /// Creates the appropriate session gauge based on theme configuration.
    /// - Parameters:
    ///   - percentage: Current usage percentage (0.0 to 1.0)
    ///   - resetDisplay: Text to display for reset time
    ///   - color: Color for the gauge
    ///   - theme: Current theme colors and configuration
    /// - Returns: A view representing the session gauge
    @ViewBuilder
    static func makeSessionGauge(
        percentage: Double,
        resetDisplay: String,
        color: Color,
        theme: ThemeColors
    ) -> some View {
        switch theme.components.sessionGaugeStyle {
        case .linearBar:
            LinearBarGauge(
                percentage: percentage,
                color: color,
                theme: theme
            )

        case .linearLED:
            LinearLEDGauge(
                percentage: percentage,
                color: color,
                blockCount: theme.components.ledBlockCount,
                theme: theme
            )

        case .linearSegmented:
            LinearSegmentedGauge(
                percentage: percentage,
                color: color,
                segmentCount: theme.components.segmentCount,
                theme: theme
            )

        case .numericLarge:
            NumericLargeGauge(
                percentage: percentage,
                label: "Session",
                color: color,
                theme: theme
            )

        case .numericDigital:
            NumericDigitalGauge(
                percentage: percentage,
                label: "SESSION",
                color: color,
                theme: theme
            )

        case .numericMinimal:
            NumericMinimalGauge(
                percentage: percentage,
                color: color,
                theme: theme
            )

        default:
            // Fallback to linear bar for unsupported types
            LinearBarGauge(
                percentage: percentage,
                color: color,
                theme: theme
            )
        }
    }

    // MARK: - Weekly Gauge

    /// Creates the appropriate weekly gauge based on theme configuration.
    /// - Parameters:
    ///   - percentage: Current usage percentage (0.0 to 1.0)
    ///   - label: Label for the gauge (e.g., "Weekly", "Sonnet", "Total")
    ///   - resetDisplay: Text to display for reset time
    ///   - color: Color for the gauge
    ///   - theme: Current theme colors and configuration
    /// - Returns: A view representing the weekly gauge
    @ViewBuilder
    static func makeWeeklyGauge(
        percentage: Double,
        label: String,
        resetDisplay: String,
        color: Color,
        theme: ThemeColors
    ) -> some View {
        switch theme.components.weeklyGaugeStyle {
        case .circularFull:
            CircularFullGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .circularArc:
            CircularArcGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .circularSegmented:
            CircularSegmentedGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                segmentCount: theme.components.segmentCount,
                theme: theme
            )

        case .circularDual:
            // For dual, we'll render as full for now (dual needs two values)
            CircularFullGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .ring:
            RingGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .numericLarge:
            NumericLargeGauge(
                percentage: percentage,
                label: label,
                color: color,
                theme: theme
            )

        case .numericDigital:
            NumericDigitalGauge(
                percentage: percentage,
                label: label,
                color: color,
                theme: theme
            )

        case .numericMinimal:
            NumericMinimalGauge(
                percentage: percentage,
                color: color,
                theme: theme
            )

        default:
            // Fallback to circular full for unsupported types
            CircularFullGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )
        }
    }

    // MARK: - Sonnet Gauge

    /// Creates the appropriate Sonnet gauge based on theme configuration.
    /// Uses the theme's sonnetGaugeStyle or falls back to weeklyGaugeStyle.
    @ViewBuilder
    static func makeSonnetGauge(
        percentage: Double,
        label: String,
        resetDisplay: String,
        color: Color,
        theme: ThemeColors
    ) -> some View {
        let style = theme.components.effectiveSonnetStyle

        switch style {
        case .circularFull:
            CircularFullGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .circularArc:
            CircularArcGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        case .circularSegmented:
            CircularSegmentedGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                segmentCount: theme.components.segmentCount,
                theme: theme
            )

        case .ring:
            RingGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )

        default:
            CircularFullGauge(
                percentage: percentage,
                label: label,
                resetDisplay: resetDisplay,
                color: color,
                theme: theme
            )
        }
    }
}
