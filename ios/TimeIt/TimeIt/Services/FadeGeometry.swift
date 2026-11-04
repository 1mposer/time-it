import CoreGraphics
import Foundation

/// The dashboard band melt's geometry, from the first list item's top edge
/// (in the full-screen space the melt is drawn in — status bar included).
/// Pure, so the Figma stops are pinned by hand in `FadeGeometryTests`.
struct FadeGeometry: Equatable {
    struct MaskStop: Equatable {
        /// 0…1 down the group.
        let location: CGFloat
        let opacity: Double
    }

    /// The first list item's top; never negative.
    let firstCardTop: CGFloat
    let endBelowFirstCard: CGFloat

    init(firstCardTop: CGFloat, endBelowFirstCard: CGFloat = Theme.Fade.endBelowFirstCard) {
        self.firstCardTop = max(0, firstCardTop)
        self.endBelowFirstCard = max(1, endBelowFirstCard)
    }

    /// The masked group runs from the screen top to the melt's end.
    var groupHeight: CGFloat { firstCardTop + endBelowFirstCard }

    /// Full strength from the top to the first card, then the Figma curve.
    /// The offsets scale with `endBelowFirstCard`, so moving the end keeps
    /// the curve's shape.
    var maskStops: [MaskStop] {
        let h = groupHeight
        let scale = endBelowFirstCard / Theme.Fade.referenceSpan
        let melt = Theme.Fade.maskOffsets.map { stop in
            MaskStop(location: (firstCardTop + stop.offset * scale) / h, opacity: stop.opacity)
        }
        return [MaskStop(location: 0, opacity: 1)] + melt
    }

    /// The glow blob at drift keyframe A, in the group's space.
    func blobRect(dark: Bool) -> CGRect {
        let size = dark ? Theme.Fade.blobSizeDark : Theme.Fade.blobSizeLight
        return CGRect(x: Theme.Fade.blobOrigin.x,
                      y: firstCardTop + Theme.Fade.blobOrigin.y,
                      width: size.width,
                      height: size.height)
    }

    /// The blob's offset from keyframe A at `time` seconds: A→B→A ping-pong,
    /// one `driftLeg` per direction, cosine ease-in-out (slow at each
    /// keyframe). Zero under Reduce Motion — the blob holds still at A.
    static func driftOffset(at time: TimeInterval,
                            reduceMotion: Bool,
                            leg: TimeInterval = Theme.Fade.driftLeg,
                            delta: CGSize = Theme.Fade.driftDelta) -> CGSize {
        guard !reduceMotion, leg > 0 else { return .zero }
        // Phase over one full cycle (2 legs): 0 at A, π at B, 2π at A.
        let phase = time.truncatingRemainder(dividingBy: 2 * leg) / leg * .pi
        let progress = (1 - cos(phase)) / 2
        return CGSize(width: delta.width * progress, height: delta.height * progress)
    }
}
