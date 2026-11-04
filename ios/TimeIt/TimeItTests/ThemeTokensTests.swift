import SwiftUI
import UIKit
import XCTest
@testable import TimeIt

/// Every colour token resolves to the Figma Semantic value in BOTH modes
/// (Light → Dark, read live 2026-11-04). Resolved against a real trait
/// collection, then compared as 8-bit sRGB + alpha.
final class ThemeTokensTests: XCTestCase {

    private struct RGBA: Equatable, CustomStringConvertible {
        let hex: UInt32
        let alpha: Int  // percent
        var description: String { String(format: "#%06X @%d%%", hex, alpha) }
    }

    private func resolve(_ color: UIColor, _ style: UIUserInterfaceStyle) -> RGBA {
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(resolved.getRed(&r, green: &g, blue: &b, alpha: &a))
        func byte(_ v: CGFloat) -> UInt32 { UInt32((v * 255).rounded()) }
        return RGBA(hex: byte(r) << 16 | byte(g) << 8 | byte(b), alpha: Int((a * 100).rounded()))
    }

    private func assertToken(_ color: UIColor, light: UInt32, dark: UInt32,
                             lightAlpha: Int = 100, darkAlpha: Int = 100,
                             _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(resolve(color, .light), RGBA(hex: light, alpha: lightAlpha), "\(name) light", file: file, line: line)
        XCTAssertEqual(resolve(color, .dark), RGBA(hex: dark, alpha: darkAlpha), "\(name) dark", file: file, line: line)
    }

    func testSurfaceAndTextTokens() {
        typealias T = Theme.UIColors
        assertToken(T.appBackground, light: 0xf2f2f7, dark: 0x000000, "surface/background")
        assertToken(T.cardBackground, light: 0xffffff, dark: 0x2c2c2e, "surface/card → card-elevated in dark")
        assertToken(T.primaryText, light: 0x1c1c1e, dark: 0xf2f2f7, "text/primary")
        assertToken(T.secondaryText, light: 0x8e8e93, dark: 0x98989f, "text/secondary")
        assertToken(T.onGradient, light: 0xffffff, dark: 0xffffff, "text/on-gradient")
        assertToken(T.divider, light: 0x3c3c43, dark: 0x545458, lightAlpha: 18, darkAlpha: 60, "separator")
        assertToken(T.timelineTrack, light: 0xf2f2f7, dark: 0x3a3a3c, "timeline/track")
    }

    func testRatingAndAccentTokens() {
        typealias T = Theme.UIColors
        assertToken(T.perfectGreen, light: 0x34c759, dark: 0x30d158, "rating/perfect")
        assertToken(T.accentOrange, light: 0xff9500, dark: 0xff9f0a, "rating/good")
        assertToken(T.badRed, light: 0xff3b30, dark: 0xff453a, "rating/bad")
        assertToken(T.blendYellow, light: 0xffbe0a, dark: 0xffbe0a, "rating/blend (same in both, intended)")
        assertToken(T.accentInteractive, light: 0x007aff, dark: 0x0a84ff, "accent/interactive")
        assertToken(T.accentDestructive, light: 0xff3b30, dark: 0xff453a, "accent/destructive")
    }

    func testChipTokens() {
        typealias T = Theme.UIColors
        assertToken(T.chipText(.green), light: 0x1a7a35, dark: 0x30d158, "chip/green/text")
        assertToken(T.chipText(.orange), light: 0xb85c00, dark: 0xff9f0a, "chip/orange/text")
        assertToken(T.chipText(.red), light: 0xc0392b, dark: 0xff453a, "chip/red/text")
        assertToken(T.chipText(.neutral), light: 0x636366, dark: 0x98989f, "chip/neutral/text")
        assertToken(T.chipBackground(.green), light: 0x34c759, dark: 0x30d158, lightAlpha: 12, darkAlpha: 20, "chip/green/bg")
        assertToken(T.chipBackground(.orange), light: 0xff9500, dark: 0xff9f0a, lightAlpha: 12, darkAlpha: 20, "chip/orange/bg")
        assertToken(T.chipBackground(.red), light: 0xff3b30, dark: 0xff453a, lightAlpha: 12, darkAlpha: 20, "chip/red/bg")
        assertToken(T.chipBackground(.neutral), light: 0x8e8e93, dark: 0x98989f, lightAlpha: 12, darkAlpha: 20, "chip/neutral/bg")
    }

    /// The light hairline is drawn only in light; dark's Card Lift highlight
    /// replaces it, so the token is fully clear in dark.
    func testCardHairlineIsLightOnly() {
        assertToken(Theme.UIColors.cardHairline, light: 0x000000, dark: 0x000000,
                    lightAlpha: 6, darkAlpha: 0, "card hairline")
    }

    /// No Figma token: the hero add-card's pressed blue keeps #66B2FF in
    /// light and reads as the dark accent at 60% in dark.
    func testPressedAccentHasADarkValue() {
        assertToken(Theme.UIColors.accentInteractivePressed, light: 0x66b2ff, dark: 0x0a84ff,
                    lightAlpha: 100, darkAlpha: 60, "accent pressed")
    }

    /// The SwiftUI tokens are the UIColor tokens — resolving the `Color`
    /// through an environment gives the same per-mode value.
    func testSwiftUIColorsFollowTheScheme() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        assertSame(Theme.cardBackground.resolve(in: dark), Color(hex: 0x2c2c2e).resolve(in: dark), "card dark")
        assertSame(Theme.cardBackground.resolve(in: light), Color(hex: 0xffffff).resolve(in: light), "card light")
        assertSame(Theme.primaryText.resolve(in: dark), Color(hex: 0xf2f2f7).resolve(in: dark), "text dark")
        assertSame(Theme.accentInteractive.resolve(in: dark), Color(hex: 0x0a84ff).resolve(in: dark), "accent dark")
        assertSame(Theme.accentInteractive.resolve(in: light), Color(hex: 0x007aff).resolve(in: light), "accent light")
    }

    /// `Color.Resolved` is linear sRGB — compare against a resolved hex
    /// rather than respelling the curve.
    private func assertSame(_ a: Color.Resolved, _ b: Color.Resolved, _ name: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.red, b.red), (a.green, b.green), (a.blue, b.blue), (a.opacity, b.opacity)] {
            XCTAssertEqual(Double(x), Double(y), accuracy: 0.002, name, file: file, line: line)
        }
    }

    /// Card elevation values — Card Float (light) and Card Lift Dark.
    func testCardElevationValues() {
        XCTAssertEqual(Theme.cardFloatRadius, 8)
        XCTAssertEqual(Theme.cardFloatY, 4)
        XCTAssertEqual(Theme.cardLiftShadowRadius, 6, "Figma blur 12 → SwiftUI radius 6")
        XCTAssertEqual(Theme.cardLiftShadowY, 4)
        XCTAssertEqual(Theme.cardLiftHighlightY, 1)
        XCTAssertEqual(Theme.cardHairlineWidth, 0.5)
    }

    /// The melt's ground is surface/background resolved per mode.
    func testMeltGroundIsSurfaceBackground() {
        let env = EnvironmentValues()
        assertSame(Theme.Fade.ground(dark: true).resolve(in: env), Color(hex: 0x000000).resolve(in: env), "ground dark")
        assertSame(Theme.Fade.ground(dark: false).resolve(in: env), Color(hex: 0xf2f2f7).resolve(in: env), "ground light")
    }

    /// The dark melt blob fills with the band's end at full strength.
    func testDarkBlobIsFullStrength() {
        XCTAssertEqual(Theme.Fade.blobOpacityDark, 1)
    }
}
