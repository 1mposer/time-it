import Foundation

/// The Activity Detail hero carousel — pure span + scroll-window math over
/// GLOBAL `hours[]` indices (depth & polish pass, build 8; owner rulings
/// 2026-10-31 / 2026-11-01, FIGMA.md §12). Replaces the single-hour stepper.
///
/// - The selection is a contiguous SPAN of hours the same length as the
///   rated Range, opening ON the Range. `−` / `+` (and a swipe) slide the
///   whole span one hour; `−` dims when the span's first hour is the first
///   walkable hour, `+` when its last hour is the last walkable hour.
/// - The row shows `visibleSlots` of the day's walkable hours. The window
///   holds still until the span's leading edge (last hour going forward,
///   first hour going back) would pass the second-to-last visible slot in
///   that direction; then it shifts just enough to keep exactly ONE slot of
///   lookahead beyond the span, and stops once the day's last (or first)
///   walkable hour is in view.
///
/// The window opens with ONE earlier slot visible left of the Range when
/// one exists (`visibleSlots` = Range + 2: one slot of lookback, one of
/// lookahead); a Range starting at the day's first walkable hour pins the
/// window to slot 0 with the spare slots ahead. The window never moves more
/// than one slot per step ("always 1 away").
///
/// Corners pinned in `HourCarouselTests`:
/// - When the 22pt pill floor caps `visibleSlots` below Range + 2, both
///   lookaheads cannot hold at once; the one-slot-per-step limit wins, so the
///   window trails by a slot rather than jumping.
/// - When the span is as long as the window or longer (`span >= visibleSlots`)
///   the window anchors on the span's first hour (clamped to the day).
/// - With no Range hours on the shown day the span is ONE hour at the first
///   walkable hour, and there is no Range to return to.
struct HourCarousel: Equatable {
    /// Every hour the row may show, as global `hours[]` indices. Non-empty.
    let walkable: Range<Int>
    /// The rated Range hours within the shown bucket; nil when none.
    let rangeHours: Range<Int>?
    /// The number of pill slots visible at once (capped to the walkable count).
    let visibleSlots: Int
    /// The chosen span — always inside `walkable`.
    private(set) var span: Range<Int>
    /// The first visible slot's global index.
    private(set) var firstVisible: Int

    init(walkable: Range<Int>, rangeHours: Range<Int>?, visibleSlots: Int) {
        self.walkable = walkable
        let range = rangeHours
            .map { $0.clamped(to: walkable) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.rangeHours = range
        self.visibleSlots = Swift.max(1, Swift.min(visibleSlots, walkable.count))
        let opening = range ?? (walkable.lowerBound ..< walkable.lowerBound + 1)
        span = opening
        firstVisible = walkable.lowerBound
        firstVisible = openingFirst
    }

    // MARK: The tunable slot count

    /// How many pills the row shows: the Range plus two (one slot of
    /// lookback, one of lookahead), at least 4, and never so many that a pill
    /// would be narrower than `minPill`. Owner-tunable on the simulator.
    static func visibleSlotCount(rangeLength: Int,
                                 availableWidth: Double,
                                 minPill: Double = 22,
                                 gap: Double = 3) -> Int {
        let wanted = Swift.max(rangeLength + 2, 4)
        guard availableWidth > 0 else { return wanted }
        let fitting = Int(((availableWidth + gap) / (minPill + gap)).rounded(.down))
        return Swift.max(1, Swift.min(wanted, fitting))
    }

    // MARK: State

    /// The visible slots as global indices.
    var visible: Range<Int> { firstVisible ..< firstVisible + visibleSlots }

    var canStepBack: Bool { span.lowerBound > walkable.lowerBound }
    var canStepForward: Bool { span.upperBound < walkable.upperBound }

    /// The span sits exactly on the rated Range. False with no Range today.
    var isAtRange: Bool { rangeHours == span }

    /// The return control shows only when there is a Range to go back to.
    var canReturnToRange: Bool { rangeHours != nil && !isAtRange }

    /// The span shares at least one hour with the Range — metric values are
    /// coloured; fully outside it they render uncoloured (nothing is judged).
    var overlapsRange: Bool { rangeHours?.overlaps(span) ?? false }

    // MARK: Moves

    mutating func stepForward() {
        guard canStepForward else { return }
        span = span.lowerBound + 1 ..< span.upperBound + 1
        if anchorsOnSpan {
            firstVisible = clampedFirst(span.lowerBound)
        } else {
            // The span's last hour (upperBound − 1) stays on the
            // second-to-last slot (firstVisible + visibleSlots − 2) or
            // earlier — moving at most one slot per step.
            let wanted = Swift.max(firstVisible, span.upperBound + 1 - visibleSlots)
            firstVisible = clampedFirst(Swift.min(wanted, firstVisible + 1))
        }
    }

    mutating func stepBack() {
        guard canStepBack else { return }
        span = span.lowerBound - 1 ..< span.upperBound - 1
        if anchorsOnSpan {
            firstVisible = clampedFirst(span.lowerBound)
        } else {
            // The span's first hour stays on the second slot or later —
            // moving at most one slot per step.
            let wanted = Swift.min(firstVisible, span.lowerBound - 1)
            firstVisible = clampedFirst(Swift.max(wanted, firstVisible - 1))
        }
    }

    /// Steps by `delta` whole hours (negative = back) — the swipe path.
    mutating func step(by delta: Int) {
        if delta > 0 { for _ in 0..<delta { stepForward() } }
        if delta < 0 { for _ in 0..<(-delta) { stepBack() } }
    }

    /// Back to the rated Range with the window as at first open. A no-op
    /// without a Range.
    mutating func returnToRange() {
        guard let rangeHours else { return }
        span = rangeHours
        firstVisible = openingFirst
    }

    // MARK: Private

    private var anchorsOnSpan: Bool { span.count >= visibleSlots }

    /// At rest: one earlier slot left of the span (clamped to the day); an
    /// anchored (over-long) span opens on its own first hour.
    private var openingFirst: Int {
        clampedFirst(anchorsOnSpan ? span.lowerBound : span.lowerBound - 1)
    }

    private func clampedFirst(_ proposed: Int) -> Int {
        let upper = Swift.max(walkable.lowerBound, walkable.upperBound - visibleSlots)
        return Swift.min(Swift.max(proposed, walkable.lowerBound), upper)
    }
}
