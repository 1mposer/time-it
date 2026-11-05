import SwiftUI

// MARK: Liquid Glass — the control layer (owner ruling 2026-11-04)
//
// Every control and piece of floating chrome takes Liquid Glass under iOS 26
// (`.glassEffect(.regular.interactive())` inside a `GlassEffectContainer`);
// below iOS 26 it draws thin material + the light-only hairline. Content
// cards stay opaque — glass is the layer that floats over content, never the
// content itself (HIG, Materials / Liquid Glass).

/// Groups glass pieces so the pieces in a group share one material under
/// iOS 26 (the detail's − / +, the span capsule, the edit circles, and every
/// `GlassControl`); a plain pass-through below it.
struct GlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// What a glass piece draws below iOS 26.
enum GlassFallback {
    /// The flat recess-track fill (the detail's − / + pieces).
    case track
    /// Thin material with the cards' 0.5pt hairline (clear in dark, so the
    /// material alone carries the edge there) — every other glass control.
    case material
}

extension View {
    /// A glass piece's surface: interactive Liquid Glass on iOS 26 (plain
    /// glass while disabled), `fallback` below it.
    @ViewBuilder
    func glassPieceSurface<S: Shape>(in shape: S, enabled: Bool, fallback: GlassFallback) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(enabled ? .regular.interactive() : .regular, in: shape)
        } else {
            switch fallback {
            case .track:
                self.background(Theme.timelineTrack, in: shape)
            case .material:
                self.background(.ultraThinMaterial, in: shape)
                    .overlay(shape.stroke(Theme.cardHairline, lineWidth: Theme.cardHairlineWidth))
            }
        }
    }

    /// The shared glass capsule: a tinted one-line label (`accentInteractive`
    /// at `font`), `height` tall with `horizontalPadding` either side, on the
    /// glass capsule surface. Used by the detail's Score capsule (28pt, 13pt)
    /// and the dashboard's primary capsules (`GlassCapsule.height`, 44pt).
    func glassCapsule(font: Font,
                      height: CGFloat = GlassCapsule.height,
                      horizontalPadding: CGFloat = GlassCapsule.horizontalPadding,
                      enabled: Bool = true) -> some View {
        self.font(font)
            .foregroundStyle(Theme.accentInteractive)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(height: height)
            .glassPieceSurface(in: Capsule(), enabled: enabled, fallback: .material)
    }
}

/// The dashboard's glass capsule metrics.
enum GlassCapsule {
    /// The HIG minimum target — the capsule itself is the whole hit area.
    static let height: CGFloat = 44
    static let horizontalPadding: CGFloat = 20
    /// Primary actions (Enable Location, Try Again, Send a suggestion).
    static let primaryFont = Font.system(size: 15, weight: .semibold)
    /// Add Activity — the dashboard's headline action.
    static let addFont = Font.system(size: 17, weight: .semibold)
    /// A disabled capsule (the Activity-limit state) draws at half strength.
    static let disabledOpacity: Double = 0.5
}

/// A glass control with the shared press feel: `PressStyle` on touch-down,
/// the lift-and-fall (`liftOnRelease`, skipped under Reduce Motion) on
/// release, and a light impact only when the control presents a sheet
/// (`presentsSheet`) — never on an inline action. `label` draws its own
/// glass surface (`glassCapsule` / `glassPieceSurface`); this wraps it in
/// its own glass container. Accessibility identifier/label go on the
/// button itself so XCUI finds the control, not the container.
struct GlassControl<Label: View>: View {
    var presentsSheet = false
    var identifier: String
    var accessibilityLabel: String? = nil
    let action: () -> Void
    @ViewBuilder let label: Label

    @State private var liftTick = 0
    @State private var hapticTick = 0

    var body: some View {
        GlassGroup(spacing: 0) {
            Button {
                liftTick += 1
                if presentsSheet { hapticTick += 1 }
                action()
            } label: {
                label
                    .liftOnRelease(trigger: liftTick)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
            .accessibilityIdentifier(identifier)
            .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
        }
    }
}

private struct OptionalAccessibilityLabel: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content
        }
    }
}
