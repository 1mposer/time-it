import Foundation

/// The trajectory phrase behind the Settings phrases toggle, keyed on
/// (first hour tier, last hour tier) — 9 cases; if any interior hour falls
/// outside the CLOSED span between first and last (e.g. green→green with an
/// orange dip), it overrides to "Mixed conditions". Ten strings, one rule —
/// the phrase can never contradict the gradient.
///
/// ⚠️ PROVISIONAL copy: only "Good, turning perfect" and "Mixed conditions"
/// are pinned; the other eight strings await design review. Cheap to
/// change — they live only here.
enum TrajectoryPhrase {

    static func phrase(for tiers: [HourTier]) -> String? {
        guard let first = tiers.first, let last = tiers.last else { return nil }

        let span = min(first, last)...max(first, last)
        let interiorEscapes = tiers.dropFirst().dropLast().contains { !span.contains($0) }
        if interiorEscapes { return "Mixed conditions" }

        switch (first, last) {
        case (.red, .red): return "Nothing in your range" // all-bad copy — only ever renders all-red
        case (.red, .orange): return "Bad, turning good"
        case (.red, .green): return "Bad, turning perfect"
        case (.orange, .red): return "Good, turning bad"
        case (.orange, .orange): return "Good throughout"
        case (.orange, .green): return "Good, turning perfect"
        case (.green, .red): return "Perfect, turning bad"
        case (.green, .orange): return "Perfect, turning good"
        case (.green, .green): return "Perfect throughout"
        }
    }

    /// Accessibility force: when Differentiate Without Color is on, phrases
    /// are enabled regardless of the Settings preference — color is never
    /// the only carrier of quality.
    static func phrasesEnabled(preference: Bool, differentiateWithoutColor: Bool) -> Bool {
        preference || differentiateWithoutColor
    }

    /// The card's phrase slot — every phrase is gated by the toggle (owner
    /// ruling 2026-09-01: on an unrated day the red slice alone carries the
    /// verdict; Differentiate Without Color force-enables the words so color
    /// is never the only carrier). An UNRATED day (server `rating: null`)
    /// reads "Nothing in your range." — the server's day rating is truth
    /// over the mirror's tiers. nil hides the slot.
    static func cardPhrase(dayRated: Bool, tiers: [HourTier], phrasesEnabled: Bool) -> String? {
        guard phrasesEnabled else { return nil }
        guard dayRated else { return "Nothing in your range." }
        return phrase(for: tiers)
    }
}
