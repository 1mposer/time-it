import Foundation

/// A week dot's colour class — the day's verdict, or no data.
enum WeekDotTier: Equatable {
    case perfect
    case good
    /// A day with hours but no qualifying Window (rating null, or a verdict
    /// this build doesn't understand — never favourable on `.unknown`).
    case bad
    /// No hours to judge: the day is absent from `days[]` (a nocturnal
    /// activity has one fewer bucket) or its `score` is nil (the zero-hour
    /// bucket, ADR-0011 null rule) on a non-qualifying verdict.
    case noData
}

/// One cell of the week-dot row (Figma component `517:73` "Week Dots").
struct WeekDot: Equatable {
    let dayIndex: Int
    /// Weekday initial in the forecast's zone ("S", "M", …).
    let letter: String
    /// Spoken day name — "Today", "Tomorrow", then the weekday.
    let name: String
    let tier: WeekDotTier

    /// A no-data day has nothing to show, so it is not a jump target.
    var isJumpable: Bool { tier != .noData }

    /// "<Day>, <Perfect|Good|No window|No data>".
    var accessibilityLabel: String {
        let verdict: String
        switch tier {
        case .perfect: verdict = "Perfect"
        case .good: verdict = "Good"
        case .bad: verdict = "No window"
        case .noData: verdict = "No data"
        }
        return "\(name), \(verdict)"
    }
}

/// The week-dot row's pure model — "the one way to show days" (owner ruling
/// 2026-10-02). Seven dots in FORECAST order from today (dayIndex 0..6),
/// never Monday-first; an 8th diurnal bucket is dropped, a missing 7th
/// nocturnal bucket is a no-data dot.
enum WeekDots {
    /// `nocturnal` names the spoken day by its evening ("Tonight",
    /// "Tomorrow night", "<Weekday> night") — a wrapped Range keys dayIndex
    /// to the evening (ADR-0004 amendment).
    static func dots(for activity: ActivityRating,
                     deriver: TimeDeriver,
                     nocturnal: Bool = false,
                     count: Int = 7) -> [WeekDot] {
        (0..<count).map { dayIndex in
            let day = activity.days.first { $0.dayIndex == dayIndex }
            return WeekDot(dayIndex: dayIndex,
                           letter: deriver.weekdayLetter(forDayIndex: dayIndex),
                           name: deriver.dayName(forDayIndex: dayIndex, nocturnal: nocturnal),
                           tier: tier(for: day))
        }
    }

    /// The verdict wins: Perfect/Good map straight through (a rated day
    /// always has hours on the wire — a nil score beside it can only be the
    /// decoder dropping an out-of-contract number, and the verdict stays
    /// real). Otherwise a nil score means no hours → no data; a real score
    /// means a judged day without a Window → bad.
    static func tier(for day: Day?) -> WeekDotTier {
        guard let day else { return .noData }
        switch day.rating {
        case .perfect: return .perfect
        case .good: return .good
        case .unknown, .none: return day.score == nil ? .noData : .bad
        }
    }
}
