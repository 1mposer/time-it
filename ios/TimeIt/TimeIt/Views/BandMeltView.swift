import SwiftUI

/// The dashboard's backdrop (Figma Final – Opus v1 "Band melt"): the
/// temperature band and its glow blob in ONE masked, clipped group, melting
/// into the plain ground from the first list item's top. Drawn behind the
/// header text and the card list, full-screen (status bar included), and
/// never hit-testable — the cards scroll over it and it does not move.
struct BandMeltView: View {
    /// The first list item's resting top, in this view's (full-screen) space.
    let firstCardTop: CGFloat
    /// Current-hour temperature; nil (no reading) draws the Cool band.
    let temp: Double?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { colorScheme == .dark }

    var body: some View {
        let geometry = FadeGeometry(firstCardTop: firstCardTop)
        let hex = Theme.Fade.bandHex(Theme.HeaderBand.band(forTemp: temp), dark: dark)
        let blob = geometry.blobRect(dark: dark)
        ZStack(alignment: .topLeading) {
            Theme.Fade.ground(dark: dark)

            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: hex.start), Color(hex: hex.end)],
                               startPoint: Theme.Fade.bandStart,
                               endPoint: Theme.Fade.bandEnd)
                DriftingBlob(rect: blob,
                             color: dark ? Color(hex: hex.end) : Color(hex: hex.start),
                             opacity: dark ? Theme.Fade.blobOpacityDark : Theme.Fade.blobOpacityLight,
                             reduceMotion: reduceMotion)
            }
            .frame(height: geometry.groupHeight)
            .frame(maxWidth: .infinity)
            .mask {
                LinearGradient(stops: geometry.maskStops.map {
                                   Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location)
                               },
                               startPoint: .top,
                               endPoint: .bottom)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The glow blob: blurred ONCE into an offscreen layer (`drawingGroup`) and
/// only translated afterwards — the drift never re-runs the blur. Under
/// Reduce Motion the timeline pauses and the blob holds at keyframe A.
private struct DriftingBlob: View {
    let rect: CGRect
    let color: Color
    let opacity: Double
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: Theme.Fade.driftFrameInterval,
                                paused: reduceMotion)) { context in
            let drift = FadeGeometry.driftOffset(at: context.date.timeIntervalSinceReferenceDate,
                                                 reduceMotion: reduceMotion)
            BlurredEllipse(size: rect.size, color: color, opacity: opacity)
                .offset(x: rect.minX + drift.width, y: rect.minY + drift.height)
        }
    }
}

/// The blurred ellipse, padded by 3σ so the offscreen layer never crops the
/// blur's tail. Equatable inputs, so a drift tick re-renders nothing here.
private struct BlurredEllipse: View, Equatable {
    let size: CGSize
    let color: Color
    let opacity: Double

    private var pad: CGFloat { Theme.Fade.blobBlur * 3 }

    var body: some View {
        Ellipse()
            .fill(color.opacity(opacity))
            .frame(width: size.width, height: size.height)
            .padding(pad)
            .blur(radius: Theme.Fade.blobBlur)
            .drawingGroup()
            .padding(-pad)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

#if DEBUG
#Preview("Band melt — mid") {
    BandMeltView(firstCardTop: 229, temp: 34)
        .ignoresSafeArea()
}

#Preview("Band melt — dark cool") {
    BandMeltView(firstCardTop: 229, temp: 24)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
}
#endif
