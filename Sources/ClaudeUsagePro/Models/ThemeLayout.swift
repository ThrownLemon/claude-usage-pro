import SwiftUI

// MARK: - Layout Enums

/// Defines where gauges appear relative to account info
enum GaugePosition: String, Codable, CaseIterable {
    /// Gauges on the left side (current default)
    case left
    /// Gauges on the right side
    case right
    /// Gauges above account info
    case top
    /// Gauges below account info
    case bottom
    /// Gauges integrated inline with text
    case inline
}

/// Defines card density/size for different theme styles
enum CardDensity: String, Codable, CaseIterable {
    /// Minimal padding, smaller gauges, compact layout
    case compact
    /// Current default sizing
    case normal
    /// More breathing room, larger visualizations
    case expanded

    /// Multiplier for padding based on density
    var paddingMultiplier: CGFloat {
        switch self {
        case .compact: return 0.75
        case .normal: return 1.0
        case .expanded: return 1.25
        }
    }

    /// Multiplier for gauge size based on density
    var gaugeSizeMultiplier: CGFloat {
        switch self {
        case .compact: return 0.85
        case .normal: return 1.0
        case .expanded: return 1.15
        }
    }
}

/// Layout arrangement for multiple gauges (weekly + sonnet)
enum GaugeArrangement: String, Codable, CaseIterable {
    /// Gauges side by side (current default)
    case horizontal
    /// Gauges stacked vertically
    case vertical
    /// Concentric or layered gauges (for dual ring displays)
    case overlapping
    /// Combined into one gauge display
    case single
}

/// Position of labels relative to gauges
enum LabelPosition: String, Codable, CaseIterable {
    /// Label above the gauge
    case above
    /// Label below the gauge
    case below
    /// Label inside the gauge (for circular gauges)
    case inside
    /// No label displayed
    case none
}

// MARK: - Theme Layout Configuration

/// Complete layout configuration for a theme.
/// Defines how usage cards are structured and arranged.
struct ThemeLayout: Equatable {
    /// Where gauges appear relative to account details
    let gaugePosition: GaugePosition

    /// Card density affecting padding and sizing
    let cardDensity: CardDensity

    /// How multiple gauges are arranged
    let gaugeArrangement: GaugeArrangement

    /// Whether to show the session gauge
    let showSessionGauge: Bool

    /// Whether to show the weekly gauge
    let showWeeklyGauge: Bool

    /// Size of session gauge (width/height for circular, height for linear)
    let sessionGaugeSize: CGFloat

    /// Size of weekly gauge (width/height for circular)
    let weeklyGaugeSize: CGFloat

    /// Minimum card height (nil for auto)
    let cardMinHeight: CGFloat?

    /// Maximum card width (nil for full width)
    let cardMaxWidth: CGFloat?

    /// Padding inside the card
    let contentPadding: EdgeInsets

    /// Spacing between gauges
    let gaugeSpacing: CGFloat

    /// Spacing between gauge and account info sections
    let sectionSpacing: CGFloat

    /// Position of labels relative to gauges
    let labelPosition: LabelPosition

    /// Whether to use a custom layout builder (for fully custom themes like Terminal)
    let useCustomLayout: Bool

    /// Custom layout identifier (e.g., "terminal", "roseGold")
    let customLayoutId: String?

    // MARK: - Initializer

    init(
        gaugePosition: GaugePosition = .left,
        cardDensity: CardDensity = .normal,
        gaugeArrangement: GaugeArrangement = .horizontal,
        showSessionGauge: Bool = true,
        showWeeklyGauge: Bool = true,
        sessionGaugeSize: CGFloat = 8,
        weeklyGaugeSize: CGFloat = 44,
        cardMinHeight: CGFloat? = nil,
        cardMaxWidth: CGFloat? = nil,
        contentPadding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        gaugeSpacing: CGFloat = 4,
        sectionSpacing: CGFloat = 10,
        labelPosition: LabelPosition = .above,
        useCustomLayout: Bool = false,
        customLayoutId: String? = nil
    ) {
        self.gaugePosition = gaugePosition
        self.cardDensity = cardDensity
        self.gaugeArrangement = gaugeArrangement
        self.showSessionGauge = showSessionGauge
        self.showWeeklyGauge = showWeeklyGauge
        self.sessionGaugeSize = sessionGaugeSize
        self.weeklyGaugeSize = weeklyGaugeSize
        self.cardMinHeight = cardMinHeight
        self.cardMaxWidth = cardMaxWidth
        self.contentPadding = contentPadding
        self.gaugeSpacing = gaugeSpacing
        self.sectionSpacing = sectionSpacing
        self.labelPosition = labelPosition
        self.useCustomLayout = useCustomLayout
        self.customLayoutId = customLayoutId
    }

    // MARK: - Presets

    /// Default layout matching current app design
    static let `default` = ThemeLayout()

    /// Compact layout with smaller elements and tighter spacing
    static let compact = ThemeLayout(
        cardDensity: .compact,
        sessionGaugeSize: 6,
        weeklyGaugeSize: 36,
        contentPadding: EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12),
        gaugeSpacing: 2,
        sectionSpacing: 8
    )

    /// Expanded layout with more breathing room
    static let expanded = ThemeLayout(
        cardDensity: .expanded,
        sessionGaugeSize: 10,
        weeklyGaugeSize: 52,
        contentPadding: EdgeInsets(top: 20, leading: 20, bottom: 20, trailing: 20),
        gaugeSpacing: 8,
        sectionSpacing: 14
    )

    /// Gauges on the right side
    static let rightGauges = ThemeLayout(
        gaugePosition: .right
    )

    /// Gauges on top, stacked vertically
    static let topGauges = ThemeLayout(
        gaugePosition: .top,
        gaugeArrangement: .horizontal,
        sectionSpacing: 12
    )

    /// Vertical stacked layout (for Terminal theme)
    static let verticalStack = ThemeLayout(
        gaugePosition: .bottom,
        gaugeArrangement: .vertical,
        sessionGaugeSize: 8,
        weeklyGaugeSize: 28,
        gaugeSpacing: 6,
        sectionSpacing: 8,
        labelPosition: .none,
        useCustomLayout: true,
        customLayoutId: "terminal"
    )

    /// Elegant expanded layout with right gauges (for Rose Gold theme)
    static let elegantRight = ThemeLayout(
        gaugePosition: .right,
        cardDensity: .expanded,
        weeklyGaugeSize: 48,
        contentPadding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        sectionSpacing: 14,
        useCustomLayout: true,
        customLayoutId: "elegant"
    )

    /// Minimal inline layout showing just numbers
    static let minimalInline = ThemeLayout(
        gaugePosition: .inline,
        cardDensity: .compact,
        showWeeklyGauge: false,
        sessionGaugeSize: 4,
        contentPadding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14),
        labelPosition: .none
    )

    // MARK: - Computed Properties

    /// Effective padding based on density
    var effectivePadding: EdgeInsets {
        let multiplier = cardDensity.paddingMultiplier
        return EdgeInsets(
            top: contentPadding.top * multiplier,
            leading: contentPadding.leading * multiplier,
            bottom: contentPadding.bottom * multiplier,
            trailing: contentPadding.trailing * multiplier
        )
    }

    /// Effective gauge size based on density
    func effectiveWeeklyGaugeSize(for density: CardDensity? = nil) -> CGFloat {
        let targetDensity = density ?? cardDensity
        return weeklyGaugeSize * targetDensity.gaugeSizeMultiplier
    }
}
