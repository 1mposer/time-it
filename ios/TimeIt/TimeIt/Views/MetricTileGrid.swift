import SwiftUI

// MARK: - Shared tile geometry (Metrics + Priority steps)

/// The wizard's metric tile (Figma `A/R2/Final` Metrics / Priority): an
/// opaque floating card, radius 16, glyph above the name — content, so never
/// glass (HIG). Two per row, 10pt apart.
enum MetricTile {
    static let height: CGFloat = 96
    static let gap: CGFloat = 10
    static let corner: CGFloat = 16
    static let padding: CGFloat = 14
    static let glyph: CGFloat = 22
    static let ringWidth: CGFloat = 1.5
    /// The Priority step's chosen outline: 2pt, 4pt outside the tile.
    static let outlineWidth: CGFloat = 2
    static let outlineGap: CGFloat = 4
    /// Select / open — a calm spring, no visible overshoot.
    static let selectSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)
    static let reducedMotion = Animation.easeInOut(duration: 0.15)

    /// The tile rows: pairs, or one full-width row for an opened tile. The
    /// opened tile keeps its catalog position; the pairing simply restarts
    /// after it.
    enum Row: Hashable {
        case pair(String, String?)
        case full(String)
    }

    static func rows(for keys: [String], opened: String?) -> [Row] {
        var rows: [Row] = []
        var pending: String?
        for key in keys {
            if key == opened {
                if let left = pending { rows.append(.pair(left, nil)); pending = nil }
                rows.append(.full(key))
            } else if let left = pending {
                rows.append(.pair(left, key))
                pending = nil
            } else {
                pending = key
            }
        }
        if let left = pending { rows.append(.pair(left, nil)) }
        return rows
    }
}

/// The opaque tile surface both steps share.
private struct TileSurface: ViewModifier {
    let ringed: Bool
    let fill: Color

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: MetricTile.corner))
            .overlay {
                if ringed {
                    RoundedRectangle(cornerRadius: MetricTile.corner)
                        .strokeBorder(Theme.accentBrand, lineWidth: MetricTile.ringWidth)
                }
            }
            .cardLift(cornerRadius: MetricTile.corner, light: .rest)
    }
}

// MARK: - The detail's "add metric" tile (build 10)

/// The last cell of the detail's metric grid: the metric square's exact
/// geometry — same card fill, `Theme.Radius.lg` corner, card lift and
/// square floor as `MetricCardView` — holding a "+" and "Add metric". A tap
/// opens the editor on the Metrics step. Shown only while some live metric
/// is not yet on the Activity (`isOffered`). A tap-gesture view with the
/// button trait, not a `Button`: the `Button` + `PressStyle` version kept
/// the accessibility-size detail from ever going idle under XCUI (bisected
/// 2026-11-11 on `testAccessibilityXXLStacksTheHeroAndNothingOverflows`).
struct AddMetricTile: View {
    let action: () -> Void

    @ScaledMetric(relativeTo: .title2) private var glyphSize: CGFloat = 22

    /// Offered while the catalog still has a metric the Activity lacks.
    static func isOffered(displayMetrics: [String], catalog: MetricCatalogProviding) -> Bool {
        catalog.metrics.contains { !displayMetrics.contains($0.key) }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "plus")
                .font(.system(size: glyphSize, weight: .semibold))
                .foregroundStyle(Theme.accentBrand)
                .accessibilityHidden(true)
            Text("Add metric")
                .scaledFont(size: 15, weight: .medium)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, Theme.Detail.metricInset)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .cardLift(cornerRadius: Theme.Radius.lg)
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .onTapGesture(perform: action)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Add metric")
        .accessibilityIdentifier("detail.addMetric")
    }
}

// MARK: - Metrics step

/// The Metrics step: pick which metrics show. A tap selects (accent ring,
/// accent glyph, a bouncing check badge) and opens a numeric metric full
/// width to its comfort-band slider; tapping a selected, closed tile opens
/// it; tapping the opened card's header deselects it. No modes, no tip box
/// (owner rulings 2026-11-11) — what matters most is the next step's job.
struct MetricTileGrid: View {
    @Binding var draft: ActivityDraft
    let catalog: MetricCatalogProviding
    var windUnit: WindSpeedUnit = .kmh

    @State private var opened: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let keys = catalog.metrics.map(\.key)
        VStack(spacing: MetricTile.gap) {
            ForEach(MetricTile.rows(for: keys, opened: openedKey), id: \.self) { row in
                switch row {
                case .full(let key):
                    if let descriptor = catalog.descriptor(for: key) { openedCard(descriptor) }
                case .pair(let left, let right):
                    HStack(spacing: MetricTile.gap) {
                        tile(left)
                        if let right { tile(right) } else { Color.clear.frame(height: MetricTile.height) }
                    }
                }
            }
        }
        .animation(reduceMotion ? MetricTile.reducedMotion : MetricTile.selectSpring, value: openedKey)
        .animation(reduceMotion ? MetricTile.reducedMotion : MetricTile.selectSpring, value: draft.metrics)
        .onAppear {
            // A new draft opens nothing; an edited one opens its first
            // numeric pick so the bounds are one glance away.
            if opened == nil {
                opened = draft.metrics.first { isOpenable($0) }
            }
        }
    }

    /// Only a selected numeric metric with a threshold opens.
    private var openedKey: String? {
        guard let opened, draft.isSelected(opened), isOpenable(opened) else { return nil }
        return opened
    }

    private func isOpenable(_ key: String) -> Bool {
        catalog.descriptor(for: key)?.kind == .numeric && draft.thresholds[key] != nil
    }

    // MARK: Closed tile

    @ViewBuilder
    private func tile(_ key: String) -> some View {
        if let descriptor = catalog.descriptor(for: key) {
            let selected = draft.isSelected(key)
            Button {
                tapTile(descriptor)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Image(systemName: descriptor.iconSymbol)
                            .font(.system(size: MetricTile.glyph))
                            .foregroundStyle(selected ? Theme.accentBrand : Theme.primaryText.opacity(0.75))
                            .symbolEffect(.bounce, value: selected)
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.accentBrand)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(descriptor.displayName)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(MetricTile.padding)
                .frame(maxWidth: .infinity, minHeight: MetricTile.height, alignment: .topLeading)
                .modifier(TileSurface(ringed: selected, fill: Theme.cardBackground))
                .contentShape(RoundedRectangle(cornerRadius: MetricTile.corner))
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: selected)
            .accessibilityIdentifier("metric.\(key)")
            .accessibilityLabel(descriptor.displayName)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func tapTile(_ descriptor: MetricDescriptor) {
        let key = descriptor.key
        if draft.isSelected(key) {
            // A selected tile that can open opens; one that can't (Moon,
            // Dust Alert) deselects.
            if isOpenable(key) {
                opened = key
            } else {
                draft.toggleMetric(key)
            }
        } else {
            draft.selectWithPreset(descriptor)
            if isOpenable(key) { opened = key }
        }
    }

    // MARK: Opened card

    private func openedCard(_ descriptor: MetricDescriptor) -> some View {
        let key = descriptor.key
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                draft.toggleMetric(key)
                opened = nil
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: descriptor.iconSymbol)
                        .font(.system(size: MetricTile.glyph))
                        .foregroundStyle(Theme.accentBrand)
                        .accessibilityHidden(true)
                    Text(descriptor.displayName)
                        .scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(Theme.primaryText)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.accentBrand)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityIdentifier("metric.\(key)")
            .accessibilityLabel(descriptor.displayName)
            .accessibilityAddTraits(.isSelected)
            .accessibilityHint("Removes it")

            ThresholdSlider(descriptor: descriptor,
                            minText: boundText(key, \.minText),
                            maxText: boundText(key, \.maxText),
                            windUnit: windUnit)
        }
        .padding(MetricTile.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(TileSurface(ringed: true, fill: Theme.cardBackground))
        .transition(.opacity)
    }

    /// Binding into one bound's text of the metric's threshold. The card
    /// only renders while the entry exists; the fallback covers the removal
    /// frame.
    private func boundText(_ key: String, _ path: WritableKeyPath<ThresholdDraft, String>) -> Binding<String> {
        Binding(get: { draft.thresholds[key]?[keyPath: path] ?? "" },
                set: { draft.thresholds[key]?[keyPath: path] = $0 })
    }
}

// MARK: - Priority step

/// The Priority step (owner rulings 2026-11-11): the judged metrics picked on
/// the previous step as the same two-column tiles. A pressed tile is
/// prioritised — filled with the brand fill, white glyph and name, a white
/// star; an unpressed one still shows on the card but cannot turn a day Bad.
/// Next stays off until one is pressed.
struct PriorityStepView: View {
    @Binding var draft: ActivityDraft
    let catalog: MetricCatalogProviding

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let keys = PriorityChoice.candidates(in: draft)
        VStack(spacing: MetricTile.gap) {
            ForEach(MetricTile.rows(for: keys, opened: nil), id: \.self) { row in
                if case .pair(let left, let right) = row {
                    HStack(spacing: MetricTile.gap) {
                        tile(left)
                        if let right { tile(right) } else { Color.clear.frame(height: MetricTile.height) }
                    }
                }
            }
        }
        .animation(reduceMotion ? MetricTile.reducedMotion : MetricTile.selectSpring,
                   value: keys.map { PriorityChoice.isChosen($0, in: draft) })
    }

    @ViewBuilder
    private func tile(_ key: String) -> some View {
        if let descriptor = catalog.descriptor(for: key) {
            let chosen = PriorityChoice.isChosen(key, in: draft)
            let ink = chosen ? Theme.onFill : Theme.primaryText
            Button {
                PriorityChoice.toggle(key, in: &draft)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Image(systemName: descriptor.iconSymbol)
                            .font(.system(size: MetricTile.glyph))
                            .foregroundStyle(chosen ? ink : Theme.primaryText.opacity(0.75))
                            .accessibilityHidden(true)
                        Spacer(minLength: 0)
                        if chosen {
                            Image(systemName: "star.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(ink)
                                .symbolEffect(.bounce, value: chosen)
                                .transition(.scale.combined(with: .opacity))
                                .accessibilityHidden(true)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(descriptor.displayName)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .padding(MetricTile.padding)
                .frame(maxWidth: .infinity, minHeight: MetricTile.height, alignment: .topLeading)
                .modifier(TileSurface(ringed: false,
                                      fill: chosen ? Theme.accentBrandFill : Theme.cardBackground))
                // The chosen outline (owner ruling 19c): a 2pt accent ring
                // 4pt OUTSIDE the fill. A stroke on the fill itself would need
                // 3:1 against the fill, which no brand shade reaches, so the
                // ring reads against the ground instead (5.65:1 light, 9.27:1
                // dark), with a ground-coloured gap between ring and fill.
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: MetricTile.corner + MetricTile.outlineGap)
                            .strokeBorder(Theme.accentBrand, lineWidth: MetricTile.outlineWidth)
                            .padding(-MetricTile.outlineGap)
                            .transition(.opacity)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: MetricTile.corner))
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.selection, trigger: chosen)
            .accessibilityIdentifier("editor.priority.\(key)")
            .accessibilityLabel(descriptor.displayName)
            .accessibilityValue(chosen ? "Matters most" : "Shows")
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }
}
