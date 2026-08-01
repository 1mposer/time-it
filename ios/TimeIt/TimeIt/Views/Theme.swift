import SwiftUI

extension Color {
    /// e.g. Color(hex: 0x1253a4)
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: opacity)
    }
}

/// Colour tokens from ios/guidelines/Guidelines.md — the visual source of truth.
enum Theme {
    static let appBackground = Color(hex: 0xf2f2f7)
    static let cardBackground = Color.white
    static let primaryText = Color(hex: 0x1c1c1e)
    static let secondaryText = Color(hex: 0x8e8e93)
    static let accentOrange = Color(hex: 0xff9500)   // Good window highlight
    static let perfectGreen = Color(hex: 0x34c759)   // Perfect window highlight
    static let timelineTrack = Color(hex: 0xf2f2f7)
    static let accentInteractive = Color(hex: 0x007aff) // Semantic accent/interactive
    static let divider = Color(hex: 0x3c3c43, opacity: 0.18)

    /// Ocean blue header gradient, #1253a4 → #3ec6e8 at ~160°.
    static let headerGradient = LinearGradient(
        colors: [
            Color(hex: 0x1253a4),
            Color(hex: 0x1a78c2),
            Color(hex: 0x29a8e0),
            Color(hex: 0x3ec6e8),
        ],
        startPoint: UnitPoint(x: 0.33, y: 0),
        endPoint: UnitPoint(x: 0.67, y: 1)
    )
}
