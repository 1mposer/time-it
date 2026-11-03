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
