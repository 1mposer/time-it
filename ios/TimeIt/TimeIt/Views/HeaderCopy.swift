import Foundation

/// The dashboard header's strings (FIGMA.md §12 ruling 7 — the temperature
/// is the big numeral, the clock leads the meta line). Pure, so the
/// composition is pinned by HeaderCopyTests without a view.
enum HeaderCopy {
    /// One item of the meta line. Figma draws no separator glyph between
    /// them: the clock is bare text, wind and humidity each carry an icon.
    enum MetaSegment: Equatable, Hashable {
        case clock(String)
        case wind(String)
        case humidity(String)
    }

    /// The big numeral — the rounded temperature with its unit, "28°C"
    /// (fresh-eyes row 18a, owner 2026-11-12, as the approved onboarding
    /// dashboard frame draws it); "—°" with no reading.
    static func numeral(temp: Double?) -> String {
        guard let temp else { return "—°" }
        return "\(Int(temp.rounded()))°C"
    }

    /// Clock, wind, humidity in that order; a missing metric drops its
    /// segment (no placeholder), the clock always stays.
    static func metaSegments(clock: String,
                             windKmh: Double?,
                             humidity: Double?,
                             windUnit: WindSpeedUnit) -> [MetaSegment] {
        var segments: [MetaSegment] = [.clock(clock)]
        if let windKmh {
            segments.append(.wind("\(Int(windUnit.fromKmh(windKmh).rounded())) \(windUnit.label)"))
        }
        if let humidity {
            segments.append(.humidity("\(Int(humidity.rounded()))%"))
        }
        return segments
    }
}
