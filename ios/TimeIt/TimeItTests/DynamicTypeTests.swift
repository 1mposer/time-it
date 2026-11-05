import SwiftUI
import XCTest
@testable import TimeIt

/// The Dynamic Type pass (owner ruling 8, 2026-10-06; 9a, 2026-10-31; 5's
/// surviving part): the font map and the hero's height functions at the
/// default and at a scaled text size.
final class DynamicTypeFontMapTests: XCTestCase {
    func testFigmaStylesMapToTheirNearestSystemTextStyle() {
        typealias S = Theme.Typography.FigmaStyle
        let expected: [S: Font.TextStyle] = [
            .title: .body,              // Title 17 Semibold
            .cardTitle: .subheadline,   // Card Title Medium 15
            .body: .subheadline,        // Body 14
            .footnote: .footnote,       // Footnote 13
            .headerMeta: .footnote,     // Header Meta 13
            .cardSubtitle: .caption,    // Card Subtitle 12
            .hourLabel: .caption,       // Hour Label 12
            .ratingBadge: .caption,     // Rating Badge 12
            .chipSmall: .caption2,      // Chip Small 11
            .axisLabel: .caption2,      // Axis Label 10
            .heroNumeral: .title2,      // the hero numeral 24
            .score: .title,             // Score 28
        ]
        for style in S.allCases {
            XCTAssertEqual(style.textStyle, expected[style], "\(style)")
        }
        XCTAssertEqual(expected.count, S.allCases.count, "every Figma style is pinned")
    }

    func testTheMapCoversTheInBetweenSizesTheViewsUse() {
        let map = Theme.Typography.textStyle(forFigmaSize:)
        XCTAssertEqual(map(9), .caption2)
        XCTAssertEqual(map(11.5), .caption2, "Chip 11.5")
        XCTAssertEqual(map(22), .title2, "the metric value Semibold 22")
        XCTAssertEqual(map(16), .callout)
        XCTAssertEqual(map(20), .title3)
        XCTAssertEqual(map(34), .largeTitle)
    }

    func testTheRingNumeralCapIsTheFigmaScoreSize() {
        XCTAssertEqual(Theme.Detail.ringNumeralMax, Theme.Typography.FigmaStyle.score.size)
        XCTAssertGreaterThan(Theme.Detail.ringNumeralMax, Theme.Detail.ringNumeral)
    }
}

final class DynamicTypeHeroLayoutTests: XCTestCase {
    typealias L = Theme.Detail

    /// A large-text set (about the xxxLarge ratio on caption / footnote).
    private let scaled = Theme.Detail.HeroMetrics.scaled(wordHeight: 20, lineHeight: 35, spanRowHeight: 41)

    func testTheStandardSetIsTodaysConstants() {
        let standard = L.HeroMetrics.standard
        XCTAssertEqual(standard.wordHeight, L.wordHeight)
        XCTAssertEqual(standard.lineHeight, L.lineHeight)
        XCTAssertEqual(standard.spanRowHeight, L.spanRowHeight)
        XCTAssertEqual(L.scaledRingColumnHeight(standard), L.ringColumnHeight)
        XCTAssertEqual(L.heroHeight(hasLine: true, metrics: standard), 122)
        XCTAssertEqual(L.heroHeight(hasLine: true, hasSpanRow: true, metrics: standard), 141)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, metrics: standard), 17)
        XCTAssertEqual(L.hitPad(forSpanRowHeight: L.spanRowHeight), L.spanRowHitPad)
    }

    func testTheHeroGrowsWithTheScaledRows() {
        // Ring column 64 + 12 + 20 = 96; row block 24 + 8 + 35 = 67, + 8 + 41
        // = 116 with row 2; top (96 − 67) / 2 = 14.5.
        XCTAssertEqual(L.scaledRingColumnHeight(scaled), 96)
        XCTAssertEqual(L.rowColumnHeight(hasLine: true, metrics: scaled), 67)
        XCTAssertEqual(L.rowColumnHeight(hasLine: true, hasSpanRow: true, metrics: scaled), 116)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, metrics: scaled), 14.5)
        XCTAssertEqual(L.heroHeight(hasLine: true, metrics: scaled), 16 + 96 + 16)
        XCTAssertEqual(L.heroHeight(hasLine: true, hasSpanRow: true, metrics: scaled), 16 + 14.5 + 116 + 16)
        XCTAssertGreaterThan(L.heroHeight(hasLine: true, hasSpanRow: true, metrics: scaled),
                             L.heroHeight(hasLine: true, hasSpanRow: true))
    }

    func testThePillRowStaysFixedAsTheTextScales() {
        // The pill row is never scaled (ruling 9a), and its top never
        // depends on row 2 at any text size.
        XCTAssertEqual(L.rowColumnHeight(hasLine: false, metrics: scaled), L.pillHeight)
        XCTAssertEqual(L.rowColumnTop(hasLine: false, metrics: scaled), (L.ringDiameter - L.pillHeight) / 2)
        XCTAssertEqual(L.heroHeight(hasLine: true, hasSpanRow: true, metrics: scaled),
                       L.heroInset + L.rowColumnTop(hasLine: true, metrics: scaled)
                           + L.rowColumnHeight(hasLine: true, hasSpanRow: true, metrics: scaled) + L.heroBottom)
    }

    func testTheClampsHoldAtAccessibilitySizes() {
        // Row 1 outgrows the ring column: the block starts at the top
        // rather than above the hero.
        let huge = L.HeroMetrics.scaled(wordHeight: 40, lineHeight: 90, spanRowHeight: 80)
        XCTAssertEqual(L.rowColumnTop(hasLine: true, metrics: huge), 0)
        // A capsule taller than 44pt needs no hit padding (never negative).
        XCTAssertEqual(L.hitPad(forSpanRowHeight: 80), 0)
        // Row 1 is never shorter than its return piece (a small text size).
        let small = L.HeroMetrics.scaled(wordHeight: 13, lineHeight: 22, spanRowHeight: 26)
        XCTAssertEqual(small.lineHeight, L.returnPiece)
    }

    func testTheStackedHeroPutsTheRowBlockUnderTheRingColumn() {
        // Ruling 5: ring column on top, the 16pt gap, the row block.
        XCTAssertEqual(L.stackedHeroHeight(hasLine: true, metrics: scaled),
                       16 + 96 + 16 + 67 + 16)
        XCTAssertEqual(L.stackedHeroHeight(hasLine: true, hasSpanRow: true, metrics: scaled)
                           - L.stackedHeroHeight(hasLine: true, metrics: scaled),
                       L.rowToLine + scaled.spanRowHeight,
                       "row 2 only adds itself — the pill row above holds still")
        XCTAssertEqual(L.stackedHeroHeight(hasLine: false), 16 + 90 + 16 + 24 + 16)
    }
}
