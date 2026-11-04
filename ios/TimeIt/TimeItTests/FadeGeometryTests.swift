import XCTest
@testable import TimeIt

/// The dashboard band melt (Figma Final – Opus v1, `839:3930` light /
/// `839:4160` dark). Every value is hand-pinned from the frame: first card
/// top at y229, the "Band melt" group 393×340, mask stops 100% to y229 then
/// 80/52/26/8/0% at y250/274/298/320/340, blob top-left (−90, 150).
final class FadeGeometryTests: XCTestCase {

    private func assertStops(_ stops: [FadeGeometry.MaskStop],
                             _ expected: [(Double, Double)],
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(stops.count, expected.count, file: file, line: line)
        for (stop, want) in zip(stops, expected) {
            XCTAssertEqual(Double(stop.location), want.0, accuracy: 1e-9, file: file, line: line)
            XCTAssertEqual(stop.opacity, want.1, accuracy: 1e-9, file: file, line: line)
        }
    }

    // MARK: mask

    func testFigmaFrameMaskStops() {
        // First card top 229 → group height 229 + 111 = 340 (the Figma group).
        let g = FadeGeometry(firstCardTop: 229)
        XCTAssertEqual(g.groupHeight, 340)
        assertStops(g.maskStops, [
            (0, 1),
            (229.0 / 340, 1),
            (250.0 / 340, 0.80),
            (274.0 / 340, 0.52),
            (298.0 / 340, 0.26),
            (320.0 / 340, 0.08),
            (1, 0),
        ])
    }

    func testStopsFollowTheFirstCardTop() {
        // A taller header (top 260) keeps the same offsets below the card:
        // 260, 281, 305, 329, 351, 371 over a 371 group.
        let g = FadeGeometry(firstCardTop: 260)
        XCTAssertEqual(g.groupHeight, 371)
        assertStops(g.maskStops, [
            (0, 1),
            (260.0 / 371, 1),
            (281.0 / 371, 0.80),
            (305.0 / 371, 0.52),
            (329.0 / 371, 0.26),
            (351.0 / 371, 0.08),
            (1, 0),
        ])
    }

    func testTheMeltEndIsOneConstant() {
        XCTAssertEqual(Theme.Fade.endBelowFirstCard, 111)
        // The offsets are written in the fixed Figma span; the default
        // geometry reads the tunable constant, so editing the constant alone
        // moves the end and rescales every stop with it.
        XCTAssertEqual(Theme.Fade.referenceSpan, 111)
        XCTAssertEqual(Theme.Fade.maskOffsets.last?.offset, Theme.Fade.referenceSpan)
        XCTAssertEqual(FadeGeometry(firstCardTop: 229),
                       FadeGeometry(firstCardTop: 229, endBelowFirstCard: Theme.Fade.endBelowFirstCard))
        // Carried lower (160): the intermediate stops scale with the end,
        // so the curve keeps its shape — +0, +30.27, +64.86, +99.46, +131.17, +160.
        let g = FadeGeometry(firstCardTop: 229, endBelowFirstCard: 160)
        XCTAssertEqual(g.groupHeight, 389)
        XCTAssertEqual(Double(g.maskStops[2].location), (229 + 21.0 * 160 / 111) / 389, accuracy: 1e-9)
        XCTAssertEqual(g.maskStops.last?.opacity, 0)
        XCTAssertEqual(g.maskStops.last?.location, 1)
    }

    func testStopsAscendWithinTheUnitInterval() {
        for top in [0.0, 120, 229, 400] as [CGFloat] {
            let stops = FadeGeometry(firstCardTop: top).maskStops
            XCTAssertEqual(stops.first?.location, 0)
            XCTAssertEqual(stops.last?.location, 1)
            for (a, b) in zip(stops, stops.dropFirst()) {
                XCTAssertLessThanOrEqual(a.location, b.location)
                XCTAssertGreaterThanOrEqual(a.opacity, b.opacity, "the melt never brightens")
            }
        }
    }

    func testNegativeTopClampsToZero() {
        // A not-yet-measured header must not produce a negative group.
        let g = FadeGeometry(firstCardTop: -40)
        XCTAssertEqual(g.groupHeight, 111)
        XCTAssertEqual(Double(g.maskStops[1].location), 0, accuracy: 1e-9)
    }

    // MARK: blob

    func testLightBlobRect() {
        // Figma: 400×300 at (−90, 150) with the card top at 229 → 79 above it.
        let rect = FadeGeometry(firstCardTop: 229).blobRect(dark: false)
        XCTAssertEqual(rect, CGRect(x: -90, y: 150, width: 400, height: 300))
        XCTAssertEqual(rect.midX, 110)
        XCTAssertEqual(rect.midY, 300)
    }

    func testDarkBlobRect() {
        let rect = FadeGeometry(firstCardTop: 229).blobRect(dark: true)
        XCTAssertEqual(rect, CGRect(x: -90, y: 150, width: 300, height: 240))
    }

    func testBlobFollowsTheFirstCardTop() {
        let rect = FadeGeometry(firstCardTop: 260).blobRect(dark: false)
        XCTAssertEqual(rect.minY, 181)
        XCTAssertEqual(rect.minX, -90)
    }

    // MARK: drift

    func testDriftIsAtKeyframeAAtZero() {
        XCTAssertEqual(FadeGeometry.driftOffset(at: 0, reduceMotion: false), .zero)
    }

    func testDriftReachesKeyframeBAtOneLeg() {
        let b = FadeGeometry.driftOffset(at: 30, reduceMotion: false)
        XCTAssertEqual(b.width, 90, accuracy: 1e-9)
        XCTAssertEqual(b.height, 25, accuracy: 1e-9)
    }

    func testDriftReturnsToAAfterTwoLegs() {
        let back = FadeGeometry.driftOffset(at: 60, reduceMotion: false)
        XCTAssertEqual(back.width, 0, accuracy: 1e-9)
        XCTAssertEqual(back.height, 0, accuracy: 1e-9)
        // And it is periodic: 90 s sits on B again.
        XCTAssertEqual(FadeGeometry.driftOffset(at: 90, reduceMotion: false).width, 90, accuracy: 1e-9)
    }

    func testDriftEasesInAndOut() {
        // Cosine ease: exactly halfway at the leg's midpoint, and slow at
        // the ends — 3 s in covers (1 − cos(π/10))/2 = 2.447% of the leg.
        let mid = FadeGeometry.driftOffset(at: 15, reduceMotion: false)
        XCTAssertEqual(mid.width, 45, accuracy: 1e-9)
        XCTAssertEqual(mid.height, 12.5, accuracy: 1e-9)
        let early = FadeGeometry.driftOffset(at: 3, reduceMotion: false)
        XCTAssertEqual(early.width, 90 * 0.0244717418, accuracy: 1e-6)
        // Symmetric on the way back.
        XCTAssertEqual(FadeGeometry.driftOffset(at: 57, reduceMotion: false).width,
                       early.width, accuracy: 1e-9)
    }

    func testDriftIsOffUnderReduceMotion() {
        for t in [0.0, 15, 30, 45, 1234.5] {
            XCTAssertEqual(FadeGeometry.driftOffset(at: t, reduceMotion: true), .zero)
        }
    }

    // MARK: band colours

    func testBandEndpointsPerScheme() {
        typealias H = Theme.Fade.BandHex
        XCTAssertEqual(Theme.Fade.bandHex(.cool, dark: false), H(start: 0x1774ff, end: 0x68d7fc))
        XCTAssertEqual(Theme.Fade.bandHex(.mid, dark: false), H(start: 0xe49b23, end: 0xf3ca5d))
        XCTAssertEqual(Theme.Fade.bandHex(.hot, dark: false), H(start: 0xee6a4d, end: 0xfa9c86))
        XCTAssertEqual(Theme.Fade.bandHex(.cool, dark: true), H(start: 0x1a5fd6, end: 0x2690b8))
        XCTAssertEqual(Theme.Fade.bandHex(.mid, dark: true), H(start: 0xb26414, end: 0xd4992a))
        XCTAssertEqual(Theme.Fade.bandHex(.hot, dark: true), H(start: 0xc24a2c, end: 0xc86a50))
    }
}
