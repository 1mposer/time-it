import SwiftUI

/// Press feedback on touch-down (fluid-interfaces rule 1): the label scales
/// to 0.97 the instant the finger lands and eases back slower on release;
/// dragging off cancels for free. No scale under Reduce Motion.
struct PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !reduceMotion
        return configuration.label
            .scaleEffect(pressed ? Theme.Motion.pressScale : 1)
            .animation(configuration.isPressed ? nil : Theme.Motion.pressRelease,
                       value: configuration.isPressed)
    }
}

/// The "lift and fall" a tap releases into (owner ruling 2026-11-04): a
/// quick rise past rest (`Theme.Detail.liftScale` / `liftRise` on
/// `Theme.Motion.liftRiseSpring`), then the bouncy `Theme.Motion.liftSpring`
/// fall back. Pairs with `PressStyle` (touch-down) on the span-score button
/// and the detail's edit circles — one implementation for both. Each bump of
/// `trigger` plays it once; under Reduce Motion it never plays, so callers
/// bump unconditionally.
struct LiftOnRelease: ViewModifier {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The lift's animated values.
    private struct Lift {
        var scale: CGFloat = 1
        var rise: CGFloat = 0
    }

    /// The rise leg; the fall is the bouncy `Theme.Motion.liftSpring`.
    static let riseDuration: TimeInterval = 0.12

    func body(content: Content) -> some View {
        // nil under Reduce Motion: the trigger holds still, nothing plays.
        content.keyframeAnimator(initialValue: Lift(), trigger: reduceMotion ? nil : trigger) { content, lift in
            content
                .scaleEffect(lift.scale)
                .offset(y: lift.rise)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(Theme.Detail.liftScale, duration: Self.riseDuration, spring: Theme.Motion.liftRiseSpring)
                SpringKeyframe(1, spring: Theme.Motion.liftSpring)
            }
            KeyframeTrack(\.rise) {
                SpringKeyframe(Theme.Detail.liftRise, duration: Self.riseDuration, spring: Theme.Motion.liftRiseSpring)
                SpringKeyframe(0, spring: Theme.Motion.liftSpring)
            }
        }
    }
}

// MARK: Reveal / de-reveal (owner report 2026-11-05)
//
// Nothing closes abruptly: a dismissed box shrinks back toward the ✕ that
// closed it (phone-gestures "Collapse"), and the card's week row folds back
// under the numerals it slid out from. Both run on `Theme.Motion.reveal`.
// Transitions cannot read the environment, so the sites pick `.opacity`
// under Reduce Motion (the cross-fade) — see `deReveal(anchor:reduceMotion:)`.
extension AnyTransition {
    /// Insertion fades in; removal shrinks to 0.94 toward `anchor` and fades.
    static func deReveal(anchor: UnitPoint) -> AnyTransition {
        .asymmetric(insertion: .opacity,
                    removal: .scale(scale: 0.94, anchor: anchor).combined(with: .opacity))
    }

    /// `deReveal(anchor:)`, or a plain cross-fade under Reduce Motion.
    static func deReveal(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .deReveal(anchor: anchor)
    }

    /// The card's week row: slides out from under the numerals above it and
    /// slides back under them.
    static var unfold: AnyTransition {
        .move(edge: .top).combined(with: .opacity)
    }

    /// `unfold`, or a plain cross-fade under Reduce Motion.
    static func unfold(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .unfold
    }
}

extension View {
    /// Plays the shared lift-and-fall each time `trigger` changes.
    func liftOnRelease(trigger: Int) -> some View {
        modifier(LiftOnRelease(trigger: trigger))
    }
}
