import SwiftUI

/// Settings' Light / Dark control (owner ruling 2026-11-11, 8b: the wide
/// segment with sun and moon). A system segmented `Picker` drops the icons
/// (a segment is title OR image), so this draws the track and a glass thumb
/// that glides between the two halves; VoiceOver and XCUI see a real
/// segmented picker through `accessibilityRepresentation`.
struct AppearanceSegment: View {
    @Binding var selection: AppAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var thumb

    /// The track's height and the thumb's inset inside it.
    static let height: CGFloat = 44
    static let thumbInset: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppAppearance.allCases) { option in
                segment(option)
            }
        }
        .padding(Self.thumbInset)
        .frame(height: Self.height)
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
            Label(Self.title(option), systemImage: Self.symbol(option))
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
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
#Preview("Appearance segment") {
    @Previewable @State var selection = AppAppearance.light
    List {
        Section("Appearance") {
            AppearanceSegment(selection: $selection)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }
}
#endif
