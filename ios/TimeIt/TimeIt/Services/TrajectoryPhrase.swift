import Foundation

/// Spec 14 §5: the trajectory phrase behind the Settings phrases toggle.
/// The phrase is keyed on (first hour tier, last hour tier) — 9 cases; if any
/// interior hour falls outside the CLOSED tier span between first and last
/// (e.g. green→green with an orange dip), it overrides to "Mixed conditions".
/// Ten strings, one rule — the phrase can never contradict the gradient.
///
/// ⚠️ PROVISIONAL copy (feasibility I3): only "Good, turning perfect" and
/// "Mixed conditions" are spec-pinned; the other eight strings await the
/// owner's design-pass review. Cheap to change — they live only here.
enum TrajectoryPhrase {

    static func phrase(for tiers: [HourTier]) -> String? {
        guard let first = tiers.first, let last = tiers.last else { return nil }

        let span = min(first, last)...max(first, last)
        let interiorEscapes = tiers.dropFirst().dropLast().contains { !span.contains($0) }
        if interiorEscapes { return "Mixed conditions" }

        switch (first, last) {
        case (.red, .red): return "Nothing in your range" // the §2 all-bad copy — only ever renders all-red
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

    /// §5 accessibility force: when the system's Differentiate Without Color
    /// is on, phrases are enabled regardless of the Settings preference —
    /// color is never the only carrier of quality.
    static func phrasesEnabled(preference: Bool, differentiateWithoutColor: Bool) -> Bool {
        preference || differentiateWithoutColor
    }
}
