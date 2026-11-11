import SwiftUI

/// The new Activity's card as the dashboard will draw it, computed for the
/// wizard's Review step (`DashboardViewModel.reviewPreview(for:)`).
struct ReviewPreview {
    let rating: ActivityRating
    let day: Day?
    let tiers: [HourTier?]
    let stripStartLocalHour: Int?
    let weekDots: [WeekDot]
}

/// The Review step (owner ruling 2026-11-11, item 5; Figma `A/R3` frames
/// `876:15364` light / `876:15455` dark / `876:15546` Reduce Motion /
/// `876:15637` start): the Activity revealed centred as the user's first
/// achievement — a title, the REAL dashboard ring card (the same view, the
/// computed score and colours; the empty ring only until the forecast
/// answers), one line under it. No decoration around the card. The card
/// springs in from 60% / 40% opacity with a success haptic as it settles;
/// Reduce Motion crossfades instead.
struct ReviewRevealView: View {
    let title: String?
    let draftRating: ActivityRating
    let iconSymbol: String
    let rangeChipLabel: String
    /// The draft Range's hour count — the empty card's grey strip.
    let rangeHourCount: Int
    let stripStartLocalHour: Int
    let preview: ReviewPreview?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var settled = 0

    static let startScale: CGFloat = 0.6
    static let startOpacity: Double = 0.4
    static let reveal = Animation.spring(duration: 0.6, bounce: 0.3)
    static let revealReduced = Animation.easeInOut(duration: 0.2)
    /// Title baseline → card top (frame: 32pt).
    static let titleToCard: CGFloat = 32

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Text(title)
                    .scaledFont(size: 28, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    .opacity(revealed ? 1 : 0)
                    .padding(.bottom, Self.titleToCard)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("editor.reviewTitle")
            }
            card
                .scaleEffect(revealed || reduceMotion ? 1 : Self.startScale)
                .opacity(revealed ? 1 : (reduceMotion ? 0 : Self.startOpacity))
                .accessibilityIdentifier("editor.reviewCard")
            Text("\(draftRating.label) is on your dashboard.")
                .scaledFont(size: 15)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 16)
                .opacity(revealed ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.success, trigger: settled)
        .onAppear {
            withAnimation(reduceMotion ? Self.revealReduced : Self.reveal) {
                revealed = true
            } completion: {
                settled += 1
            }
        }
    }

    private var card: some View {
        // The draft names the card; the server reply only lends its days
        // (score, verdict) — so the card can never show another label.
        ScoreRingCardView(activity: ActivityRating(activityId: draftRating.activityId,
                                                   label: draftRating.label,
                                                   displayMetrics: draftRating.displayMetrics,
                                                   days: preview?.rating.days ?? []),
                          day: preview?.day,
                          iconSymbol: iconSymbol,
                          rangeChipLabel: rangeChipLabel,
                          tiers: preview?.tiers ?? Array(repeating: nil, count: rangeHourCount),
                          stripStartLocalHour: preview?.stripStartLocalHour ?? stripStartLocalHour,
                          weekDots: preview?.weekDots ?? [],
                          showsWeekDots: true)
            // The dashboard overlays its chevron on the card; the replica
            // draws the same glyph at the same spot (static here).
            .overlay(alignment: .topTrailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .padding(.top, 4)
                    .padding(.trailing, 4.5)
                    .accessibilityHidden(true)
            }
            .allowsHitTesting(false)
    }
}
