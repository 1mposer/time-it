import SwiftUI

// MARK: - Coming days (the tomorrow detail's list)

enum ComingDays {
    struct Row: Equatable, Identifiable {
        let dayIndex: Int
        /// "Thu"
        let dayName: String
        let tier: WeekDotTier
        let line: VerdictLine
        /// "Average 48"; nil when the day has no hours (no score).
        let average: String?

        var id: Int { dayIndex }
    }

    /// The days after `shown`, up to the week-dot horizon (seven days).
    static func rows(for activity: ActivityRating, after shown: Int, deriver: TimeDeriver,
                     horizon: Int = 7) -> [Row] {
        activity.days
            .filter { $0.dayIndex > shown && $0.dayIndex < horizon }
            .sorted { $0.dayIndex < $1.dayIndex }
            .map { day in
                Row(dayIndex: day.dayIndex,
                    dayName: deriver.shortWeekday(forDayIndex: day.dayIndex),
                    tier: WeekDots.tier(for: day),
                    line: VerdictLine(day: day, deriver: deriver),
                    average: day.score.map { "Average \($0)" })
            }
    }
}

// MARK: - Explore rows

enum ExploreRows {
    enum Kind: Equatable { case yourHours, bestHours, lookingAt }

    struct Row: Equatable, Identifiable {
        let kind: Kind
        let label: String
        let value: String
        let result: String
        /// The result's tint source: a verdict (Best hours) or nil (plain text).
        let resultRating: Rating?
        /// Best hours' result is a verdict word, the others an average.
        let resultIsVerdict: Bool
        let isHighlighted: Bool

        var id: String { label }
    }

    struct LookingAt: Equatable {
        let span: String
        /// nil while the server's span score is in flight or failed.
        let score: Int?
    }

    static func average(_ score: Int?) -> String {
        "Average \(score.map(String.init) ?? "\u{2014}")"
    }

    static func rows(range: String, dayScore: Int?, best: VerdictLine, lookingAt: LookingAt?) -> [Row] {
        var rows = [
            Row(kind: .yourHours, label: "Your hours", value: range, result: average(dayScore),
                resultRating: nil, resultIsVerdict: false, isHighlighted: lookingAt == nil),
            Row(kind: .bestHours, label: "Best hours", value: best.window ?? "\u{2014}",
                result: best.verdict ?? VerdictLine.noGoodTime, resultRating: best.rating,
                resultIsVerdict: true, isHighlighted: false),
        ]
        if let lookingAt {
            rows.append(Row(kind: .lookingAt, label: "Looking at", value: lookingAt.span,
                            result: average(lookingAt.score), resultRating: nil,
                            resultIsVerdict: false, isHighlighted: true))
        }
        return rows
    }

    static func backLabel(range: String) -> String { "Back to \(range)" }
}
