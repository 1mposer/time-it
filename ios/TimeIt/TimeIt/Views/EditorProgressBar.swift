import SwiftUI

/// The wizard's progress bar (Figma `A/R2/Final`, progress board `872:14047`;
/// owner rulings 2026-11-11): a chunky 10pt rounded bar in the top bar,
/// never empty (0.12 on the first step), springing forward "Duolingo style"
/// on every step change. Track `timeline/track`, fill the brand fill with a
/// 2pt white sheen along its top; Reduce Motion drops the bounce.
struct EditorProgressBar: View {
    let fraction: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 10
    /// The advance spring (frame note): bouncy, settles under half a second.
    static let advance = Animation.spring(duration: 0.45, bounce: 0.35)
    static let advanceReduced = Animation.easeInOut(duration: 0.2)

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width * fraction, Self.height)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.timelineTrack)
                Capsule()
                    .fill(Theme.accentBrandFill)
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 2)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                    .overlay(Capsule().stroke(Theme.accentBrandEdge, lineWidth: 1))
                    .frame(width: width)
            }
        }
        .frame(height: Self.height)
        .animation(reduceMotion ? Self.advanceReduced : Self.advance, value: fraction)
        .accessibilityElement()
        .accessibilityIdentifier("editor.progress")
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }
}

#if DEBUG
#Preview("Progress") {
    VStack(spacing: 16) {
        ForEach(EditorStep.allCases, id: \.rawValue) { step in
            EditorProgressBar(fraction: WizardProgress.fraction(for: step))
        }
    }
    .padding()
}
#endif
