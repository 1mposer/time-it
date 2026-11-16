import SwiftUI

/// The day score's colour band (owner ruling 02 a, 2026-11-15): the ring's
/// arc and numeral follow the SCORE, not the verdict — ≥70 green, 40–69
/// orange, <40 red, nil the empty ring's grey. Display only — the score
/// never feeds a verdict (ADR-0011 independence).
enum ScoreBand: Equatable {
    case high, middle, low, empty

    init(score: Int?) {
        switch score {
        case .none: self = .empty
        case .some(let value) where value >= 70: self = .high
        case .some(let value) where value >= 40: self = .middle
        default: self = .low
        }
    }
}

extension Theme {
    static func scoreBandTint(_ score: Int?) -> Color {
        switch ScoreBand(score: score) {
        case .high: return perfectGreen
        case .middle: return ratingGood
        case .low: return badRed
        case .empty: return timelineTrack
        }
    }
}
