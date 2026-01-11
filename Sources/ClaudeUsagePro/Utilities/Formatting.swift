import Foundation

// MARK: - Double Formatting Extensions

extension Double {
    /// Formats the value as a percentage string (e.g., 0.75 → "75%").
    /// Value is expected to be in 0.0-1.0 range but is not clamped.
    var formattedPercentage: String {
        "\(Int((self * 100).rounded()))%"
    }
}
