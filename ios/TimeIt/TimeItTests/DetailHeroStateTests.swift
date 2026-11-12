import XCTest
@testable import TimeIt

/// Pins the detail hero's dim rule (fresh-eyes row 5a, owner 2026-11-12):
/// while a previewed span is unscored the ring and the verdict word dim to
/// secondary — colour only. The numeral never changes (ADR-0011): the day's
/// score stays until the span is scored.
final class DetailHeroStateTests: XCTestCase {

    func testPreviewedSpanDimsRingAndWord() {
        // D1 — at the Range: the day's verdict in its own tint.
        XCTAssertFalse(SpanScoring.dimsVerdict(isAtRange: true, spanScored: false))
        // D2 — the carousel moved off the Range, nothing scored yet: dim.
        XCTAssertTrue(SpanScoring.dimsVerdict(isAtRange: false, spanScored: false))
        // D3 — the shown span has the server's score: its verdict, full tint.
        XCTAssertFalse(SpanScoring.dimsVerdict(isAtRange: false, spanScored: true))
        // Return — back on the Range: full tint again.
        XCTAssertFalse(SpanScoring.dimsVerdict(isAtRange: true, spanScored: false))
    }
}
