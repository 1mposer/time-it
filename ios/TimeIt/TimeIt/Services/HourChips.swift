import Foundation

/// Which hour the detail's metric cards read (fresh-eyes row 7b, owner
/// 2026-11-12): nil = the span's average (the opening state). Tapping a chip
/// selects its hour, tapping it again returns to the average. Stored by
/// global position and checked against the span on every read, so a span
/// that moves off the chosen hour reads as the average without a reset race.
struct HourChipSelection: Equatable {
    private(set) var position: Int?

    /// A chip tap: toggles that hour. An hour with no data (gone, or past
    /// the horizon) has nothing to show, so it is not selectable.
    mutating func tap(_ position: Int, in slots: [HourSlot]) {
        guard slots.contains(where: { $0.position == position && $0.index != nil }) else { return }
        self.position = self.position == position ? nil : position
    }

    /// Back to the average (the caption tap, a new span, a day jump).
    mutating func clear() { position = nil }

    /// The selected hour if the span still holds it with data; else nil.
    func hour(in slots: [HourSlot]) -> HourSlot? {
        guard let position else { return nil }
        return slots.first { $0.position == position && $0.index != nil }
    }
}

/// The pure copy and reading behind the chip row and its caption.
enum HourChips {
    /// "6am" — a chip's clock hour, the app's am/pm dialect.
    static func label(_ slot: HourSlot) -> String {
        RangeText.hourText(slot.localHour)
    }

    /// The row's leading segment — the average, selected by default.
    static let averageLabel = "Avg"

    /// What the cards show, in plain words (owner, seen live 2026-11-12:
    /// the row must explain itself): "Average of 6 – 10am · tap an hour"
    /// (the span, exclusive end — the Range's own phrasing) or, with an hour
    /// selected, "At 9am".
    static func caption(slots: [HourSlot], selected: HourSlot?) -> String {
        if let selected { return "At \(label(selected))" }
        guard let first = slots.first, let last = slots.last,
              let window = SpanScoring.window(startHour: first.localHour,
                                              endHour: (last.localHour + 1) % 24) else {
            return "Average · tap an hour"
        }
        return "Average of \(RangeText.chipLabel(window)) · tap an hour"
    }

    /// What the cards show: the chosen hour, else the span's average
    /// (`HourAggregate`).
    static func reading(slots: [HourSlot], hours: [HourlyWeather], selected: HourSlot?) -> HourlyWeather? {
        if let index = selected?.index, hours.indices.contains(index) { return hours[index] }
        return HourAggregate.aggregate(slots: slots, hours: hours)
    }
}
