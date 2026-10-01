import Foundation

/// The Activity Detail v3 hero stepper — pure selection math over GLOBAL
/// `hours[]` indices, kept out of the view so bounds and snap-back are
/// testable.
///
/// Owner ruling (2026-09-30, [FIGMA.md §11](docs/design/FIGMA.md)): the
/// stepper MAY step past either end of the Range. Outside the Range the
/// coloured hour pills are hidden (the metric values still render, uncoloured)
/// and tapping the pill snaps the selection back into the Range. `−` dims at
/// the absolute WALKABLE lower bound — the first forecast hour the detail can
/// show today — not at the Range start (the frames predate the ruling and draw
/// the dim at the Range start, which is the same pixel whenever the Range
/// opens on the first available hour).
///
/// The frames do not draw the out-of-range or snap-back states; the snap
/// target therefore follows the spec's stated fallback — the NEAREST Range
/// end.
struct HourStepper: Equatable {
    /// Every hour the stepper may walk, as global `hours[]` indices.
    let walkable: Range<Int>
    /// The Activity's Range hours within the shown bucket; nil when the Range
    /// covers no forecast hour today (the whole walk is then out of range).
    let rangeHours: Range<Int>?
    /// The selected hour — always inside `walkable`.
    private(set) var selected: Int

    /// Clamps `selected` into `walkable` so no caller can seed an unreachable
    /// hour. `walkable` must be non-empty.
    init(walkable: Range<Int>, rangeHours: Range<Int>?, selected: Int) {
        self.walkable = walkable
        self.rangeHours = rangeHours.flatMap { $0.isEmpty ? nil : $0 }
        self.selected = Swift.min(Swift.max(selected, walkable.lowerBound), walkable.upperBound - 1)
    }

    /// The hour the detail opens on: the Range's first hour today, falling
    /// back to the first walkable hour when the Range covers none.
    static func initialSelection(walkable: Range<Int>, rangeHours: Range<Int>?) -> Int {
        if let rangeHours, !rangeHours.isEmpty { return rangeHours.lowerBound }
        return walkable.lowerBound
    }

    /// False at the absolute walkable lower bound — where `−` dims.
    var canStepBack: Bool { selected > walkable.lowerBound }

    /// False at the absolute walkable upper bound — where `+` dims.
    var canStepForward: Bool { selected < walkable.upperBound - 1 }

    /// Inside the authored Range. False → the coloured hour pills are hidden
    /// and the metric values render uncoloured.
    var isInRange: Bool { rangeHours?.contains(selected) ?? false }

    /// Where a tap on the pill returns to: the NEAREST Range end. Nil when
    /// the selection is already in range, or when the Range has no hours
    /// today (nothing to snap to).
    var snapBackTarget: Int? {
        guard let rangeHours, !isInRange else { return nil }
        if selected < rangeHours.lowerBound { return rangeHours.lowerBound }
        return rangeHours.upperBound - 1
    }

    mutating func stepBack() {
        guard canStepBack else { return }
        selected -= 1
    }

    mutating func stepForward() {
        guard canStepForward else { return }
        selected += 1
    }

    /// Snaps back into the Range; a no-op when already in range.
    mutating func snapBack() {
        guard let target = snapBackTarget else { return }
        selected = target
    }

    mutating func select(_ index: Int) {
        selected = Swift.min(Swift.max(index, walkable.lowerBound), walkable.upperBound - 1)
    }
}
