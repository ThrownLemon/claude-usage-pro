import AppKit
import SwiftUI

/// Available app themes
enum AppTheme: String, CaseIterable, Codable {
    case standard = "Standard"
    case minimal = "Minimal"
    case unified = "Unified"
    case premium = "Premium"
    case nature = "Nature"
    case vibrant = "Vibrant"
    case ocean = "Ocean"
    case sunset = "Sunset"
    case midnight = "Midnight"
    case roseGold = "Rose Gold"
    case terminal = "Terminal"

    var displayName: String {
        rawValue
    }

    var description: String {
        switch self {
        case .standard:
            return "Default dark theme"
        case .minimal:
            return "Clean, simple design"
        case .unified:
            return "Consistent circular gauges"
        case .premium:
            return "Glow effects & gradients"
        case .nature:
            return "Organic wood & forest textures"
        case .vibrant:
            return "Neon gradients & glow effects"
        case .ocean:
            return "Deep blue & aquamarine"
        case .sunset:
            return "Warm purple to orange gradients"
        case .midnight:
            return "Dark cosmic with neon accents"
        case .roseGold:
            return "Elegant pink & gold luxury"
        case .terminal:
            return "Retro hacker CRT style"
        }
    }
}

/// Color scheme mode options
enum ColorSchemeMode: String, CaseIterable, Codable {
    case system = "System"
    case dark = "Dark"
    case light = "Light"

    var displayName: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .dark:
            return "moon.fill"
        case .light:
            return "sun.max.fill"
        }
    }

    /// Returns the SwiftUI ColorScheme, or nil for system (follow system preference)
    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    /// Returns the effective ColorScheme considering system appearance
    func effectiveColorScheme(systemScheme: ColorScheme) -> ColorScheme {
        switch self {
        case .system:
            return systemScheme
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }
}

// MARK: - Custom Environment Key for Effective Color Scheme

private struct EffectiveColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .dark
}

extension EnvironmentValues {
    var effectiveColorScheme: ColorScheme {
        get { self[EffectiveColorSchemeKey.self] }
        set { self[EffectiveColorSchemeKey.self] = newValue }
    }
}

/// Border style for themed cards
enum BorderStyle: String, Codable {
    case solid
    case dashed
    case none
}

/// Font design for the theme (used as fallback)
enum ThemeFontDesign: String, Codable {
    case `default`
    case rounded
    case monospaced
    case serif

    var design: Font.Design {
        switch self {
        case .default: return .default
        case .rounded: return .rounded
        case .monospaced: return .monospaced
        case .serif: return .serif
        }
    }
}

/// Custom font configuration for themes
struct ThemeFontConfig {
    /// Font family name for titles/headers (nil = system font)
    let titleFontName: String?
    /// Font family name for body text
    let bodyFontName: String?
    /// Font family name for labels/captions
    let labelFontName: String?
    /// Font family name for numeric values (gauges, percentages)
    let numberFontName: String?
    /// Default font design fallback when custom font not available
    let fallbackDesign: ThemeFontDesign
    /// Whether to use small caps for labels
    let useSmallCaps: Bool
    /// Letter spacing adjustment (0 = normal)
    let letterSpacing: CGFloat

    /// Default font config using system rounded
    static let `default` = ThemeFontConfig(
        titleFontName: nil,
        bodyFontName: nil,
        labelFontName: nil,
        numberFontName: nil,
        fallbackDesign: .rounded,
        useSmallCaps: false,
        letterSpacing: 0
    )

    /// Create a title font with the configured family
    func titleFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        if let fontName = titleFontName {
            return .custom(fontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: fallbackDesign.design)
    }

    /// Create a body font with the configured family
    func bodyFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontName = bodyFontName {
            return .custom(fontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: fallbackDesign.design)
    }

    /// Create a label font with the configured family
    func labelFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if let fontName = labelFontName {
            let font = Font.custom(fontName, size: size).weight(weight)
            return useSmallCaps ? font.smallCaps() : font
        }
        let font = Font.system(size: size, weight: weight, design: fallbackDesign.design)
        return useSmallCaps ? font.smallCaps() : font
    }

    /// Create a number font with the configured family (always monospaced digits)
    func numberFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if let fontName = numberFontName {
            return .custom(fontName, size: size).weight(weight).monospacedDigit()
        }
        return .system(size: size, weight: weight, design: fallbackDesign.design).monospacedDigit()
    }
}

/// Special overlay effects
enum ThemeOverlayStyle: String, Codable {
    case none
    case scanline
    case stars
    case vignette
}

/// Theme color palette and styling - now with light/dark mode support
struct ThemeColors {
    // Background colors for dark/light modes
    let cardBackgroundDark: Color
    let cardBackgroundLight: Color
    let cardBorderDark: Color
    let cardBorderLight: Color
    let headerBackgroundDark: Color
    let headerBackgroundLight: Color

    // Text colors (base - used when dark/light variants not specified)
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color

    // Text color variants for light/dark modes (optional overrides)
    var primaryTextDark: Color?
    var primaryTextLight: Color?
    var secondaryTextDark: Color?
    var secondaryTextLight: Color?
    var tertiaryTextDark: Color?
    var tertiaryTextLight: Color?

    // Gauge colors (same for both modes - accent colors)
    let sessionGaugeColor: Color
    let sonnetGaugeColor: Color
    let totalGaugeHealthy: Color
    let totalGaugeWarning: Color
    let totalGaugeCritical: Color

    // Accent colors
    let accentPrimary: Color
    let accentSecondary: Color

    // Special effects
    let glowEnabled: Bool
    let glowIntensity: Double
    let useGradients: Bool

    // Border styling
    let borderWidth: CGFloat
    let cornerRadius: CGFloat

    // Gauge styling
    let gaugeLineWidth: CGFloat
    let gaugeSize: CGFloat

    // Background image support (for themed backgrounds)
    let backgroundImageDark: String?
    let backgroundImageLight: String?
    let backgroundOpacity: Double

    // Gauge theming (for themed icons inside gauges)
    let gaugeIcon: String?
    let gaugeIconColor: Color?
    let gaugeGlowRadius: CGFloat

    // Progress bar theming
    let progressBarGradient: Bool
    let progressBarStartColor: Color
    let progressBarEndColor: Color

    // Card theming
    let cardHasShadow: Bool
    let cardShadowColor: Color
    let cardShadowRadius: CGFloat
    let cardBorderStyle: BorderStyle
    let addAccountBorderStyle: BorderStyle

    // MARK: - Enhanced Theme Properties
    let fontDesign: ThemeFontDesign
    let fontConfig: ThemeFontConfig
    let overlayStyle: ThemeOverlayStyle

    // MARK: - Layout & Component Configuration
    let layout: ThemeLayout
    let components: GaugeComponentConfig

    // Fallback solid color for app background when no image is present
    // or to tint the image
    var appBackgroundDark: Color?
    var appBackgroundLight: Color?

    // Color accessors that take colorScheme as parameter
    func appBackground(for colorScheme: ColorScheme) -> Color {
        if let color = (colorScheme == .dark ? appBackgroundDark : appBackgroundLight) {
            return color
        }
        // Default fallback
        return colorScheme == .dark ? Color.black.opacity(0.8) : Color.white.opacity(0.8)
    }

    // Color accessors that take colorScheme as parameter
    func cardBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? cardBackgroundDark : cardBackgroundLight
    }

    func cardBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? cardBorderDark : cardBorderLight
    }

    func headerBackground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? headerBackgroundDark : headerBackgroundLight
    }

    /// Returns the background image name for the current color scheme
    func backgroundImage(for colorScheme: ColorScheme) -> String? {
        colorScheme == .dark ? backgroundImageDark : backgroundImageLight
    }

    /// Check if this theme has a background image
    var hasBackgroundImage: Bool {
        backgroundImageDark != nil || backgroundImageLight != nil
    }

    // Text color accessors that respect light/dark variants
    func primaryText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark, let darkColor = primaryTextDark {
            return darkColor
        } else if colorScheme == .light, let lightColor = primaryTextLight {
            return lightColor
        }
        return primaryText
    }

    func secondaryText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark, let darkColor = secondaryTextDark {
            return darkColor
        } else if colorScheme == .light, let lightColor = secondaryTextLight {
            return lightColor
        }
        return secondaryText
    }

    func tertiaryText(for colorScheme: ColorScheme) -> Color {
        if colorScheme == .dark, let darkColor = tertiaryTextDark {
            return darkColor
        } else if colorScheme == .light, let lightColor = tertiaryTextLight {
            return lightColor
        }
        return tertiaryText
    }
}

/// Theme manager providing colors and styling for the current theme
struct ThemeManager {
    // Use centralized keys from Constants (static for @AppStorage compatibility)
    static let themeKey = Constants.UserDefaultsKeys.selectedTheme
    static let colorSchemeModeKey = Constants.UserDefaultsKeys.colorSchemeMode

    /// Get the current theme from UserDefaults
    static var current: AppTheme {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: themeKey),
                let theme = AppTheme(rawValue: rawValue)
            {
                return theme
            }
            return .standard
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: themeKey)
        }
    }

    /// Get the current color scheme mode from UserDefaults
    static var currentColorSchemeMode: ColorSchemeMode {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: colorSchemeModeKey),
                let mode = ColorSchemeMode(rawValue: rawValue)
            {
                return mode
            }
            return .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: colorSchemeModeKey)
        }
    }

    /// Get colors for a specific theme
    static func colors(for theme: AppTheme) -> ThemeColors {
        switch theme {
        case .standard:
            return standardColors
        case .minimal:
            return minimalColors
        case .unified:
            return unifiedColors
        case .premium:
            return premiumColors
        case .nature:
            return natureColors
        case .vibrant:
            return vibrantColors
        case .ocean:
            return oceanColors
        case .sunset:
            return sunsetColors
        case .midnight:
            return midnightColors
        case .roseGold:
            return roseGoldColors
        case .terminal:
            return terminalColors
        }
    }

    /// Get colors for current theme
    static var currentColors: ThemeColors {
        colors(for: current)
    }

    // MARK: - Theme Definitions

    /// Standard/Default theme - Original app colors
    private static let standardColors = ThemeColors(
        cardBackgroundDark: Color(white: 0.20),
        cardBackgroundLight: Color(white: 0.98),
        cardBorderDark: Color(white: 0.30),
        cardBorderLight: Color(white: 0.88),
        headerBackgroundDark: Color(white: 0.15),
        headerBackgroundLight: Color(white: 0.95),
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(white: 0.5),
        sessionGaugeColor: .green,
        sonnetGaugeColor: .blue,
        totalGaugeHealthy: .green,
        totalGaugeWarning: .yellow,
        totalGaugeCritical: .red,
        accentPrimary: .blue,
        accentSecondary: .green,
        glowEnabled: false,
        glowIntensity: 0,
        useGradients: false,
        borderWidth: 1,
        cornerRadius: 12,
        gaugeLineWidth: 4,
        gaugeSize: 44,
        backgroundImageDark: nil,
        backgroundImageLight: nil,
        backgroundOpacity: 1.0,
        gaugeIcon: nil,
        gaugeIconColor: nil,
        gaugeGlowRadius: 0,
        progressBarGradient: false,
        progressBarStartColor: .green,
        progressBarEndColor: .green,
        cardHasShadow: false,
        cardShadowColor: .clear,
        cardShadowRadius: 0,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: .default,
        overlayStyle: .none,
        layout: .default,
        components: .default,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Minimal theme - Clean, simple design with more whitespace
    private static let minimalColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.18, green: 0.18, blue: 0.19),
        cardBackgroundLight: Color(red: 0.98, green: 0.98, blue: 0.99),
        cardBorderDark: Color(white: 0.28),
        cardBorderLight: Color(white: 0.88),
        headerBackgroundDark: Color(red: 0.14, green: 0.14, blue: 0.15),
        headerBackgroundLight: Color(red: 0.95, green: 0.95, blue: 0.96),
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(white: 0.4),
        sessionGaugeColor: Color(red: 0.29, green: 0.62, blue: 1.0),  // #4A9EFF
        sonnetGaugeColor: Color(red: 0.29, green: 0.62, blue: 1.0),  // #4A9EFF
        totalGaugeHealthy: Color(red: 0.29, green: 0.87, blue: 0.50),  // #4ADE80
        totalGaugeWarning: Color(red: 0.98, green: 0.80, blue: 0.08),  // #FACC15
        totalGaugeCritical: Color(red: 0.94, green: 0.27, blue: 0.27),  // #EF4444
        accentPrimary: Color(red: 0.29, green: 0.62, blue: 1.0),
        accentSecondary: Color(red: 0.29, green: 0.87, blue: 0.50),
        glowEnabled: false,
        glowIntensity: 0,
        useGradients: false,
        borderWidth: 1,
        cornerRadius: 10,
        gaugeLineWidth: 3,
        gaugeSize: 42,
        backgroundImageDark: nil,
        backgroundImageLight: nil,
        backgroundOpacity: 1.0,
        gaugeIcon: nil,
        gaugeIconColor: nil,
        gaugeGlowRadius: 0,
        progressBarGradient: false,
        progressBarStartColor: Color(red: 0.29, green: 0.62, blue: 1.0),
        progressBarEndColor: Color(red: 0.29, green: 0.62, blue: 1.0),
        cardHasShadow: false,
        cardShadowColor: .clear,
        cardShadowRadius: 0,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Helvetica Neue",
            bodyFontName: "Helvetica Neue",
            labelFontName: "Helvetica Neue",
            numberFontName: nil,
            fallbackDesign: .default,
            useSmallCaps: true,
            letterSpacing: 0.5
        ),
        overlayStyle: .none,
        layout: .minimalInline,
        components: .minimal,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Unified theme - All circular gauges with metallic accents
    private static let unifiedColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.17, green: 0.17, blue: 0.18),
        cardBackgroundLight: Color(red: 0.96, green: 0.96, blue: 0.97),
        cardBorderDark: Color(white: 0.28),
        cardBorderLight: Color(white: 0.82),
        headerBackgroundDark: Color(red: 0.12, green: 0.12, blue: 0.13),
        headerBackgroundLight: Color(red: 0.93, green: 0.93, blue: 0.94),
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(white: 0.45),
        sessionGaugeColor: Color(red: 0.95, green: 0.75, blue: 0.15),  // Gold/Yellow
        sonnetGaugeColor: Color(red: 0.40, green: 0.70, blue: 1.0),  // Light blue
        totalGaugeHealthy: Color(red: 0.30, green: 0.85, blue: 0.55),  // Green
        totalGaugeWarning: Color(red: 0.95, green: 0.75, blue: 0.15),  // Gold
        totalGaugeCritical: Color(red: 0.95, green: 0.35, blue: 0.35),  // Red
        accentPrimary: Color(red: 0.40, green: 0.70, blue: 1.0),
        accentSecondary: Color(red: 0.95, green: 0.75, blue: 0.15),
        glowEnabled: false,
        glowIntensity: 0,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 14,
        gaugeLineWidth: 5,
        gaugeSize: 46,
        backgroundImageDark: nil,
        backgroundImageLight: nil,
        backgroundOpacity: 1.0,
        gaugeIcon: nil,
        gaugeIconColor: nil,
        gaugeGlowRadius: 0,
        progressBarGradient: false,
        progressBarStartColor: Color(red: 0.40, green: 0.70, blue: 1.0),
        progressBarEndColor: Color(red: 0.40, green: 0.70, blue: 1.0),
        cardHasShadow: false,
        cardShadowColor: .clear,
        cardShadowRadius: 0,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: .default,  // Uses system rounded
        overlayStyle: .none,
        layout: .default,
        components: .default,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Premium theme - Glow effects and gradients
    private static let premiumColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.14, green: 0.14, blue: 0.16),
        cardBackgroundLight: Color(red: 0.97, green: 0.97, blue: 0.99),
        cardBorderDark: Color(red: 0.22, green: 0.27, blue: 0.32),
        cardBorderLight: Color(red: 0.85, green: 0.88, blue: 0.92),
        headerBackgroundDark: Color(red: 0.10, green: 0.10, blue: 0.12),
        headerBackgroundLight: Color(red: 0.94, green: 0.94, blue: 0.96),
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(red: 0.45, green: 0.50, blue: 0.55),
        sessionGaugeColor: Color(red: 0.0, green: 0.85, blue: 0.65),  // Cyan-green
        sonnetGaugeColor: Color(red: 0.0, green: 0.66, blue: 1.0),  // Electric blue #00A8FF
        totalGaugeHealthy: Color(red: 0.0, green: 1.0, blue: 0.53),  // Neon green #00FF88
        totalGaugeWarning: Color(red: 1.0, green: 0.84, blue: 0.0),  // Glowing yellow #FFD700
        totalGaugeCritical: Color(red: 1.0, green: 0.42, blue: 0.42),  // Glowing red #FF6B6B
        accentPrimary: Color(red: 0.0, green: 0.66, blue: 1.0),
        accentSecondary: Color(red: 0.0, green: 1.0, blue: 0.53),
        glowEnabled: true,
        glowIntensity: 0.6,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 16,
        gaugeLineWidth: 5,
        gaugeSize: 48,
        backgroundImageDark: nil,
        backgroundImageLight: nil,
        backgroundOpacity: 1.0,
        gaugeIcon: nil,
        gaugeIconColor: nil,
        gaugeGlowRadius: 8,
        progressBarGradient: false,
        progressBarStartColor: Color(red: 0.0, green: 0.66, blue: 1.0),
        progressBarEndColor: Color(red: 0.0, green: 0.66, blue: 1.0),
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.0, green: 0.66, blue: 1.0).opacity(0.2),
        cardShadowRadius: 8,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Avenir Next",
            bodyFontName: "Avenir Next",
            labelFontName: "Avenir Next",
            numberFontName: nil,
            fallbackDesign: .rounded,
            useSmallCaps: false,
            letterSpacing: 0.3
        ),
        overlayStyle: .none,
        layout: .default,
        components: .premium,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Nature theme - Organic wood grain & forest textures
    private static let natureColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.24, green: 0.20, blue: 0.15).opacity(0.85),  // Warm brown tint
        cardBackgroundLight: Color(red: 1.0, green: 0.98, blue: 0.94).opacity(0.90),  // Floral white
        cardBorderDark: Color(red: 0.55, green: 0.41, blue: 0.08).opacity(0.4),  // Goldenrod hint
        cardBorderLight: Color(red: 0.42, green: 0.56, blue: 0.14).opacity(0.3),  // Olive drab hint
        headerBackgroundDark: Color(red: 0.18, green: 0.15, blue: 0.10).opacity(0.9),  // Dark wood
        headerBackgroundLight: Color(red: 0.96, green: 0.94, blue: 0.90).opacity(0.9),  // Warm cream
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(red: 0.45, green: 0.40, blue: 0.35),
        sessionGaugeColor: Color(red: 0.42, green: 0.56, blue: 0.14),  // Olive drab #6B8E23
        sonnetGaugeColor: Color(red: 0.55, green: 0.27, blue: 0.07),  // Saddle brown #8B4513
        totalGaugeHealthy: Color(red: 0.13, green: 0.55, blue: 0.13),  // Forest green #228B22
        totalGaugeWarning: Color(red: 0.85, green: 0.65, blue: 0.13),  // Goldenrod #DAA520
        totalGaugeCritical: Color(red: 0.80, green: 0.36, blue: 0.36),  // Indian red #CD5C5C
        accentPrimary: Color(red: 0.29, green: 0.49, blue: 0.35),  // Fern green #4A7C59
        accentSecondary: Color(red: 0.55, green: 0.41, blue: 0.08),  // Dark goldenrod #8B6914
        glowEnabled: false,
        glowIntensity: 0,
        useGradients: false,
        borderWidth: 1,
        cornerRadius: 14,
        gaugeLineWidth: 5,
        gaugeSize: 46,
        backgroundImageDark: "nature_bg_dark",
        backgroundImageLight: "nature_bg_light",
        backgroundOpacity: 1.0,
        gaugeIcon: "leaf.fill",
        gaugeIconColor: Color(red: 0.42, green: 0.56, blue: 0.14),  // Olive green
        gaugeGlowRadius: 0,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 1.0, green: 0.85, blue: 0.4),  // Warm yellow (sunrise)
        progressBarEndColor: Color(red: 0.42, green: 0.56, blue: 0.14),  // Forest green
        cardHasShadow: true,
        cardShadowColor: Color.black.opacity(0.15),
        cardShadowRadius: 8,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Gill Sans",
            bodyFontName: "Gill Sans",
            labelFontName: "Gill Sans",
            numberFontName: nil,
            fallbackDesign: .rounded,
            useSmallCaps: false,
            letterSpacing: 0
        ),
        overlayStyle: .none,
        layout: .default,
        components: .default,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Vibrant theme - Neon gradients with glow effects
    private static let vibrantColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.29, green: 0.0, blue: 0.51).opacity(0.35),  // Indigo tint
        cardBackgroundLight: Color(red: 0.93, green: 0.51, blue: 0.93).opacity(0.25),  // Violet tint
        cardBorderDark: Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.5),  // Cyan glow
        cardBorderLight: Color(red: 1.0, green: 0.0, blue: 1.0).opacity(0.3),  // Magenta hint
        headerBackgroundDark: Color(red: 0.20, green: 0.0, blue: 0.35).opacity(0.9),  // Deep purple
        headerBackgroundLight: Color(red: 0.96, green: 0.90, blue: 0.98).opacity(0.9),  // Light lavender
        primaryText: .primary,
        secondaryText: .secondary,
        tertiaryText: Color(red: 0.60, green: 0.50, blue: 0.70),
        sessionGaugeColor: Color(red: 0.0, green: 0.83, blue: 1.0),  // Vivid cyan #00D4FF
        sonnetGaugeColor: Color(red: 1.0, green: 0.08, blue: 0.58),  // Deep pink #FF1493
        totalGaugeHealthy: Color(red: 0.0, green: 1.0, blue: 1.0),  // Cyan #00FFFF
        totalGaugeWarning: Color(red: 1.0, green: 0.84, blue: 0.0),  // Gold #FFD700
        totalGaugeCritical: Color(red: 1.0, green: 0.08, blue: 0.58),  // Deep pink #FF1493
        accentPrimary: Color(red: 0.0, green: 1.0, blue: 1.0),  // Cyan #00FFFF
        accentSecondary: Color(red: 1.0, green: 0.0, blue: 1.0),  // Magenta #FF00FF
        glowEnabled: true,
        glowIntensity: 0.7,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 16,
        gaugeLineWidth: 5,
        gaugeSize: 48,
        backgroundImageDark: "vibrant_bg_dark",
        backgroundImageLight: "vibrant_bg_light",
        backgroundOpacity: 1.0,
        gaugeIcon: nil,
        gaugeIconColor: nil,
        gaugeGlowRadius: 12,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 0.0, green: 0.83, blue: 1.0),  // Cyan
        progressBarEndColor: Color(red: 1.0, green: 0.08, blue: 0.58),  // Pink
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.0, green: 1.0, blue: 1.0).opacity(0.3),  // Cyan glow
        cardShadowRadius: 12,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .dashed,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Futura",
            bodyFontName: nil,
            labelFontName: "Futura",
            numberFontName: nil,
            fallbackDesign: .rounded,
            useSmallCaps: true,
            letterSpacing: 1.0
        ),
        overlayStyle: .none,
        layout: .topGauges,
        components: .vibrant,
        appBackgroundDark: nil,
        appBackgroundLight: nil
    )

    /// Ocean theme - Deep blue & aquamarine
    private static let oceanColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.04, green: 0.10, blue: 0.18).opacity(0.9),  // Deep blue #0a192f
        cardBackgroundLight: Color(red: 0.90, green: 0.95, blue: 1.0).opacity(0.9),  // Very light blue
        cardBorderDark: Color(red: 0.39, green: 1.0, blue: 0.85).opacity(0.3),  // Aquamarine hint
        cardBorderLight: Color(red: 0.04, green: 0.10, blue: 0.18).opacity(0.1),
        headerBackgroundDark: Color(red: 0.02, green: 0.05, blue: 0.10).opacity(0.95),
        headerBackgroundLight: Color(red: 0.85, green: 0.92, blue: 0.98),
        primaryText: .primary,
        secondaryText: Color(red: 0.53, green: 0.83, blue: 0.60),  // Sea foam #88d498
        tertiaryText: Color(white: 0.5),
        sessionGaugeColor: Color(red: 0.39, green: 1.0, blue: 0.85),  // Aquamarine #64ffda
        sonnetGaugeColor: Color(red: 0.0, green: 0.75, blue: 1.0),  // Blue
        totalGaugeHealthy: Color(red: 0.39, green: 1.0, blue: 0.85),  // Aquamarine
        totalGaugeWarning: Color(red: 1.0, green: 0.42, blue: 0.42),  // Coral #ff6b6b
        totalGaugeCritical: Color(red: 1.0, green: 0.25, blue: 0.25),
        accentPrimary: Color(red: 0.39, green: 1.0, blue: 0.85),  // Aquamarine
        accentSecondary: Color(red: 0.53, green: 0.83, blue: 0.60),  // Sea foam
        glowEnabled: true,
        glowIntensity: 0.3,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 12,
        gaugeLineWidth: 4,
        gaugeSize: 44,
        backgroundImageDark: "ocean_bg_dark",
        backgroundImageLight: "ocean_bg_light",
        backgroundOpacity: 0.8,
        gaugeIcon: "water.waves",
        gaugeIconColor: Color(red: 0.39, green: 1.0, blue: 0.85),
        gaugeGlowRadius: 4,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 0.39, green: 1.0, blue: 0.85),
        progressBarEndColor: Color(red: 0.0, green: 0.5, blue: 1.0),
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.0, green: 0.0, blue: 0.2).opacity(0.4),
        cardShadowRadius: 10,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Avenir",
            bodyFontName: "Avenir",
            labelFontName: "Avenir",
            numberFontName: nil,
            fallbackDesign: .rounded,
            useSmallCaps: false,
            letterSpacing: 0.2
        ),
        overlayStyle: .none,
        layout: .default,
        components: .ocean,
        appBackgroundDark: Color(red: 0.04, green: 0.10, blue: 0.18),
        appBackgroundLight: Color(red: 0.90, green: 0.95, blue: 1.0)
    )

    /// Sunset theme - Warm purple to orange gradients
    private static let sunsetColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.18, green: 0.11, blue: 0.41).opacity(0.8),  // Deep purple #2d1b69
        cardBackgroundLight: Color(red: 1.0, green: 0.95, blue: 0.90),
        cardBorderDark: Color(red: 1.0, green: 0.42, blue: 0.21).opacity(0.4),  // Orange hint
        cardBorderLight: Color(red: 0.5, green: 0.2, blue: 0.1).opacity(0.2),
        headerBackgroundDark: Color(red: 0.10, green: 0.05, blue: 0.25).opacity(0.9),
        headerBackgroundLight: Color(red: 1.0, green: 0.90, blue: 0.85),
        primaryText: .white,
        secondaryText: Color(red: 1.0, green: 0.8, blue: 0.6),
        tertiaryText: Color(red: 0.8, green: 0.6, blue: 0.8),
        // Light mode needs dark text on peachy background (dark variants use base)
        primaryTextDark: nil,
        primaryTextLight: Color(red: 0.3, green: 0.15, blue: 0.2),  // Dark purple-brown
        secondaryTextDark: nil,
        secondaryTextLight: Color(red: 0.6, green: 0.3, blue: 0.2),  // Warm brown
        tertiaryTextDark: nil,
        tertiaryTextLight: Color(red: 0.5, green: 0.35, blue: 0.4),  // Muted mauve
        sessionGaugeColor: Color(red: 1.0, green: 0.42, blue: 0.21),  // Orange #ff6b35
        sonnetGaugeColor: Color(red: 1.0, green: 0.2, blue: 0.4),  // Pinkish red
        totalGaugeHealthy: Color(red: 1.0, green: 0.42, blue: 0.21),
        totalGaugeWarning: Color(red: 1.0, green: 0.84, blue: 0.0),  // Gold
        totalGaugeCritical: Color(red: 0.8, green: 0.1, blue: 0.1),
        accentPrimary: Color(red: 1.0, green: 0.42, blue: 0.21),
        accentSecondary: Color(red: 0.6, green: 0.2, blue: 0.8),  // Purple
        glowEnabled: true,
        glowIntensity: 0.4,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 15,
        gaugeLineWidth: 5,
        gaugeSize: 46,
        backgroundImageDark: "sunset_bg_dark",
        backgroundImageLight: "sunset_bg_light",
        backgroundOpacity: 0.7,
        gaugeIcon: "sun.max.fill",
        gaugeIconColor: .orange,
        gaugeGlowRadius: 6,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 1.0, green: 0.2, blue: 0.4),
        progressBarEndColor: Color(red: 1.0, green: 0.7, blue: 0.0),
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.2, green: 0.0, blue: 0.4).opacity(0.5),
        cardShadowRadius: 10,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .rounded,
        fontConfig: ThemeFontConfig(
            titleFontName: "Optima",
            bodyFontName: "Optima",
            labelFontName: "Optima",
            numberFontName: nil,
            fallbackDesign: .rounded,
            useSmallCaps: false,
            letterSpacing: 0
        ),
        overlayStyle: .vignette,
        layout: .default,
        components: .default,
        appBackgroundDark: Color(red: 0.18, green: 0.11, blue: 0.41),
        appBackgroundLight: Color(red: 1.0, green: 0.95, blue: 0.90)
    )

    /// Midnight theme - Dark cosmic with neon accents
    private static let midnightColors = ThemeColors(
        cardBackgroundDark: Color(white: 0.05).opacity(0.95),  // Deep black #0d0d0d
        cardBackgroundLight: Color(red: 0.95, green: 0.93, blue: 1.0).opacity(0.9),  // Light lavender
        cardBorderDark: Color(red: 0.61, green: 0.36, blue: 0.90).opacity(0.5),  // Neon purple #9b5de5
        cardBorderLight: Color(red: 0.5, green: 0.3, blue: 0.7).opacity(0.4),  // Softer purple
        headerBackgroundDark: Color.black,
        headerBackgroundLight: Color(red: 0.9, green: 0.88, blue: 0.98),  // Light purple header
        primaryText: .white,
        secondaryText: Color(red: 0.00, green: 0.96, blue: 0.83),  // Electric blue #00f5d4
        tertiaryText: Color(white: 0.4),
        // Light mode needs dark text on light cosmic background
        primaryTextDark: nil,
        primaryTextLight: Color(red: 0.2, green: 0.15, blue: 0.35),  // Dark purple
        secondaryTextDark: nil,
        secondaryTextLight: Color(red: 0.4, green: 0.25, blue: 0.6),  // Medium purple
        tertiaryTextDark: nil,
        tertiaryTextLight: Color(red: 0.5, green: 0.45, blue: 0.6),  // Muted purple
        sessionGaugeColor: Color(red: 0.61, green: 0.36, blue: 0.90),  // Neon purple
        sonnetGaugeColor: Color(red: 0.00, green: 0.96, blue: 0.83),  // Electric blue
        totalGaugeHealthy: Color(red: 0.00, green: 0.96, blue: 0.83),
        totalGaugeWarning: Color(red: 1.0, green: 0.0, blue: 0.5),  // Magenta
        totalGaugeCritical: Color(red: 1.0, green: 0.0, blue: 0.0),
        accentPrimary: Color(red: 0.00, green: 0.96, blue: 0.83),
        accentSecondary: Color(red: 0.61, green: 0.36, blue: 0.90),
        glowEnabled: true,
        glowIntensity: 0.8,
        useGradients: true,
        borderWidth: 1.5,
        cornerRadius: 8,
        gaugeLineWidth: 3,
        gaugeSize: 42,
        backgroundImageDark: "midnight_bg",
        backgroundImageLight: "midnight_bg_light",
        backgroundOpacity: 0.9,
        gaugeIcon: "sparkles",
        gaugeIconColor: Color(red: 0.00, green: 0.96, blue: 0.83),
        gaugeGlowRadius: 10,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 0.61, green: 0.36, blue: 0.90),
        progressBarEndColor: Color(red: 0.00, green: 0.96, blue: 0.83),
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.61, green: 0.36, blue: 0.90).opacity(0.3),
        cardShadowRadius: 15,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .dashed,
        fontDesign: .default,
        fontConfig: ThemeFontConfig(
            titleFontName: nil,
            bodyFontName: nil,
            labelFontName: nil,
            numberFontName: "SF Mono",
            fallbackDesign: .default,
            useSmallCaps: true,
            letterSpacing: 1.5
        ),
        overlayStyle: .stars,
        layout: .default,
        components: .midnight,
        appBackgroundDark: Color(white: 0.05),
        appBackgroundLight: Color(red: 0.92, green: 0.90, blue: 0.98)  // Light lavender background
    )

    /// Rose Gold theme - Elegant pink & gold luxury
    private static let roseGoldColors = ThemeColors(
        cardBackgroundDark: Color(red: 0.3, green: 0.2, blue: 0.25).opacity(0.9),
        cardBackgroundLight: Color(red: 1.0, green: 0.96, blue: 0.96).opacity(0.95),  // Cream/Blush #fff5f5
        cardBorderDark: Color(red: 0.72, green: 0.43, blue: 0.47).opacity(0.6),  // Rose gold #b76e79
        cardBorderLight: Color(red: 0.72, green: 0.43, blue: 0.47).opacity(0.4),
        headerBackgroundDark: Color(red: 0.25, green: 0.15, blue: 0.2),
        headerBackgroundLight: Color(red: 1.0, green: 0.84, blue: 0.88),  // Blush #ffd6e0
        primaryText: Color(red: 0.3, green: 0.1, blue: 0.15),
        secondaryText: Color(red: 0.72, green: 0.43, blue: 0.47),
        tertiaryText: Color(red: 0.6, green: 0.5, blue: 0.5),
        // Dark mode needs light text on dark rose background (light variants use base)
        primaryTextDark: Color(red: 1.0, green: 0.95, blue: 0.95),  // Soft white/cream
        primaryTextLight: nil,
        secondaryTextDark: Color(red: 0.9, green: 0.7, blue: 0.75),  // Light rose
        secondaryTextLight: nil,
        tertiaryTextDark: Color(red: 0.7, green: 0.55, blue: 0.6),  // Muted rose
        tertiaryTextLight: nil,
        sessionGaugeColor: Color(red: 0.72, green: 0.43, blue: 0.47),  // Rose gold
        sonnetGaugeColor: Color(red: 0.9, green: 0.6, blue: 0.6),
        totalGaugeHealthy: Color(red: 0.72, green: 0.43, blue: 0.47),
        totalGaugeWarning: Color(red: 0.8, green: 0.5, blue: 0.2),  // Goldish
        totalGaugeCritical: Color(red: 0.8, green: 0.2, blue: 0.2),
        accentPrimary: Color(red: 0.72, green: 0.43, blue: 0.47),
        accentSecondary: Color(red: 0.98, green: 0.90, blue: 0.80),  // Champagne
        glowEnabled: true,
        glowIntensity: 0.2,
        useGradients: true,
        borderWidth: 1,
        cornerRadius: 18,
        gaugeLineWidth: 2,
        gaugeSize: 45,
        backgroundImageDark: "rosegold_bg_dark",
        backgroundImageLight: "rosegold_bg_light",
        backgroundOpacity: 0.8,
        gaugeIcon: "crown.fill",
        gaugeIconColor: Color(red: 0.72, green: 0.43, blue: 0.47),
        gaugeGlowRadius: 4,
        progressBarGradient: true,
        progressBarStartColor: Color(red: 0.72, green: 0.43, blue: 0.47),
        progressBarEndColor: Color(red: 0.98, green: 0.80, blue: 0.70),
        cardHasShadow: true,
        cardShadowColor: Color(red: 0.72, green: 0.43, blue: 0.47).opacity(0.2),
        cardShadowRadius: 10,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .solid,
        fontDesign: .serif,
        fontConfig: ThemeFontConfig(
            titleFontName: "Baskerville",
            bodyFontName: "Baskerville",
            labelFontName: "Baskerville",
            numberFontName: "Didot",
            fallbackDesign: .serif,
            useSmallCaps: true,
            letterSpacing: 0.5
        ),
        overlayStyle: .none,
        layout: .elegantRight,
        components: .elegant,
        appBackgroundDark: Color(red: 0.25, green: 0.15, blue: 0.2),
        appBackgroundLight: Color(red: 1.0, green: 0.96, blue: 0.96)
    )

    /// Terminal theme - Retro hacker CRT style
    private static let terminalColors = ThemeColors(
        cardBackgroundDark: Color.black,  // Pure black #000000
        cardBackgroundLight: Color(red: 0.98, green: 0.97, blue: 0.94).opacity(0.95),  // Vintage paper
        cardBorderDark: Color(red: 0.0, green: 1.0, blue: 0.0),  // Green #00ff00
        cardBorderLight: Color(red: 0.0, green: 0.5, blue: 0.0).opacity(0.5),  // Darker green
        headerBackgroundDark: Color(white: 0.05),
        headerBackgroundLight: Color(red: 0.95, green: 0.94, blue: 0.90),  // Light paper header
        primaryText: Color(red: 0.0, green: 1.0, blue: 0.0),  // Green text
        secondaryText: Color(red: 0.0, green: 0.8, blue: 0.0),
        tertiaryText: Color(red: 0.0, green: 0.6, blue: 0.0),
        // Light mode uses darker green on light paper
        primaryTextDark: nil,
        primaryTextLight: Color(red: 0.0, green: 0.4, blue: 0.0),  // Dark green
        secondaryTextDark: nil,
        secondaryTextLight: Color(red: 0.0, green: 0.35, blue: 0.0),  // Medium dark green
        tertiaryTextDark: nil,
        tertiaryTextLight: Color(red: 0.2, green: 0.4, blue: 0.2),  // Muted green
        sessionGaugeColor: Color(red: 0.0, green: 1.0, blue: 0.0),
        sonnetGaugeColor: Color(red: 0.0, green: 1.0, blue: 0.0),
        totalGaugeHealthy: Color(red: 0.0, green: 1.0, blue: 0.0),
        totalGaugeWarning: Color(red: 1.0, green: 0.8, blue: 0.0),
        totalGaugeCritical: Color(red: 1.0, green: 0.0, blue: 0.0),
        accentPrimary: Color(red: 0.0, green: 1.0, blue: 0.0),
        accentSecondary: Color(red: 0.0, green: 1.0, blue: 0.0),
        glowEnabled: true,
        glowIntensity: 0.5,
        useGradients: false,
        borderWidth: 2,
        cornerRadius: 0,  // Square corners for terminal
        gaugeLineWidth: 4,
        gaugeSize: 44,
        backgroundImageDark: "terminal_bg",
        backgroundImageLight: "terminal_bg_light",
        backgroundOpacity: 0.6,
        gaugeIcon: "chevron.right.square.fill",
        gaugeIconColor: Color(red: 0.0, green: 1.0, blue: 0.0),
        gaugeGlowRadius: 4,
        progressBarGradient: false,
        progressBarStartColor: Color(red: 0.0, green: 1.0, blue: 0.0),
        progressBarEndColor: Color(red: 0.0, green: 1.0, blue: 0.0),
        cardHasShadow: false,
        cardShadowColor: .green,
        cardShadowRadius: 0,
        cardBorderStyle: .solid,
        addAccountBorderStyle: .dashed,
        fontDesign: .monospaced,
        fontConfig: ThemeFontConfig(
            titleFontName: "Menlo",
            bodyFontName: "Menlo",
            labelFontName: "Menlo",
            numberFontName: "Menlo",
            fallbackDesign: .monospaced,
            useSmallCaps: false,
            letterSpacing: 0
        ),
        overlayStyle: .scanline,
        layout: .verticalStack,
        components: .terminal,
        appBackgroundDark: Color.black,
        appBackgroundLight: Color(red: 0.96, green: 0.95, blue: 0.92)  // Light vintage paper
    )
}

// MARK: - View Modifiers for Theme

extension View {
    /// Apply glow effect if enabled in current theme
    @ViewBuilder
    func themeGlow(color: Color, theme: ThemeColors) -> some View {
        if theme.glowEnabled {
            self.shadow(color: color.opacity(theme.glowIntensity), radius: 8)
                .shadow(color: color.opacity(theme.glowIntensity * 0.5), radius: 4)
        } else {
            self
        }
    }

    /// Apply themed gauge glow effect with theme-specific radius
    @ViewBuilder
    func themeGaugeGlow(color: Color, theme: ThemeColors) -> some View {
        if theme.gaugeGlowRadius > 0 {
            self.shadow(color: color.opacity(0.6), radius: theme.gaugeGlowRadius)
                .shadow(color: color.opacity(0.3), radius: theme.gaugeGlowRadius / 2)
        } else {
            self
        }
    }

    /// Apply card styling based on theme and color scheme
    func themeCard(_ theme: ThemeColors, colorScheme: ColorScheme) -> some View {
        self
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        theme.cardBorder(for: colorScheme),
                        style: StrokeStyle(
                            lineWidth: theme.borderWidth,
                            dash: theme.cardBorderStyle == .dashed ? [8, 4] : []
                        )
                    )
            )
            .shadow(
                color: theme.cardHasShadow ? theme.cardShadowColor : .clear,
                radius: theme.cardShadowRadius
            )
            .themeOverlay(theme)
    }

    /// Apply Add Account card styling with special border
    func themeAddAccountCard(_ theme: ThemeColors, colorScheme: ColorScheme) -> some View {
        self
            .background(theme.cardBackground(for: colorScheme))
            .cornerRadius(theme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .stroke(
                        theme.accentPrimary,
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: theme.addAccountBorderStyle == .dashed ? [8, 4] : []
                        )
                    )
            )
            .shadow(
                color: theme.cardHasShadow ? theme.cardShadowColor : .clear,
                radius: theme.cardShadowRadius
            )
            .themeOverlay(theme)
    }

    /// Apply theme-specific overlay (scanlines, stars, etc)
    @ViewBuilder
    func themeOverlay(_ theme: ThemeColors) -> some View {
        switch theme.overlayStyle {
        case .none:
            self
        case .scanline:
            self.overlay(
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.1))
                            .frame(maxWidth: .infinity, maxHeight: 2)
                        Spacer()
                    }
                }
                .allowsHitTesting(false)
                .mask(RoundedRectangle(cornerRadius: theme.cornerRadius))
            )
        case .stars:
            // Deterministic star positions using seeded RNG to prevent flickering
            self.overlay(
                GeometryReader { _ in
                    Canvas { context, size in
                        // Use a seeded random generator for deterministic positions
                        var rng = SeededRandomNumberGenerator(seed: 42)
                        for _ in 0..<30 {
                            let x = Double.random(in: 0...size.width, using: &rng)
                            let y = Double.random(in: 0...size.height, using: &rng)
                            context.fill(
                                Path(ellipseIn: CGRect(x: x, y: y, width: 2, height: 2)),
                                with: .color(.white.opacity(0.4)))
                        }
                    }
                }
                .allowsHitTesting(false)
                .mask(RoundedRectangle(cornerRadius: theme.cornerRadius))
            )
        case .vignette:
            self.overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.2)]),
                            center: .center,
                            startRadius: 0,
                            endRadius: 200
                        )
                    )
                    .allowsHitTesting(false)
            )
        }
    }
}

// MARK: - Seeded Random Number Generator

/// A deterministic random number generator using a linear congruential generator algorithm.
/// Used to generate consistent pseudo-random positions for star overlays.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        // Linear congruential generator parameters (same as glibc)
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
