import SwiftUI

/// The custom gradient threshold slider (§5 of the wizard redesign): capsule
/// track with a semantic danger gradient, circular draggable thumb(s) that
/// snap to the metric's `MetricRange.step`, and a tap-to-type exact-entry
/// fallback. No third-party dependency. Values are written back through the
/// draft's `minText`/`maxText` so `parseBound` validation still applies.
struct ThresholdSlider: View {
    let descriptor: MetricDescriptor
    @Binding var minText: String
    @Binding var maxText: String

    @State private var isTyping = false
    @FocusState private var focusedBound: Bound?

    private enum Bound { case min, max }

    private static let thumbSize: CGFloat = 24

    /// The escape hatch: a legacy threshold carrying a bound its declared
    /// `boundStyle` doesn't show (e.g. a windSpeed min authored pre-redesign)
    /// renders dual-thumb so no data is hidden or lost.
    static func effectiveBoundStyle(for descriptor: MetricDescriptor, draft: ThresholdDraft) -> BoundStyle {
        let declared = descriptor.boundStyle ?? .range
        switch declared {
        case .range:
            return .range
        case .maxOnly:
            return parse(draft.minText) == nil ? .maxOnly : .range
        case .minOnly:
            return parse(draft.maxText) == nil ? .minOnly : .range
        }
    }

    /// Snaps a raw track value to the metric's step, clamped to its range.
    static func snap(_ value: Double, to range: MetricRange) -> Double {
        let clamped = Swift.min(Swift.max(value, range.min), range.max)
        let steps = ((clamped - range.min) / range.step).rounded()
        return range.min + steps * range.step
    }

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              value.isFinite else { return nil }
        return value
    }

    // MARK: derived state

    private var range: MetricRange {
        descriptor.range ?? MetricRange(min: 0, max: 100, step: 1)
    }

    private var style: BoundStyle {
        var probe = ThresholdDraft()
        probe.minText = minText
        probe.maxText = maxText
        return Self.effectiveBoundStyle(for: descriptor, draft: probe)
    }

    private var minValue: Double? { Self.parse(minText) }
    private var maxValue: Double? { Self.parse(maxText) }

    /// Where a thumb sits while its text is empty/unparsable — the preset,
    /// else the range end it edits.
    private var minThumbValue: Double { minValue ?? descriptor.presetMin ?? range.min }
    private var maxThumbValue: Double { maxValue ?? descriptor.presetMax ?? range.max }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isTyping {
                typingFields
            } else {
                valueLabel
            }
            track
                .frame(height: Self.thumbSize)
        }
        .padding(.vertical, 4)
    }

    // MARK: value label + typing fallback (the only keyboard on the tab)

    private var valueLabel: some View {
        Button {
            isTyping = true
        } label: {
            Text(labelText)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.primaryText)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor.value.\(descriptor.key)")
    }

    private var labelText: String {
        let unit = descriptor.unit.isEmpty ? "" : " \(descriptor.unit)"
        switch style {
        case .range:
            return "\(text(minValue))–\(text(maxValue))\(unit)"
        case .maxOnly:
            return "≤ \(text(maxValue))\(unit)"
        case .minOnly:
            return "≥ \(text(minValue))\(unit)"
        }
    }

    private func text(_ value: Double?) -> String {
        value.map(ThresholdDraft.format) ?? "—"
    }

    private var typingFields: some View {
        HStack(spacing: 12) {
            if style != .maxOnly {
                boundField("min", text: $minText, bound: .min,
                           identifier: "editor.min.\(descriptor.key)")
            }
            if style != .minOnly {
                boundField("max", text: $maxText, bound: .max,
                           identifier: "editor.max.\(descriptor.key)")
            }
        }
        .onChange(of: focusedBound) { _, focused in
            if focused == nil { isTyping = false }
        }
    }

    private func boundField(_ placeholder: String, text: Binding<String>,
                            bound: Bound, identifier: String) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
            .frame(width: 84)
            .focused($focusedBound, equals: bound)
            .onSubmit { isTyping = false }
            .accessibilityIdentifier(identifier)
    }

    // MARK: track + thumbs

    private var track: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - Self.thumbSize, 1)
            let midY = geometry.size.height / 2
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: gradientColors,
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
                if range.step >= 1 {
                    ticks(usable: usable, midY: midY)
                }
                if style != .maxOnly {
                    thumb(value: minThumbValue, usable: usable, midY: midY, bound: .min,
                          identifier: "editor.slider.min.\(descriptor.key)")
                }
                if style != .minOnly {
                    thumb(value: maxThumbValue, usable: usable, midY: midY, bound: .max,
                          identifier: "editor.slider.max.\(descriptor.key)")
                }
            }
        }
    }

    /// dangerHigh = green → orange → red left-to-right; dangerLow reversed;
    /// dangerBothEnds = red → green → red (settled Theme colors).
    private var gradientColors: [Color] {
        switch descriptor.gradient ?? .dangerHigh {
        case .dangerHigh: return [Theme.perfectGreen, Theme.accentOrange, Theme.badRed]
        case .dangerLow: return [Theme.badRed, Theme.accentOrange, Theme.perfectGreen]
        case .dangerBothEnds: return [Theme.badRed, Theme.perfectGreen, Theme.badRed]
        }
    }

    /// Tick marks at every step (none for rainFall's 0.5 step).
    private func ticks(usable: CGFloat, midY: CGFloat) -> some View {
        Canvas { context, _ in
            let steps = Int(((range.max - range.min) / range.step).rounded())
            guard steps > 0 else { return }
            for index in 0...steps {
                let x = Self.thumbSize / 2 + usable * CGFloat(index) / CGFloat(steps)
                let rect = CGRect(x: x - 0.5, y: midY - 3, width: 1, height: 6)
                context.fill(Path(rect), with: .color(.white.opacity(0.35)))
            }
        }
        .allowsHitTesting(false)
    }

    private func thumb(value: Double, usable: CGFloat, midY: CGFloat,
                       bound: Bound, identifier: String) -> some View {
        let fraction = (value - range.min) / max(range.max - range.min, .ulpOfOne)
        return Circle()
            .fill(.white)
            .frame(width: Self.thumbSize, height: Self.thumbSize)
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08)))
            .position(x: Self.thumbSize / 2 + usable * CGFloat(fraction), y: midY)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        drag(to: gesture.location.x, usable: usable, bound: bound)
                    }
            )
            .accessibilityIdentifier(identifier)
    }

    /// Snaps the dragged position and writes it back through the text fields.
    /// A thumb writes ONLY its own bound — the other bound (even a legacy one
    /// the declared style wouldn't show) is never touched.
    private func drag(to x: CGFloat, usable: CGFloat, bound: Bound) {
        let fraction = Double((x - Self.thumbSize / 2) / usable)
        var value = Self.snap(range.min + fraction * (range.max - range.min), to: range)
        switch bound {
        case .min:
            if let ceiling = maxValue, style == .range { value = Swift.min(value, ceiling) }
            minText = ThresholdDraft.format(value)
        case .max:
            if let floor = minValue, style == .range { value = Swift.max(value, floor) }
            maxText = ThresholdDraft.format(value)
        }
    }
}

#if DEBUG
/// Stateful host so canvas thumbs actually drag.
private struct SliderPreviewHost: View {
    let descriptor: MetricDescriptor
    @State var minText: String
    @State var maxText: String

    init(_ key: String) {
        let descriptor = StaticMetricCatalog().descriptor(for: key)!
        self.descriptor = descriptor
        let draft = ThresholdDraft(preset: descriptor)
        _minText = State(initialValue: draft.minText)
        _maxText = State(initialValue: draft.maxText)
    }

    var body: some View {
        ThresholdSlider(descriptor: descriptor, minText: $minText, maxText: $maxText)
            .padding(.horizontal)
    }
}

#Preview("dangerBothEnds — temp") {
    SliderPreviewHost("temp")
}

#Preview("dangerHigh — windSpeed") {
    SliderPreviewHost("windSpeed")
}

#Preview("dangerLow — visibility") {
    SliderPreviewHost("visibility")
}
#endif
