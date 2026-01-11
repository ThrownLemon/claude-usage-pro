import SwiftUI

// MARK: - Gauge Style Types

/// Available gauge visualization styles for usage displays.
/// Each theme can specify different styles for session and weekly gauges.
enum GaugeStyleType: String, Codable, CaseIterable {
    // MARK: Circular Variants

    /// Full ring gauge - the current default for weekly gauges
    case circularFull

    /// 270-degree arc gauge - elegant partial circle
    case circularArc

    /// Segmented ring with discrete sections
    case circularSegmented

    /// Two concentric rings - for showing two values together
    case circularDual

    // MARK: Linear Variants

    /// Horizontal progress bar - current default for session gauge
    case linearBar

    /// Dotted or block-based progress indicator
    case linearSegmented

    /// LED-style discrete blocks - perfect for Terminal theme
    case linearLED

    // MARK: Numeric Displays

    /// Large prominent number display - elegant style for Rose Gold
    case numericLarge

    /// Digital readout style - for Terminal theme
    case numericDigital

    /// Just the percentage, minimal decoration
    case numericMinimal

    // MARK: Special Styles

    /// Mini historical line chart showing usage over time
    case sparkline

    /// Thin ring indicator without fill
    case ring

    // MARK: - Display Properties

    /// Human-readable name for the gauge style
    var displayName: String {
        switch self {
        case .circularFull: return "Circular"
        case .circularArc: return "Arc"
        case .circularSegmented: return "Segmented Ring"
        case .circularDual: return "Dual Ring"
        case .linearBar: return "Progress Bar"
        case .linearSegmented: return "Segmented Bar"
        case .linearLED: return "LED Blocks"
        case .numericLarge: return "Large Number"
        case .numericDigital: return "Digital"
        case .numericMinimal: return "Minimal"
        case .sparkline: return "Sparkline"
        case .ring: return "Thin Ring"
        }
    }

    /// Whether this style is primarily numeric (text-based)
    var isNumeric: Bool {
        switch self {
        case .numericLarge, .numericDigital, .numericMinimal:
            return true
        default:
            return false
        }
    }

    /// Whether this style is circular
    var isCircular: Bool {
        switch self {
        case .circularFull, .circularArc, .circularSegmented, .circularDual, .ring:
            return true
        default:
            return false
        }
    }

    /// Whether this style is linear (horizontal bar)
    var isLinear: Bool {
        switch self {
        case .linearBar, .linearSegmented, .linearLED:
            return true
        default:
            return false
        }
    }
}

// MARK: - Gauge Component Configuration

/// Configuration for gauge components within a theme.
/// Specifies which gauge styles to use and optional features like sparklines.
struct GaugeComponentConfig: Equatable {
    /// Style for the session usage gauge
    let sessionGaugeStyle: GaugeStyleType

    /// Style for the weekly usage gauge
    let weeklyGaugeStyle: GaugeStyleType

    /// Style for the Sonnet gauge (Claude Max only), nil to use weeklyGaugeStyle
    let sonnetGaugeStyle: GaugeStyleType?

    /// Whether to show a sparkline chart for usage history
    let showSparkline: Bool

    /// Number of data points to show in sparkline (typically 24-48)
    let sparklineDataPoints: Int

    /// Whether to animate gauge value changes
    let animateChanges: Bool

    /// Duration of gauge animations in seconds
    let animationDuration: Double

    /// Whether to show percentage text inside circular gauges
    let showPercentageInGauge: Bool

    /// Number of segments for segmented gauge styles
    let segmentCount: Int

    /// LED block count for linearLED style
    let ledBlockCount: Int

    // MARK: - Initializer

    init(
        sessionGaugeStyle: GaugeStyleType = .linearBar,
        weeklyGaugeStyle: GaugeStyleType = .circularFull,
        sonnetGaugeStyle: GaugeStyleType? = nil,
        showSparkline: Bool = false,
        sparklineDataPoints: Int = 24,
        animateChanges: Bool = true,
        animationDuration: Double = 0.3,
        showPercentageInGauge: Bool = true,
        segmentCount: Int = 10,
        ledBlockCount: Int = 20
    ) {
        self.sessionGaugeStyle = sessionGaugeStyle
        self.weeklyGaugeStyle = weeklyGaugeStyle
        self.sonnetGaugeStyle = sonnetGaugeStyle
        self.showSparkline = showSparkline
        // Validate numerical inputs to ensure sensible ranges
        self.sparklineDataPoints = max(1, min(sparklineDataPoints, 100))
        self.animateChanges = animateChanges
        self.animationDuration = max(0.0, min(animationDuration, 5.0))
        self.showPercentageInGauge = showPercentageInGauge
        self.segmentCount = max(1, min(segmentCount, 100))
        self.ledBlockCount = max(1, min(ledBlockCount, 100))
    }

    // MARK: - Presets

    /// Default configuration matching current app design
    static let `default` = GaugeComponentConfig()

    /// Terminal theme: LED blocks, digital readout
    static let terminal = GaugeComponentConfig(
        sessionGaugeStyle: .linearLED,
        weeklyGaugeStyle: .numericDigital,
        showPercentageInGauge: false,
        ledBlockCount: 20
    )

    /// Rose Gold theme: elegant large numbers, arc gauge
    static let elegant = GaugeComponentConfig(
        sessionGaugeStyle: .numericLarge,
        weeklyGaugeStyle: .circularArc,
        showPercentageInGauge: false
    )

    /// Minimal theme: just numbers, thin ring
    static let minimal = GaugeComponentConfig(
        sessionGaugeStyle: .numericMinimal,
        weeklyGaugeStyle: .ring,
        showPercentageInGauge: false
    )

    /// Vibrant theme: segmented colorful gauges
    static let vibrant = GaugeComponentConfig(
        sessionGaugeStyle: .linearSegmented,
        weeklyGaugeStyle: .circularSegmented,
        segmentCount: 12
    )

    /// Midnight theme: dual rings for nested display
    static let midnight = GaugeComponentConfig(
        sessionGaugeStyle: .linearBar,
        weeklyGaugeStyle: .circularDual
    )

    /// Premium theme: default with sparkline
    static let premium = GaugeComponentConfig(
        sessionGaugeStyle: .linearBar,
        weeklyGaugeStyle: .circularFull,
        showSparkline: true,
        sparklineDataPoints: 24
    )

    /// Ocean theme: wave-like progress
    static let ocean = GaugeComponentConfig(
        sessionGaugeStyle: .linearBar,
        weeklyGaugeStyle: .circularFull,
        animationDuration: 0.5  // Slower, wave-like animations
    )

    // MARK: - Computed Properties

    /// Effective Sonnet gauge style (falls back to weekly style)
    var effectiveSonnetStyle: GaugeStyleType {
        sonnetGaugeStyle ?? weeklyGaugeStyle
    }

    /// Whether any sparkline features are enabled
    var hasSparkline: Bool {
        showSparkline && sparklineDataPoints > 0
    }
}

// MARK: - Progress Style

/// Style configuration for linear progress indicators
struct ProgressStyle: Equatable {
    /// Height of the progress bar
    let height: CGFloat

    /// Corner radius of the progress bar
    let cornerRadius: CGFloat

    /// Whether to show a gradient fill
    let useGradient: Bool

    /// Start color for gradient (or solid color if no gradient)
    let startColor: Color?

    /// End color for gradient
    let endColor: Color?

    /// Whether to show a glow effect
    let showGlow: Bool

    /// Whether to show tick marks
    let showTicks: Bool

    /// Number of tick marks (if enabled)
    let tickCount: Int

    // MARK: - Presets

    static let `default` = ProgressStyle(
        height: 8,
        cornerRadius: 4,
        useGradient: false,
        startColor: nil,
        endColor: nil,
        showGlow: false,
        showTicks: false,
        tickCount: 0
    )

    static let led = ProgressStyle(
        height: 12,
        cornerRadius: 2,
        useGradient: false,
        startColor: nil,
        endColor: nil,
        showGlow: true,
        showTicks: false,
        tickCount: 0
    )

    static let segmented = ProgressStyle(
        height: 10,
        cornerRadius: 2,
        useGradient: false,
        startColor: nil,
        endColor: nil,
        showGlow: false,
        showTicks: true,
        tickCount: 10
    )
}
