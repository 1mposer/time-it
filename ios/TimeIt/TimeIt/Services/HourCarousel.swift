import Foundation

/// The Activity Detail hero carousel — pure span ↔ scroll-position math over
/// GLOBAL `hours[]` indices (depth & polish pass, build 8; owner rulings
/// 2026-10-31 / 2026-11-01 / 2026-11-03, FIGMA.md §12).
///
/// The row is a native horizontal `ScrollView` of pill SLOTS that snaps by
/// pill pitch. The chosen span is the run of pills under a FIXED highlight
/// window: `leadSlots` slots in from the viewport's leading edge, the Range's
/// length long. So the scroll position (the leading visible slot's id) is
/// the one piece of state, and the span derives from it:
///
///     span.lowerBound = clamp(anchor + leadSlots, walkable.lowerBound,
///                             walkable.upperBound − L)
///
/// - `visibleSlots` = Range + 2 (one slot of lookback, one of lookahead),
///   floor 4, capped so no pill is narrower than 22pt (`visibleSlotCount`).
/// - The leading pad: ONE blank slot before the day's first walkable hour,
///   so the span can reach the walk start while keeping its one-slot
///   lookback position (it shows as an empty slot there). Zero pads when the
///   span cannot fit in the viewport beside a lookback slot (`V ≤ L`).
/// - The trailing pad: `max(0, V − lead − L)` blank slots after the last
///   walkable hour, so the furthest snap is exactly the span-at-walk-end
///   position (the highlight never rests misaligned).
/// - When `V ≤ L` (a long Range under the pill floor) the span is wider
///   than the viewport: the anchor is the span's first hour, the span runs
///   off the trailing edge, and the last `L − V` scroll positions all clamp
///   to the span at the walk end.
/// - With no Range hours on the shown day the span is ONE hour, opening at
///   the first walkable hour, and there is no Range to return to.
struct HourCarousel: Equatable {
    /// Every hour the row may show, as global `hours[]` indices. Non-empty.
    let walkable: Range<Int>
    /// The rated Range hours within the shown bucket; nil when none.
    let rangeHours: Range<Int>?
    /// The number of pill slots visible at once (≥ 1).
    let visibleSlots: Int
    /// The chosen span — always inside `walkable`.
    private(set) var span: Range<Int>

    init(walkable: Range<Int>, rangeHours: Range<Int>?, visibleSlots: Int) {
        self.walkable = walkable
        let range = rangeHours
            .map { $0.clamped(to: walkable) }
            .flatMap { $0.isEmpty ? nil : $0 }
        self.rangeHours = range
        self.visibleSlots = Swift.max(1, visibleSlots)
        span = range ?? (walkable.lowerBound ..< walkable.lowerBound + 1)
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

    // MARK: Slots ↔ scroll position

    /// Blank slots before the first walkable hour: one (the lookback slot)
    /// when the span fits beside it, else none.
    var leadSlots: Int { visibleSlots > span.count ? 1 : 0 }

    /// Blank slots after the last walkable hour — enough that the furthest
    /// snap puts the span exactly on the walk end.
    var trailSlots: Int { Swift.max(0, visibleSlots - leadSlots - span.count) }

    /// Every slot id the row lays out, pads included. A slot whose id is not
    /// in `walkable` is a blank pad.
    var slotIDs: Range<Int> { walkable.lowerBound - leadSlots ..< walkable.upperBound + trailSlots }

    /// The leading visible slot's id that puts the highlight on the span.
    var scrollAnchor: Int { span.lowerBound - leadSlots }

    /// The visible slots as ids (pads included).
    var visible: Range<Int> { scrollAnchor ..< scrollAnchor + visibleSlots }

    /// The span the highlight covers when the row rests on `anchor` (any
    /// slot id; out-of-range anchors clamp to the walk ends).
    func span(forScrollAnchor anchor: Int) -> Range<Int> {
        let length = span.count
        let lower = Swift.min(Swift.max(anchor + leadSlots, walkable.lowerBound),
                              walkable.upperBound - length)
        return lower ..< lower + length
    }

    /// Moves the span to where the row rests on `anchor`.
    mutating func settle(onScrollAnchor anchor: Int) {
        span = span(forScrollAnchor: anchor)
    }

    // MARK: State

    var canStepBack: Bool { span.lowerBound > walkable.lowerBound }
    var canStepForward: Bool { span.upperBound < walkable.upperBound }

    /// The span sits exactly on the rated Range. False with no Range today.
    var isAtRange: Bool { rangeHours == span }

    /// The ring's return affordance is live only when there is a Range to go
    /// back to.
    var canReturnToRange: Bool { rangeHours != nil && !isAtRange }

    /// The span shares at least one hour with the Range — metric values are
    /// coloured; fully outside it they render uncoloured (nothing is judged).
    var overlapsRange: Bool { rangeHours?.overlaps(span) ?? false }

    // MARK: Moves

    mutating func stepForward() { step(by: 1) }
    mutating func stepBack() { step(by: -1) }

    /// Slides the whole span by `delta` whole hours (negative = back),
    /// clamped to the walk.
    mutating func step(by delta: Int) {
        let length = span.count
        let lower = Swift.min(Swift.max(span.lowerBound + delta, walkable.lowerBound),
                              walkable.upperBound - length)
        span = lower ..< lower + length
    }

    /// Back to the rated Range. A no-op without a Range.
    mutating func returnToRange() {
        guard let rangeHours else { return }
        span = rangeHours
    }
}
