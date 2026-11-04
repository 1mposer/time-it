import XCTest
@testable import TimeIt

/// The dashboard pull-down stagger — hand-derived from
/// rb(x) = 0.55·x·d / (d + 0.55·x), extra(i) = rb(x)·(i + 1)·k, k = 0.6 (the owner's
/// 2026-11-04 tune, `bf8c6db` — re-derived from the 0.8 values).
final class PullStaggerTests: XCTestCase {

    func testRubberBandMatchesTheUIKitCurve() {
        // d = 844, x = 100: 0.55·100·844 / (844 + 55) = 46420 / 899 = 51.635
        // (REFERENCE.md: "100 pt of drag moves 52 pt").
        XCTAssertEqual(PullStagger.rubberBand(100, dimension: 844), 51.635, accuracy: 0.001)
        // x = 844: c·x = 464.2; 464.2·844 / (844 + 464.2) = 391784.8 /
        // 1308.2 = 299.48 ("844 pt moves 300 pt").
        XCTAssertEqual(PullStagger.rubberBand(844, dimension: 844), 299.48, accuracy: 0.01)
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
        for (a, b) in zip(offsets, offsets.dropFirst()) {
            XCTAssertGreaterThan(b, a)
        }
        // Every gap grows by the same rb·k: rb(80) = 30800 / 744 = 41.398,
        // × 0.6 = 24.839.
        XCTAssertEqual(offsets[1] - offsets[0], 24.839, accuracy: 0.001)
        XCTAssertEqual(offsets[4] - offsets[3], 24.839, accuracy: 0.001)
    }

    func testMonotonicInOverscroll() {
        let a = PullStagger.offset(overscroll: 40, index: 2, viewport: 700)
        let b = PullStagger.offset(overscroll: 80, index: 2, viewport: 700)
        XCTAssertGreaterThan(b, a)
    }

    func testBoundedByTheViewportHoweverHardThePull() {
        // rb < d, so extra(i) < d·(i + 1)·k.
        for pull: CGFloat in [100, 1_000, 100_000] {
            let extra = PullStagger.offset(overscroll: pull, index: 4, viewport: 700)
            XCTAssertLessThan(extra, 700 * 5 * PullStagger.k)
        }
    }

    func testTheFifthCardTravelsAboutTwiceTheFirst() {
        // Total travel = overscroll + extra. x = 80, d = 700: first
        // 80 + 24.839 = 104.839, fifth 80 + 124.194 = 204.194 → 1.948×.
        let x: CGFloat = 80
        let first = x + PullStagger.offset(overscroll: x, index: 0, viewport: 700)
        let fifth = x + PullStagger.offset(overscroll: x, index: 4, viewport: 700)
        XCTAssertEqual(fifth / first, 1.948, accuracy: 0.001)
        // And it holds across pulls: x = 20 → rb 10.830, 1.981×;
        // x = 200 → rb 95.062, 1.888×.
        for pull: CGFloat in [20, 200] {
            let f = pull + PullStagger.offset(overscroll: pull, index: 0, viewport: 700)
            let l = pull + PullStagger.offset(overscroll: pull, index: 4, viewport: 700)
            XCTAssertTrue((1.85...2.0).contains(l / f), "pull \(pull): \(l / f)")
        }
    }
}
