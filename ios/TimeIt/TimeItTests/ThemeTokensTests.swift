import SwiftUI
import UIKit
import XCTest
@testable import TimeIt

/// Every colour token resolves to the Figma Semantic value in BOTH modes
/// (Light → Dark; Dark is the sage ladder C and the brand accent, owner rulings 2026-11-11). Resolved against a real trait
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
        assertToken(T.appBackground, light: 0xf2f2f7, dark: 0x161915, "surface/background (owner dark palette)")
        assertToken(T.cardBackground, light: 0xffffff, dark: 0x222721, "surface/card (dark surface)")
        assertToken(T.primaryText, light: 0x1c1c1e, dark: 0xd7dcd6, "text/primary")
        assertToken(T.secondaryText, light: 0x8e8e93, dark: 0x8f9d8b, "text/secondary")
        assertToken(T.onGradient, light: 0xffffff, dark: 0xffffff, "text/on-gradient")
        assertToken(T.onFill, light: 0xffffff, dark: 0x161915, "text/on-fill (dark buttonLabel)")
        assertToken(T.divider, light: 0x3c3c43, dark: 0x31372f, lightAlpha: 18, darkAlpha: 100, "separator (dark divider)")
        assertToken(T.timelineTrack, light: 0xf2f2f7, dark: 0x31372f, "timeline/track (dark divider)")
    }

    func testRatingAndAccentTokens() {
        typealias T = Theme.UIColors
        assertToken(T.perfectGreen, light: 0x34c759, dark: 0x30d158, "rating/perfect")
        assertToken(T.ratingGood, light: 0xff9500, dark: 0xff9f0a, "rating/good")
        assertToken(T.badRed, light: 0xff3b30, dark: 0xff453a, "rating/bad")
        assertToken(T.blendYellow, light: 0xffbe0a, dark: 0xffbe0a, "rating/blend (same in both, intended)")
        assertToken(T.accentBrand, light: 0x48665c, dark: 0xb5beb2, "accent/brand (dark main)")
        assertToken(T.accentBrandFill, light: 0x48665c, dark: 0xb5beb2, "accent/brand-fill")
        assertToken(T.accentBrandPressed, light: 0x48665c, dark: 0x8f9d8b, "accent pressed (dark buttonPressed)")
        assertToken(T.disabledFill, light: 0x48665c, dark: 0x444d41, lightAlpha: 45, darkAlpha: 100, "disabled fill")
        assertToken(T.accentTint, light: 0x48665c, dark: 0xb5beb2, lightAlpha: 18, darkAlpha: 16, "accent tint")
        assertToken(T.accentDestructive, light: 0xff3b30, dark: 0xff453a, "accent/destructive")
    }

    func testChipTokens() {
        typealias T = Theme.UIColors
        assertToken(T.chipText(.green), light: 0x1a7a35, dark: 0x30d158, "chip/green/text")
        assertToken(T.chipText(.orange), light: 0xb85c00, dark: 0xff9f0a, "chip/orange/text")
        assertToken(T.chipText(.red), light: 0xc0392b, dark: 0xff453a, "chip/red/text")
        assertToken(T.chipText(.neutral), light: 0x636366, dark: 0x8f9d8b, "chip/neutral/text")
        assertToken(T.chipBackground(.green), light: 0x34c759, dark: 0x30d158, lightAlpha: 12, darkAlpha: 20, "chip/green/bg")
        assertToken(T.chipBackground(.orange), light: 0xff9500, dark: 0xff9f0a, lightAlpha: 12, darkAlpha: 20, "chip/orange/bg")
        assertToken(T.chipBackground(.red), light: 0xff3b30, dark: 0xff453a, lightAlpha: 12, darkAlpha: 20, "chip/red/bg")
        assertToken(T.chipBackground(.neutral), light: 0x8e8e93, dark: 0x8f9d8b, lightAlpha: 12, darkAlpha: 20, "chip/neutral/bg")
    }

    /// The light hairline is drawn only in light; dark's Card Lift highlight
    /// replaces it, so the token is fully clear in dark.
    func testCardHairlineIsLightOnly() {
        assertToken(Theme.UIColors.cardHairline, light: 0x000000, dark: 0x000000,
                    lightAlpha: 6, darkAlpha: 0, "card hairline")
    }

    /// The SwiftUI tokens are the UIColor tokens — resolving the `Color`
    /// through an environment gives the same per-mode value.
    func testSwiftUIColorsFollowTheScheme() {
        var light = EnvironmentValues()
        light.colorScheme = .light
        var dark = EnvironmentValues()
        dark.colorScheme = .dark
        assertSame(Theme.cardBackground.resolve(in: dark), Color(hex: 0x222721).resolve(in: dark), "card dark")
        assertSame(Theme.cardBackground.resolve(in: light), Color(hex: 0xffffff).resolve(in: light), "card light")
        assertSame(Theme.primaryText.resolve(in: dark), Color(hex: 0xd7dcd6).resolve(in: dark), "text dark")
        assertSame(Theme.accentBrand.resolve(in: dark), Color(hex: 0xb5beb2).resolve(in: dark), "accent dark")
        assertSame(Theme.accentBrand.resolve(in: light), Color(hex: 0x48665c).resolve(in: light), "accent light")
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
        assertSame(Theme.Fade.ground(dark: true).resolve(in: env), Color(hex: 0x161915).resolve(in: env), "ground dark")
        assertSame(Theme.Fade.ground(dark: false).resolve(in: env), Color(hex: 0xf2f2f7).resolve(in: env), "ground light")
    }

    /// The dark melt blob fills with the band's end at full strength.
    func testDarkBlobIsFullStrength() {
        XCTAssertEqual(Theme.Fade.blobOpacityDark, 1)
    }

    // MARK: Contrast floors (HIG 4.5:1 for text) — the ruled values must hold them

    private func luminance(_ c: RGBA) -> Double {
        func channel(_ v: UInt32) -> Double {
            let x = Double(v) / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.hex >> 16 & 0xff) + 0.7152 * channel(c.hex >> 8 & 0xff) + 0.0722 * channel(c.hex & 0xff)
    }

    private func contrast(_ a: UIColor, _ b: UIColor, _ style: UIUserInterfaceStyle) -> Double {
        let la = luminance(resolve(a, style)), lb = luminance(resolve(b, style))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    func testAccentHoldsTextContrastInBothModes() {
        typealias T = Theme.UIColors
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertGreaterThanOrEqual(contrast(T.accentBrand, T.cardBackground, style), 4.5, "accent on card \(style.rawValue)")
            XCTAssertGreaterThanOrEqual(contrast(T.accentBrand, T.appBackground, style), 4.5, "accent on ground \(style.rawValue)")
            XCTAssertGreaterThanOrEqual(contrast(T.onFill, T.accentBrandFill, style), 4.5, "label on fill \(style.rawValue)")
        }
        XCTAssertGreaterThanOrEqual(contrast(T.accentBrand, T.timelineTrack, .dark), 4.5, "main on the dark track")
        XCTAssertGreaterThanOrEqual(contrast(T.onFill, T.accentBrandPressed, .dark), 4.5, "label on the pressed fill")
        XCTAssertGreaterThanOrEqual(contrast(T.accentBrand, T.appBackground, .dark), 3, "the chosen outline against the ground")
        XCTAssertGreaterThanOrEqual(contrast(T.secondaryText, T.cardBackground, .dark), 4.5, "secondary on the dark card")
    }
}
