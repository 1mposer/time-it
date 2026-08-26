import XCTest
@testable import TimeIt

/// The phrases toggle's reduction rule — phrase keyed on (first hour tier,
/// last hour tier) → 9 cases; any interior hour outside the CLOSED tier span
/// between first and last overrides to "Mixed conditions". Ten strings, one
/// rule — the phrase can never contradict the gradient.
final class TrajectoryPhraseTests: XCTestCase {

    // MARK: the 9 (first, last) cases — no interior escape

    func testSpecExampleGoodTurningPerfect() {
        // The one string pinned verbatim ("Good, turning perfect").
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .orange, .green]), "Good, turning perfect")
    }

    func testAllNinePairCases() {
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .red]), "Nothing in your range",
                       "the (red, red) case IS the §2 all-bad copy — an interior lift escapes to Mixed, so it only renders all-red")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .orange]), "Bad, turning good")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .green]), "Bad, turning perfect")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .red]), "Good, turning bad")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .orange]), "Good throughout")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .green]), "Good, turning perfect")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green, .red]), "Perfect, turning bad")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green, .orange]), "Perfect, turning good")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green, .green]), "Perfect throughout")
    }

    func testExactlyTenDistinctStrings() {
        // "Ten strings, one rule" — the 9 pair cases plus Mixed, no accidental
        // duplicates collapsing two trajectories into one phrase.
        let pairs: [[HourTier]] = [
            [.red, .red], [.red, .orange], [.red, .green],
            [.orange, .red], [.orange, .orange], [.orange, .green],
            [.green, .red], [.green, .orange], [.green, .green],
        ]
        var strings = Set(pairs.compactMap { TrajectoryPhrase.phrase(for: $0) })
        strings.insert("Mixed conditions")
        XCTAssertEqual(strings.count, 10)
    }

    // MARK: the interior-escape override

    func testInteriorDipOutsideSpanIsMixedConditions() {
        // Canonical case: green→green with an orange dip.
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green, .orange, .green]), "Mixed conditions")
    }

    func testInteriorLiftAboveSpanIsMixedConditions() {
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .green, .red]), "Mixed conditions")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .green, .orange]), "Mixed conditions")
    }

    func testInteriorWithinTheClosedSpanDoesNotEscape() {
        // Zigzag INSIDE the span keeps the trajectory phrase — the escape rule
        // only fires for tiers outside [min(first,last), max(first,last)].
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .green, .orange, .green]), "Good, turning perfect")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .orange, .red, .green]), "Bad, turning perfect")
    }

    // MARK: flat + degenerate cases

    func testFlatRangesReadThroughout() {
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green, .green, .green, .green]), "Perfect throughout")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.orange, .orange, .orange]), "Good throughout")
    }

    func testAllBadRangeReadsNothingInYourRange() {
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red, .red, .red, .red]), "Nothing in your range")
    }

    func testSingleHourRangeUsesItsFlatPhrase() {
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.green]), "Perfect throughout")
        XCTAssertEqual(TrajectoryPhrase.phrase(for: [.red]), "Nothing in your range")
    }

    func testEmptyTiersHaveNoPhrase() {
        XCTAssertNil(TrajectoryPhrase.phrase(for: []))
    }

    // MARK: enablement — default off; Differentiate Without Color forces on

    func testPhrasesEnabledRule() {
        XCTAssertFalse(TrajectoryPhrase.phrasesEnabled(preference: false, differentiateWithoutColor: false),
                       "default off — the card shows no words (§2 owner decision C)")
        XCTAssertTrue(TrajectoryPhrase.phrasesEnabled(preference: true, differentiateWithoutColor: false))
        XCTAssertTrue(TrajectoryPhrase.phrasesEnabled(preference: false, differentiateWithoutColor: true),
                      "Differentiate Without Color force-enables — color is never the only carrier")
        XCTAssertTrue(TrajectoryPhrase.phrasesEnabled(preference: true, differentiateWithoutColor: true))
    }
}
