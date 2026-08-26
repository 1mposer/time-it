import XCTest
@testable import TimeIt

/// The range renders as a gradient slice with one color stop per hour,
/// truthful to the per-hour tiers — a green-orange-green afternoon renders
/// exactly that (zigzag preserved), and an all-bad range is solid red (bad
/// weather is painted, never absent). The midpoint math stays exact, and a
/// YELLOW BLEND WAYPOINT is inserted at the hour boundary `(i+1)/n` at every
/// green↔orange transition — both directions, never at a red boundary.
/// Yellow is a waypoint color, not a fourth tier: `HourTier` stays three
/// cases; yellow exists only inside the gradient stop model.
final class TierGradientTests: XCTestCase {

    private let G = SliceStopColor.tier(.green)
    private let O = SliceStopColor.tier(.orange)
    private let R = SliceStopColor.tier(.red)
    private let Y = SliceStopColor.blend

    private func assertStops(_ tiers: [HourTier],
                             _ expected: [(Double, SliceStopColor)],
                             file: StaticString = #filePath, line: UInt = #line) {
        let stops = TierGradient.stops(for: tiers)
        XCTAssertEqual(stops.count, expected.count,
                       "expected \(expected.count) stops, got \(stops.map { ($0.location, $0.color) })",
                       file: file, line: line)
        for (stop, want) in zip(stops, expected) {
            XCTAssertEqual(stop.location, want.0, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(stop.color, want.1, file: file, line: line)
        }
    }

    func testEmptyTiersProduceNoStops() {
        XCTAssertEqual(TierGradient.stops(for: []), [])
    }

    func testSingleHourPinsItsTierAcrossTheWholeSlice() {
        assertStops([.green], [(0, G), (0.5, G), (1, G)])
    }

    func testStopsSitAtHourMidpointsWithPinnedEdges() {
        // Midpoint math: 4 hours → edge + 4 midpoints at (i+0.5)/4 + edge.
        // The one boundary here is R→O — red, so no waypoint appears.
        assertStops([.red, .red, .orange, .orange],
                    [(0, R), (0.125, R), (0.375, R), (0.625, O), (0.875, O), (1, O)])
    }

    func testYellowWaypointAtGreenToOrangeBoundary() {
        assertStops([.green, .orange],
                    [(0, G), (0.25, G), (0.5, Y), (0.75, O), (1, O)])
    }

    func testYellowWaypointAtOrangeToGreenBoundary() {
        // Both directions — the waypoint is about the PAIR, not the order.
        assertStops([.orange, .green],
                    [(0, O), (0.25, O), (0.5, Y), (0.75, G), (1, G)])
    }

    func testNoWaypointAtRedBoundaries() {
        // G→R and R→O both touch red — red keeps hard transitions; the
        // waypoint exists only to kill the green↔orange brown smudge.
        assertStops([.green, .red, .orange],
                    [(0, G), (1.0 / 6, G), (0.5, R), (5.0 / 6, O), (1, O)])
    }

    func testFlatRunsGetNoWaypoints() {
        let stops = TierGradient.stops(for: [.green, .green, .green])
        XCTAssertTrue(stops.allSatisfy { $0.color == G }, "no boundary → no waypoint")
    }

    func testZigzagIsPreservedWithWaypointsOnBothShoulders() {
        // Truthfulness rule: the interior dip survives at its hour's
        // midpoint, flanked by a waypoint on each green↔orange shoulder.
        assertStops([.green, .orange, .green],
                    [(0, G), (1.0 / 6, G), (1.0 / 3, Y), (0.5, O), (2.0 / 3, Y), (5.0 / 6, G), (1, G)])
    }

    func testAllBadRangeIsSolidRed() {
        let stops = TierGradient.stops(for: [.red, .red, .red])
        XCTAssertTrue(stops.allSatisfy { $0.color == R }, "all-bad renders solid red — visibly bad, never absent")
    }

    func testLocationsAreStrictlyAscendingWithinUnitInterval() {
        // Waypoints at (i+1)/n interleave strictly between the midpoints at
        // (i±0.5)/n — no collisions, no reordering.
        let stops = TierGradient.stops(for: [.red, .orange, .green, .orange, .red, .green])

        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThan(a.location, b.location)
        }
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.last?.location, 1)
    }

    func testBlendIsAWaypointNotAFourthTier() {
        // Exactly three tiers — yellow lives only in the stop model;
        // `HourTier` cannot represent it, so chips, phrases, and solid
        // fills (all typed on HourTier) can never paint it.
        XCTAssertEqual(HourTier.allCases, [.red, .orange, .green])

        // And inside the gradient it only ever sits BETWEEN a green stop and
        // an orange stop — never at an edge, never beside red.
        let stops = TierGradient.stops(for: [.red, .orange, .green, .orange, .red, .green, .green, .orange])
        let blendIndices = stops.indices.filter { stops[$0].color == Y }
        XCTAssertFalse(blendIndices.isEmpty, "sequence has G↔O boundaries — the assertion must not be vacuous")
        for index in blendIndices {
            XCTAssertTrue(index > 0 && index < stops.count - 1, "a waypoint is never an edge stop")
            let neighbors = Set([stops[index - 1].color, stops[index + 1].color])
            XCTAssertEqual(neighbors, [G, O], "a waypoint sits between one green and one orange stop")
        }
    }

    func testCanonicalFigmaVariantStopTables() {
        // The nine "Tier Gradient Slice" variants as exact stop tables.
        assertStops([.green], [(0, G), (0.5, G), (1, G)])
        assertStops([.green, .green, .green, .green],
                    [(0, G), (0.125, G), (0.375, G), (0.625, G), (0.875, G), (1, G)])
        assertStops([.orange, .orange, .orange, .orange],
                    [(0, O), (0.125, O), (0.375, O), (0.625, O), (0.875, O), (1, O)])
        assertStops([.red, .red, .red, .red],
                    [(0, R), (0.125, R), (0.375, R), (0.625, R), (0.875, R), (1, R)])
        assertStops([.orange, .green, .green, .green],
                    [(0, O), (0.125, O), (0.25, Y), (0.375, G), (0.625, G), (0.875, G), (1, G)])
        assertStops([.green, .green, .green, .orange],
                    [(0, G), (0.125, G), (0.375, G), (0.625, G), (0.75, Y), (0.875, O), (1, O)])
        assertStops([.green, .orange, .green],
                    [(0, G), (1.0 / 6, G), (1.0 / 3, Y), (0.5, O), (2.0 / 3, Y), (5.0 / 6, G), (1, G)])
        assertStops([.red, .orange, .green, .green],
                    [(0, R), (0.125, R), (0.375, O), (0.5, Y), (0.625, G), (0.875, G), (1, G)])
        assertStops([.red, .orange, .green, .green, .orange, .green],
                    [(0, R), (1.0 / 12, R), (3.0 / 12, O), (4.0 / 12, Y), (5.0 / 12, G),
                     (7.0 / 12, G), (8.0 / 12, Y), (9.0 / 12, O), (10.0 / 12, Y), (11.0 / 12, G), (1, G)])
    }
}
