import Foundation

/// The card v2 hour strip's boundary numerals — one per hour BOUNDARY of the
/// Range-scoped strip (an n-hour strip has n+1 boundaries), in the frame's
/// bare 12-hour style: "6", "7" … "10" with no meridiem suffix (`458:394`).
///
/// Pure, so the thinning rule is pinned by a test rather than discovered on a
/// long Range: the frame's 3–4 hour strips print every boundary, and a long
/// Range would otherwise collide its numerals.
enum RangeStripAxis {

    /// At most this many numerals are drawn; longer strips print every
    /// `stride`-th boundary instead (the ends always survive).
    static let maxLabels = 12

    /// Bare 12-hour numeral for a 0...23 local hour — 0 and 12 both read "12".
    static func numeral(_ localHour: Int) -> String {
        let wrapped = ((localHour % 24) + 24) % 24 % 12
        return "\(wrapped == 0 ? 12 : wrapped)"
    }

    /// Which boundary ordinals (0...hourCount) carry a numeral. Always
    /// includes the first and the last; interior ones thin out evenly once
    /// the strip is longer than `maxLabels` boundaries.
    static func visibleBoundaries(hourCount: Int, maxLabels: Int = maxLabels) -> [Int] {
        guard hourCount > 0 else { return [] }
        let boundaries = hourCount + 1
        let stride = Swift.max(1, Int((Double(boundaries) / Double(Swift.max(2, maxLabels))).rounded(.up)))
        var result = Swift.stride(from: 0, through: hourCount, by: stride).map { $0 }
        if result.last != hourCount {
            // The end always prints; an interior numeral closer to it than
            // the stride gives way so the two never crowd (note 36).
            if result.count > 1, let last = result.last, hourCount - last < stride {
                result.removeLast()
            }
            result.append(hourCount)
        }
        return result
    }

    /// The gap kept between two numerals.
    static let labelGap: CGFloat = 6

    /// How many numerals a strip of `width` holds when each is about
    /// `labelWidth` wide — at least the two ends, at most `maxLabels`. At
    /// large text sizes this thins the frame's every-hour axis (note 36).
    static func maxLabels(fittingWidth width: CGFloat, labelWidth: CGFloat) -> Int {
        let fits = Int((width + labelGap) / (labelWidth + labelGap))
        return Swift.min(maxLabels, Swift.max(2, fits))
    }

    /// The drawn numerals as `(boundary ordinal, text)` for a strip of
    /// `hourCount` hours whose first hour is local hour `startLocalHour`.
    static func labels(startLocalHour: Int, hourCount: Int,
                       maxLabels: Int = maxLabels) -> [(boundary: Int, text: String)] {
        visibleBoundaries(hourCount: hourCount, maxLabels: maxLabels).map {
            (boundary: $0, text: numeral(startLocalHour + $0))
        }
    }
}
