import SwiftUI

/// The week-dot row (Figma component `517:73` "Week Dots", owner-approved
/// 2026-10-02): seven equal-width cells, each a 10pt weekday initial over an
/// 18pt slot holding a 10pt verdict dot; the ringed day (today on the card,
/// the selected day on the detail) gets a 1.5pt blue 18pt ring and a
/// primary-colour letter. Cell geometry from the component: 12pt label line,
/// 4pt gap, 18pt slot = 34pt tall.
///
/// With `onTap` each data dot is a button (the detail's day-jump control)
/// with a ≥44pt tap target; no-data dots are never tappable.
struct WeekDotsView: View {
    let dots: [WeekDot]
    let ringedDayIndex: Int?
    var onTap: ((Int) -> Void)? = nil
    let identifierPrefix: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The ring is one view that slides between cells on a day-jump.
    @Namespace private var ringSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dots, id: \.dayIndex) { dot in
                cellContainer(for: dot)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 34)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: ringedDayIndex)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifierPrefix)
    }

    @ViewBuilder
    private func cellContainer(for dot: WeekDot) -> some View {
        if let onTap, dot.isJumpable {
            Button {
                onTap(dot.dayIndex)
            } label: {
                cell(for: dot)
                    .frame(maxWidth: .infinity)
                    // ±5 vertical padding pair: a 44pt tap target around the
                    // 34pt cell without growing the row (the beta-pill pattern).
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -5)
            .accessibilityLabel(dot.accessibilityLabel)
            .accessibilityAddTraits(dot.dayIndex == ringedDayIndex ? .isSelected : [])
            .accessibilityIdentifier("\(identifierPrefix).\(dot.dayIndex)")
        } else {
            cell(for: dot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(dot.accessibilityLabel)
                .accessibilityIdentifier("\(identifierPrefix).\(dot.dayIndex)")
        }
    }

    private func cell(for dot: WeekDot) -> some View {
        let ringed = dot.dayIndex == ringedDayIndex
        return VStack(spacing: 4) {
            Text(dot.letter)
                .font(.system(size: 10))
                .tracking(0.1)
                .foregroundStyle(ringed ? Theme.primaryText : Theme.secondaryText)
                .frame(height: 12)
            ZStack {
                dotShape(dot.tier)
                if ringed {
                    Circle()
                        .strokeBorder(Theme.accentInteractive, lineWidth: 1.5)
                        .matchedGeometryEffect(id: "ring", in: ringSpace)
                }
            }
            .frame(width: 18, height: 18)
        }
    }

    @ViewBuilder
    private func dotShape(_ tier: WeekDotTier) -> some View {
        switch tier {
        case .perfect:
            Circle().fill(Theme.perfectGreen).frame(width: 10, height: 10)
        case .good:
            Circle().fill(Theme.accentOrange).frame(width: 10, height: 10)
        case .bad:
            Circle().fill(Theme.badRed).frame(width: 10, height: 10)
        case .noData:
            Circle()
                .fill(Theme.timelineTrack)
                .overlay(Circle().strokeBorder(Theme.divider, lineWidth: 1))
                .frame(width: 10, height: 10)
        }
    }
}

#if DEBUG
#Preview("Week dots") {
    let dots = [WeekDotTier.perfect, .good, .bad, .perfect, .noData, .good, .noData]
        .enumerated()
        .map { WeekDot(dayIndex: $0.offset, letter: ["F", "S", "S", "M", "T", "W", "T"][$0.offset],
                       name: "Day \($0.offset)", tier: $0.element) }
    VStack(spacing: 20) {
        WeekDotsView(dots: dots, ringedDayIndex: 0, identifierPrefix: "preview")
            .frame(width: 277)
        WeekDotsView(dots: dots, ringedDayIndex: 3, onTap: { _ in }, identifierPrefix: "preview.tap")
            .frame(width: 365)
    }
    .padding()
    .background(Theme.cardBackground)
}
#endif
