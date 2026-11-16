import XCTest
@testable import TimeIt

/// Owner ruling 02 a (2026-11-15): the ring's colour follows the SCORE band —
/// ≥70 rating/perfect green, 40–69 rating/good orange, <40 rating/bad red;
/// nil → the empty ring's grey track. The verdict keeps `ratingTint` on its
/// own line (ADR-0011 independence: the score never feeds a verdict).
final class ScoreBandTests: XCTestCase {

    func testBandEdges() {
        XCTAssertEqual(ScoreBand(score: 100), .high)
        XCTAssertEqual(ScoreBand(score: 70), .high, "70 is the first green")
        XCTAssertEqual(ScoreBand(score: 69), .middle)
        XCTAssertEqual(ScoreBand(score: 40), .middle, "40 is the first orange")
        XCTAssertEqual(ScoreBand(score: 39), .low)
        XCTAssertEqual(ScoreBand(score: 1), .low)
        XCTAssertEqual(ScoreBand(score: nil), .empty)
    }

    func testTintMapsTheBandToTheRatingTokens() {
        XCTAssertEqual(Theme.scoreBandTint(86), Theme.perfectGreen)
        XCTAssertEqual(Theme.scoreBandTint(54), Theme.ratingGood)
        XCTAssertEqual(Theme.scoreBandTint(20), Theme.badRed)
        XCTAssertEqual(Theme.scoreBandTint(nil), Theme.timelineTrack)
    }

    /// The Stars case that opened the rethink: a Perfect verdict with a
    /// score of 20 — the ring is red, the verdict line stays green.
    func testAPerfectVerdictWithALowScoreKeepsBothColours() {
        XCTAssertEqual(Theme.scoreBandTint(20), Theme.badRed)
        XCTAssertEqual(Theme.ratingTint(.perfect), Theme.perfectGreen)
    }
}
