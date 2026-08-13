import XCTest
@testable import TimeIt

/// Spec 14 §2: the range renders as a gradient slice with one color stop per
/// hour, truthful to the per-hour tiers — a green-orange-green afternoon
/// renders exactly that (zigzag preserved), and an all-bad range is solid red
/// (bad weather is painted, never absent). This is the pure stop-placement
/// layer (feasibility I6); binding tiers to actual colors is the rendering
/// wave's job (ADR-0008 gate).
final class TierGradientTests: XCTestCase {

    func testEmptyTiersProduceNoStops() {
        XCTAssertEqual(TierGradient.stops(for: []), [])
    }

    func testSingleHourPinsItsTierAcrossTheWholeSlice() {
        let stops = TierGradient.stops(for: [.green])

        XCTAssertEqual(stops.map(\.tier), [.green, .green, .green])
        XCTAssertEqual(stops.map(\.location), [0, 0.5, 1])
    }

    func testStopsSitAtHourMidpointsWithPinnedEdges() {
        let stops = TierGradient.stops(for: [.green, .orange, .orange, .red])

        // 4 hours → edge + 4 midpoints + edge; midpoints at (i + 0.5)/4.
        XCTAssertEqual(stops.count, 6)
        XCTAssertEqual(stops.map(\.tier), [.green, .green, .orange, .orange, .red, .red],
                       "edges repeat the first/last hour's tier so the slice never fades to nothing")
        let expected: [Double] = [0, 0.125, 0.375, 0.625, 0.875, 1]
        for (stop, location) in zip(stops, expected) {
            XCTAssertEqual(stop.location, location, accuracy: 1e-9)
        }
    }

    func testZigzagIsPreserved() {
        // The truthfulness rule: a green-orange-green afternoon renders as
        // exactly that — the interior dip must survive as its own stop.
        let stops = TierGradient.stops(for: [.green, .orange, .green])

        XCTAssertEqual(stops.map(\.tier), [.green, .green, .orange, .green, .green])
        XCTAssertEqual(stops[2].location, 0.5, accuracy: 1e-9, "the dip sits at its hour's midpoint")
    }

    func testAllBadRangeIsSolidRed() {
        let stops = TierGradient.stops(for: [.red, .red, .red])

        XCTAssertTrue(stops.allSatisfy { $0.tier == .red }, "all-bad renders solid red — visibly bad, never absent")
    }

    func testLocationsAreStrictlyAscendingWithinUnitInterval() {
        let stops = TierGradient.stops(for: [.red, .orange, .green, .orange, .red, .green])

        for (a, b) in zip(stops, stops.dropFirst()) {
            XCTAssertLessThan(a.location, b.location)
        }
        XCTAssertEqual(stops.first?.location, 0)
        XCTAssertEqual(stops.last?.location, 1)
    }
}
