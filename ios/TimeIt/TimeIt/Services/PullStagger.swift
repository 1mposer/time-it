import CoreGraphics

/// The dashboard's pull-down stagger (depth & polish pass, build 8 — owner
/// ask 2026-11-03: "when someone pulls the screen down, the gaps in between
/// the cards get larger … the last one moves faster than the first"). Pure,
/// so the view only feeds it the live top overscroll.
///
/// While the list is pulled `overscroll` points past its top, the child at
/// visual position `index` (0 = topmost) is pushed down by an EXTRA
///
///     rubberBand(overscroll) × (index + 1) × k
///
/// on top of the scroll view's own overscroll, so every gap grows by the same
/// `rubberBand × k` and the bottom child travels furthest. The rubber band is
/// UIKit's touch curve (c = 0.55, ceiling = the viewport height — the
/// fluid-interfaces REFERENCE.md formula), so the extra is bounded however
/// hard the pull. No animation of its own: it tracks the scroll view's
/// offset 1:1, including the scroll's own spring back on release.
enum PullStagger {
    /// Owner-tunable. At k = 0.8 the fifth card's TOTAL travel (scroll
    /// overscroll + its extra) is ~2.1–2.2× the first's across typical pulls
    /// (pinned in `PullStaggerTests`).
    static let k: CGFloat = 0.6
    /// UIKit's touch rubber-band coefficient.
    static let touchCoefficient: CGFloat = 0.55

    /// `c·x·d / (d + c·x)` — hyperbolic, never exceeds `d`.
    static func rubberBand(_ x: CGFloat, dimension d: CGFloat, c: CGFloat = touchCoefficient) -> CGFloat {
        guard d > 0 else { return 0 }
        let sign: CGFloat = x < 0 ? -1 : 1
        let a = abs(x)
        return sign * (c * a * d) / (d + c * a)
    }

    /// The extra downward offset for the child at `index`. Zero when the
    /// list is not overscrolled (or scrolled normally, `overscroll ≤ 0`).
    static func offset(overscroll: CGFloat, index: Int, viewport: CGFloat, k: CGFloat = k) -> CGFloat {
        guard overscroll > 0, index >= 0 else { return 0 }
        return rubberBand(overscroll, dimension: viewport) * CGFloat(index + 1) * k
    }
}
