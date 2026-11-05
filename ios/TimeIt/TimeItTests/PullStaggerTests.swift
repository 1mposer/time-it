import XCTest
@testable import TimeIt

/// The dashboard pull-down stagger — hand-derived from
/// rb(x) = 0.55·x·d / (d + 0.55·x), extra(i) = rb(x·(i + 1)·k), k = 0.35 (the
/// owner's 2026-11-05 ask "the swipe down goes down fast": the multiplied pull
/// now goes THROUGH the curve, replacing rb(x)·(i + 1)·0.6).
/// With d = 700: rb(x) = 385·x / (700 + 0.55·x).
final class PullStaggerTests: XCTestCase {

    func testRubberBandMatchesTheUIKitCurve() {
        // d = 844, x = 100: 0.55·100·844 / (844 + 55) = 46420 / 899 = 51.635
        // (REFERENCE.md: "100 pt of drag moves 52 pt").
        XCTAssertEqual(PullStagger.rubberBand(100, dimension: 844), 51.635, accuracy: 0.001)
        // x = 844: c·x = 464.2; 464.2·844 / (844 + 464.2) = 391784.8 /
        // 1308.2 = 299.48 ("844 pt moves 300 pt").
        XCTAssertEqual(PullStagger.rubberBand(844, dimension: 844), 299.48, accuracy: 0.01)
    }

    func testKIsTheOwnerTune() {
        XCTAssertEqual(PullStagger.k, 0.35)
    }

    func testZeroAtZeroOverscroll() {
        for index in 0..<6 {
            XCTAssertEqual(PullStagger.offset(overscroll: 0, index: index, viewport: 700), 0)
        }
    }

    func testZeroWhileScrolledNormally() {
        XCTAssertEqual(PullStagger.offset(overscroll: -120, index: 3, viewport: 700), 0)
    }

    func testMonotonicInIndexSoEveryGapGrows() {
        let offsets = (0..<6).map { PullStagger.offset(overscroll: 80, index: $0, viewport: 700) }
        // x = 80 → curve inputs 28, 56, 84, 112, 140, 168:
        // rb(28) = 10780 / 715.4 = 15.068; rb(56) = 21560 / 730.8 = 29.502;
        // rb(84) = 32340 / 746.2 = 43.340; rb(112) = 43120 / 761.6 = 56.618;
        // rb(140) = 53900 / 777.0 = 69.369; rb(168) = 64680 / 792.4 = 81.625.
        XCTAssertEqual(offsets[0], 15.068, accuracy: 0.001)
        XCTAssertEqual(offsets[4], 69.369, accuracy: 0.001)
        // Gaps 14.433, 13.838, 13.278, 12.752, 12.256: every gap grows
        // (strictly increasing in index) ...
        for (a, b) in zip(offsets, offsets.dropFirst()) {
            XCTAssertGreaterThan(b, a)
        }
        // ... and a later gap grows by no more than an earlier one (the
        // curve saturates).
        let gaps = zip(offsets, offsets.dropFirst()).map { $1 - $0 }
        for (earlier, later) in zip(gaps, gaps.dropFirst()) {
            XCTAssertLessThanOrEqual(later, earlier)
        }
        XCTAssertEqual(gaps[0], 14.433, accuracy: 0.001)
        XCTAssertEqual(gaps[4], 12.256, accuracy: 0.001)
    }

    func testMonotonicInOverscroll() {
        let a = PullStagger.offset(overscroll: 40, index: 2, viewport: 700)
        let b = PullStagger.offset(overscroll: 80, index: 2, viewport: 700)
        XCTAssertGreaterThan(b, a)
    }

    func testBoundedByTheViewportHoweverHardThePull() {
        // rb < d whatever its input, so every child's extra stays under one
        // viewport — the first and the fifth alike (x = 100 000, index 4:
        // rb(175 000) = 694.95 < 700).
        for pull: CGFloat in [100, 1_000, 100_000] {
            for index in [0, 4] {
                let extra = PullStagger.offset(overscroll: pull, index: index, viewport: 700)
                XCTAssertLessThan(extra, 700, "pull \(pull), index \(index)")
            }
        }
    }

    func testTheFifthCardTravelsAboutOneAndAHalfTimesTheFirst() {
        // Total travel = overscroll + extra. x = 80, d = 700: first
        // 80 + rb(28) = 95.068, fifth 80 + rb(140) = 149.369 → 1.571×.
        let x: CGFloat = 80
        let first = x + PullStagger.offset(overscroll: x, index: 0, viewport: 700)
        let fifth = x + PullStagger.offset(overscroll: x, index: 4, viewport: 700)
        XCTAssertEqual(fifth / first, 1.571, accuracy: 0.001)
        // And it holds across pulls: x = 20 → 23.829 vs 38.735, 1.626×;
        // x = 200 → 236.493 vs 350.980, 1.484×.
        for pull: CGFloat in [20, 200] {
            let f = pull + PullStagger.offset(overscroll: pull, index: 0, viewport: 700)
            let l = pull + PullStagger.offset(overscroll: pull, index: 4, viewport: 700)
            XCTAssertTrue((1.4...1.7).contains(l / f), "pull \(pull): \(l / f)")
        }
    }
}

/// The tunable pull-to-refresh (owner report 2026-11-05: the system control
/// fired too early). One threshold, one decision from the release point.
final class PullRefreshTests: XCTestCase {

    func testTheThresholdIsWellPastTheSystemControl() {
        XCTAssertEqual(PullRefresh.threshold, 110)
    }

    func testProgressFillsTheArcUpToTheThresholdAndClamps() {
        XCTAssertEqual(PullRefresh.progress(overscroll: 0), 0)
        XCTAssertEqual(PullRefresh.progress(overscroll: 55), 0.5)
        XCTAssertEqual(PullRefresh.progress(overscroll: 110), 1)
        XCTAssertEqual(PullRefresh.progress(overscroll: 400), 1)
        XCTAssertEqual(PullRefresh.progress(overscroll: -20), 0)
    }

    func testAReleaseFiresOnlyAtOrPastTheThreshold() {
        XCTAssertFalse(PullRefresh.fires(overscroll: 109.9))
        XCTAssertTrue(PullRefresh.fires(overscroll: 110))
        XCTAssertTrue(PullRefresh.fires(overscroll: 300))
    }

    func testTheDisarmFractionIsEightyPercent() {
        XCTAssertEqual(PullRefresh.disarmFraction, 0.8)
    }

    /// The haptic is the commitment: once armed, easing back to 105pt keeps
    /// it armed (the release refreshes); only under 88pt does it disarm, and
    /// crossing 110pt again re-arms.
    func testArmedHoldsUntilUnderTheDisarmLineAndReArmsPastTheThreshold() {
        XCTAssertFalse(PullRefresh.armed(wasArmed: false, overscroll: 109.9))
        XCTAssertTrue(PullRefresh.armed(wasArmed: false, overscroll: 110), "arms at the threshold")
        XCTAssertTrue(PullRefresh.armed(wasArmed: true, overscroll: 105), "easing back keeps the commitment")
        XCTAssertTrue(PullRefresh.armed(wasArmed: true, overscroll: 88), "88 = 110 × 0.8 still holds")
        XCTAssertFalse(PullRefresh.armed(wasArmed: true, overscroll: 87.9), "under the disarm line")
        XCTAssertFalse(PullRefresh.armed(wasArmed: false, overscroll: 100), "no re-arm below the threshold")
        XCTAssertTrue(PullRefresh.armed(wasArmed: false, overscroll: 110), "re-arms past it again")
    }
}

/// The dashboard rhythm (owner ruling 2026-11-05: wider tries returned,
/// the original values stay — as named tokens now).
final class DashboardRhythmTests: XCTestCase {
    func testTheOriginalRhythmIsPinned() {
        XCTAssertEqual(Theme.Spacing.listBelowHeader, 14)
        XCTAssertEqual(Theme.Spacing.cardGap, 10)
        XCTAssertEqual(Theme.Spacing.headerLocationToNumeral, 2)
        XCTAssertEqual(Theme.Spacing.headerNumeralToMeta, 10)
    }
}
