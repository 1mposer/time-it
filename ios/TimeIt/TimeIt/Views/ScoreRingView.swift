import SwiftUI

/// The day-score ring — Figma "Score ring" (card v2 `458:394`, detail v3 hero
/// `464:2301`). A full track circle with an arc whose sweep is `score`/100,
/// drawn clockwise from 12 o'clock with butt caps, and the numeral inside in
/// the day's rating-tier colour.
///
/// `score == nil` renders the track alone: no arc and NO numeral — a score the
/// server did not send is never fabricated (ADR-0011 null rule).
struct ScoreRingView: View {
    /// The wire's `days[].score`; nil → empty ring.
    let score: Int?
    /// Rating-tier colour for the arc and the numeral.
    let tint: Color
    let style: Style

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The two drawn sizes. Measured off the exported ring SVGs: the 48pt
    /// ring is a 5pt stroke (outer r24 / inner r19), the 64pt hero ring a 6pt
    /// stroke (outer r32 / inner r26).
    enum Style {
        case card
        case hero

        var diameter: CGFloat { self == .card ? 48 : 64 }
        var lineWidth: CGFloat { self == .card ? 5 : 6 }
        var numeralSize: CGFloat { self == .card ? 15 : 22 }
        var numeralTracking: CGFloat { self == .card ? -0.3 : -0.4 }
    }

    private var fraction: Double {
        guard let score else { return 0 }
        return Swift.min(Swift.max(Double(score) / 100, 0), 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.timelineTrack, lineWidth: style.lineWidth)
            if score != nil {
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: style.lineWidth, lineCap: .butt))
                    // SwiftUI trims from 3 o'clock; the frame starts at 12.
                    .rotationEffect(.degrees(-90))
                Text("\(score ?? 0)")
                    .font(.system(size: style.numeralSize, weight: .semibold))
                    .tracking(style.numeralTracking)
                    .foregroundStyle(tint)
            }
        }
        .frame(width: style.diameter, height: style.diameter)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: score)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Score rings") {
    VStack(spacing: 24) {
        HStack(spacing: 24) {
            ScoreRingView(score: 86, tint: Theme.perfectGreen, style: .card)
            ScoreRingView(score: 31, tint: Theme.badRed, style: .card)
            ScoreRingView(score: nil, tint: Theme.secondaryText, style: .card)
        }
        HStack(spacing: 24) {
            ScoreRingView(score: 86, tint: Theme.perfectGreen, style: .hero)
            ScoreRingView(score: 54, tint: Theme.accentOrange, style: .hero)
            ScoreRingView(score: nil, tint: Theme.secondaryText, style: .hero)
        }
    }
    .padding(40)
    .background(Theme.cardBackground)
}
#endif
