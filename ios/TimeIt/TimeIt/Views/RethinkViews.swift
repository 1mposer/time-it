import SwiftUI

// MARK: - The card's glass overlay (frame 5 `921:20600`)

/// Covers ONE card once today's hours are over: "Your chosen hours of 6 –
/// 10am have passed, you are seeing tomorrow's score." + "Tap to dismiss".
/// A tap dismisses it for the rest of that local day (per Activity) with a
/// light haptic. The card under it is blurred, so the overlay reads as glass.
struct PassedCardOverlay: View {
    let rangeLabel: String
    let activityId: String
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var tick = 0

    private typealias Layout = RethinkLayout.Overlay

    var body: some View {
        let shape = RethinkLayout.shape()
        Button {
            tick += 1
            onDismiss()
        } label: {
            VStack(spacing: Layout.copyToHint) {
                Text(HoursOverCopy.overlay(rangeLabel: rangeLabel))
                    .scaledFont(size: Layout.copyFont, weight: .semibold)
                    .lineSpacing(Layout.copyLineSpacing)
                    .foregroundStyle(Theme.primaryText)
                    .multilineTextAlignment(.center)
                    // The overlay is the card's size: at the largest text
                    // sizes the copy shrinks to fit rather than clip.
                    .minimumScaleFactor(Layout.minimumScale)
                Text(HoursOverCopy.overlayHint)
                    .scaledFont(size: Layout.hintFont, weight: .medium)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(Layout.minimumScale)
            }
            .dynamicTypeSize(...Layout.typeCap)
            .padding(RethinkLayout.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The frame's two tints over the card, which the dashboard
            // blurs beneath (Figma backdrop blur 20 = a 10pt Gaussian).
            .background {
                ZStack {
                    shape.fill(colorScheme == .dark ? Layout.darkFill : Layout.lightFill)
                    shape.fill(Layout.greyWash)
                }
            }
            .overlay(shape.strokeBorder(colorScheme == .dark ? Layout.darkRim : Layout.lightRim,
                                        lineWidth: Layout.rimWidth))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(HoursOverCopy.overlay(rangeLabel: rangeLabel))
        .accessibilityHint("Dismisses")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("card.overlay.\(activityId)")
    }
}

// MARK: - The hours-over row (frames 3 / 3b)

/// "Today's hours are over" + "Best was 7 – 10am · Perfect" on top of the
/// tomorrow detail. Tap → light haptic → green outline + filled check
/// (0.2 s) → the row slides off to the right while the content rises
/// (0.3 s spring); Reduce Motion: a cross-fade.
struct HoursOverRow: View {
    let morning: MorningResult?
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var tick = 0

    private typealias Layout = RethinkLayout.HoursOver

    var body: some View {
        let shape = RethinkLayout.shape()
        Button(action: tap) {
            HStack(spacing: Layout.glyphToText) {
                Image(systemName: pressed ? "checkmark.circle.fill" : "checkmark.circle")
                    .font(.system(size: Layout.glyphSize, weight: .regular))
                    .foregroundStyle(pressed ? Theme.perfectGreen : Theme.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Layout.titleToSubtitle) {
                    Text(HoursOverCopy.title)
                        .scaledFont(size: Layout.titleFont, weight: .medium)
                        .tracking(-0.1)
                        .foregroundStyle(Theme.primaryText)
                    if let best = HoursOverCopy.bestWas(morning) {
                        (Text(best.lead).foregroundColor(Theme.secondaryText)
                         + Text(best.verdict).foregroundColor(Theme.ratingTint(best.rating)))
                            .scaledFont(size: Layout.subtitleFont)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(RethinkLayout.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.detailContainer, in: shape)
            .overlay(shape.strokeBorder(Theme.perfectGreen, lineWidth: Layout.pressedBorder)
                .opacity(pressed ? 1 : 0))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .cardLift(cornerRadius: RethinkLayout.outerRadius)
        .disabled(pressed)
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Dismisses")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("detail.hoursOver")
    }

    private var accessibilityLabel: String {
        guard let best = HoursOverCopy.bestWas(morning) else { return HoursOverCopy.title }
        return "\(HoursOverCopy.title). \(best.lead)\(best.verdict)"
    }

    private func tap() {
        tick += 1
        withAnimation(.easeOut(duration: Layout.pressDuration)) { pressed = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Layout.pressDuration))
            onDismiss()
        }
    }

    /// Off to the right (and collapsing) on removal; a fade under Reduce Motion.
    static func removal(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(insertion: .opacity,
                                              removal: .move(edge: .trailing).combined(with: .opacity))
    }

    static func removalAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: Layout.slideDuration)
    }
}

// MARK: - Coming days (frame 7 `921:21142`)

struct ComingDaysCard: View {
    let rows: [ComingDays.Row]

    private typealias Layout = RethinkLayout.ComingDays
    @ScaledMetric(relativeTo: .subheadline) private var rowHeight = Layout.rowHeight
    @ScaledMetric(relativeTo: .subheadline) private var nameColumn = Layout.nameColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Coming days")
                .scaledFont(size: Layout.titleFont, weight: .medium)
                .foregroundStyle(Theme.secondaryText)
                .padding(.bottom, Layout.titleToRows)
                .accessibilityAddTraits(.isHeader)
            ForEach(rows) { row in
                rowView(row)
            }
        }
        .padding(RethinkLayout.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.detailContainer, in: RethinkLayout.shape())
        .cardLift(cornerRadius: RethinkLayout.outerRadius)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.comingDays")
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private func rowView(_ row: ComingDays.Row) -> some View {
        let dot = Circle()
            .fill(dotColor(row.tier))
            .frame(width: Layout.dotSize, height: Layout.dotSize)
        let name = Text(row.dayName)
            .scaledFont(size: Layout.nameFont)
            .foregroundStyle(Theme.primaryText)
        let line = Text(row.line.text)
            .scaledFont(size: Layout.lineFont, weight: .semibold)
            .foregroundStyle(row.line.tint)
            .fixedSize(horizontal: false, vertical: true)
        let average = row.average.map {
            Text($0)
                .scaledFont(size: Layout.averageFont, weight: .medium)
                .foregroundStyle(Theme.secondaryText)
        }
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Stack, don't truncate (HIG).
                VStack(alignment: .leading, spacing: RethinkLayout.Grid.x1) {
                    HStack(spacing: Layout.dotToName) { dot; name }
                    line
                    average
                }
                .padding(.vertical, RethinkLayout.Grid.x1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: Layout.dotToName) {
                    dot
                    name.frame(minWidth: nameColumn, alignment: .leading)
                    line
                    Spacer(minLength: RethinkLayout.Grid.x2)
                    average?.fixedSize()
                }
            }
        }
        .frame(minHeight: rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.dayName, row.line.text, row.average].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier("detail.comingDays.\(row.dayIndex)")
    }

    private func dotColor(_ tier: WeekDotTier) -> Color {
        switch tier {
        case .perfect: return Theme.perfectGreen
        case .good: return Theme.ratingGood
        case .bad: return Theme.badRed
        case .noData: return Theme.timelineTrack
        }
    }
}

// MARK: - The Report / Explore switch (glass segmented control)

/// Two glyph segments — `chart.bar.doc.horizontal` = Report,
/// `slider.horizontal.3` = Explore — with a thumb that slides on a spring
/// and a light haptic. Thumb r12 in r16, 4pt inset (owner grid rule).
struct HeroModeSwitch: View {
    @Binding var mode: HeroMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumbSpace
    @State private var tick = 0

    private typealias Layout = RethinkLayout.Switch

    var body: some View {
        HStack(spacing: 0) {
            segment(.report, systemName: "chart.bar.doc.horizontal", label: "Report")
            segment(.explore, systemName: "slider.horizontal.3", label: "Explore")
        }
        .padding(Layout.inset)
        .glassPieceSurface(in: RoundedRectangle(cornerRadius: Layout.radius, style: .continuous),
                           enabled: true, fallback: .track)
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.modeSwitch")
    }

    private func segment(_ value: HeroMode, systemName: String, label: String) -> some View {
        let selected = mode == value
        return Button {
            guard !selected else { return }
            tick += 1
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15)) { mode = value }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: Layout.glyphSize, weight: .medium))
                .foregroundStyle(selected ? Theme.primaryText : Theme.secondaryText)
                .frame(width: Layout.thumbWidth, height: Layout.thumbHeight)
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: Layout.thumbRadius, style: .continuous)
                            .fill(Theme.cardBackground)
                            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                    }
                }
                // 44pt hit target around the 24pt segment.
                .padding(.vertical, RethinkLayout.Grid.x2 + 2)
                .contentShape(Rectangle())
                .padding(.vertical, -(RethinkLayout.Grid.x2 + 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("detail.modeSwitch.\(value.rawValue)")
    }
}
