import XCTest
@testable import TimeIt

/// The detail's hour chips (fresh-eyes row 7b, owner 2026-11-12): the cards
/// read the span's average until a chip is tapped, then that hour; a second
/// tap on the chip — or the caption — returns to the average.
final class HourChipsTests: XCTestCase {

    private func hour(_ index: Int, temp: Double) -> HourlyWeather {
        HourlyWeather(index: index, temp: temp, humidity: 40, visibility: 10, uV: 3,
                      windSpeed: 10, rainFall: 0, cloudCover: 15,
                      moon: [], dustAlert: false, seaWarning: false,
                      darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0, tide: 0)
    }

    /// 6am–10am: positions 2…5 at local hours 6…9, all with data.
    private let slots = (0..<4).map { HourSlot(position: 2 + $0, localHour: 6 + $0, index: 2 + $0) }
    /// Temps 20…27 at indices 0…7.
    private var hours: [HourlyWeather] { (0..<8).map { hour($0, temp: Double(20 + $0)) } }

    // MARK: Selection

    func testOpensOnTheAverage() {
        XCTAssertNil(HourChipSelection().hour(in: slots))
    }

    func testTappingAChipSelectsThatHour() {
        var selection = HourChipSelection()
        selection.tap(4, in: slots)
        XCTAssertEqual(selection.hour(in: slots)?.position, 4)
    }

    func testTappingTheSelectedChipAgainReturnsToTheAverage() {
        var selection = HourChipSelection()
        selection.tap(4, in: slots)
        selection.tap(4, in: slots)
        XCTAssertNil(selection.hour(in: slots))
    }

    func testTappingAnotherChipMovesTheSelection() {
        var selection = HourChipSelection()
        selection.tap(4, in: slots)
        selection.tap(2, in: slots)
        XCTAssertEqual(selection.hour(in: slots)?.position, 2)
    }

    func testClearingReturnsToTheAverage() {
        var selection = HourChipSelection()
        selection.tap(4, in: slots)
        selection.clear()
        XCTAssertNil(selection.hour(in: slots))
    }

    func testAHourWithNoDataCannotBeSelected() {
        let gone = [HourSlot(position: 1, localHour: 5, index: nil)] + slots
        var selection = HourChipSelection()
        selection.tap(1, in: gone)
        XCTAssertNil(selection.hour(in: gone))
    }

    func testASelectionTheSpanNoLongerHoldsReadsAsTheAverage() {
        var selection = HourChipSelection()
        selection.tap(5, in: slots)
        XCTAssertNil(selection.hour(in: Array(slots.prefix(2))), "the span moved off the chosen hour")
    }

    // MARK: Caption

    /// Owner, seen live 2026-11-12: the row must explain itself — the
    /// caption says in plain words what the cards show, and how to change it.
    func testTheAverageCaptionNamesTheSpanAndTheGesture() {
        XCTAssertEqual(HourChips.caption(slots: slots, selected: nil), "Average of 6 – 10am · tap an hour")
    }

    func testTheCaptionFollowsTheSpanAcrossNoon() {
        let late = (0..<3).map { HourSlot(position: $0, localHour: 10 + $0, index: $0) }
        XCTAssertEqual(HourChips.caption(slots: late, selected: nil), "Average of 10am – 1pm · tap an hour")
    }

    func testASelectedHourCaptionSaysAtThatHour() {
        XCTAssertEqual(HourChips.caption(slots: slots, selected: slots[3]), "At 9am")
    }

    func testTheLeadingSegmentIsTheAverage() {
        XCTAssertEqual(HourChips.averageLabel, "Avg")
    }

    func testAChipIsLabelledWithItsClockHour() {
        XCTAssertEqual(HourChips.label(slots[0]), "6am")
        XCTAssertEqual(HourChips.label(HourSlot(position: 0, localHour: 0, index: 0)), "12am")
    }

    // MARK: The cards' reading

    func testTheCardsReadTheAverageWithNoSelection() {
        // Positions 2…5 → temps 22, 23, 24, 25 → mean 23.5.
        XCTAssertEqual(HourChips.reading(slots: slots, hours: hours, selected: nil)?.temp, 23.5)
    }

    func testTheCardsReadTheChosenHour() {
        XCTAssertEqual(HourChips.reading(slots: slots, hours: hours, selected: slots[2])?.temp, 24)
    }
}
