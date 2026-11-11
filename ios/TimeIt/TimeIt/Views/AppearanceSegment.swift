import SwiftUI

/// Settings' Light / Dark control (owner rulings 2026-11-11, 8b then 13b:
/// a compact icon-only segment, sun | moon, trailing on the "Appearance"
/// row, glass thumb, no words). Custom because a system segmented `Picker`
/// cannot draw this; VoiceOver and XCUI see a real segmented picker with
/// "Light" / "Dark" through `accessibilityRepresentation`.
struct AppearanceSegment: View {
    @Binding var selection: AppAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb

    /// About a quarter of the full-width version (ruling 13b).
    static let size = CGSize(width: 90, height: 32)
    static let thumbInset: CGFloat = 3

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { option in
                segment(option)
            }
        }
        .padding(Self.thumbInset)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Capsule().fill(Theme.timelineTrack))
        .accessibilityRepresentation {
            Picker("Appearance", selection: $selection) {
                ForEach(AppAppearance.allCases) { option in
                    Text(Self.title(option)).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .accessibilityIdentifier("settings.appearance")
    }

    private func segment(_ option: AppAppearance) -> some View {
        let selected = option == selection
        return Button {
            withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) { selection = option }
        } label: {
            Image(systemName: Self.symbol(option))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(selected ? Theme.primaryText : Theme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if selected {
                        Capsule()
                            .fill(Theme.cardBackground)
                            .glassPieceSurface(in: Capsule(), enabled: true, fallback: .material)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    static func title(_ option: AppAppearance) -> String {
        option == .light ? "Light" : "Dark"
    }

    static func symbol(_ option: AppAppearance) -> String {
        option == .light ? "sun.max" : "moon.fill"
    }
}

#if DEBUG
#Preview("Appearance row") {
    @Previewable @State var selection = AppAppearance.light
    List {
        Section("Appearance") {
            HStack {
                Text("Appearance")
                Spacer()
                AppearanceSegment(selection: $selection)
            }
        }
    }
}
#endif
