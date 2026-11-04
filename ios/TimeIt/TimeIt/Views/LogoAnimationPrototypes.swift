import SwiftUI

// PROTOTYPE — the opening logo animation, three variants for the owner to
// compare in Xcode previews. Nothing here is wired into the launch flow; the
// chosen variant gets adopted (and this file trimmed) once the owner rules.

/// The app mark — Figma component "Size=1024" (93:2): three translucent
/// identity-temperature circles in a Venn on a cream rounded-square tile.
/// Geometry measured off the 1024 `AppIcon.png`, as fractions of the tile
/// width. Every animation variant below draws through this one view and
/// settles on `LogoPose.rest`, so the end frame IS the static mark.
struct LogoMark: View {
    /// Tile width (and height).
    let size: CGFloat
    fileprivate var poses: [LogoCircle: LogoPose] = LogoPose.restPoses
    /// Orbit variant only — the circle group spins about the Venn centroid.
    fileprivate var orbit: Angle = .zero

    init(size: CGFloat) {
        self.size = size
    }

    fileprivate init(size: CGFloat, poses: [LogoCircle: LogoPose], orbit: Angle = .zero) {
        self.size = size
        self.poses = poses
        self.orbit = orbit
    }

    var body: some View {
        let tile = RoundedRectangle(cornerRadius: size * LogoGeometry.cornerRadius, style: .continuous)
        ZStack {
            tile.fill(LogoPalette.tile)
            ZStack {
                // Draw order is the icon's: amber under, coral on top.
                ForEach(LogoCircle.drawOrder, id: \.self) { circle in
                    circleView(circle, pose: poses[circle] ?? .rest)
                }
            }
            .frame(width: size, height: size)
            .rotationEffect(orbit, anchor: LogoGeometry.centroidAnchor)
        }
        .frame(width: size, height: size)
        .clipShape(tile)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time It")
        .accessibilityAddTraits(.isImage)
    }

    private func circleView(_ circle: LogoCircle, pose: LogoPose) -> some View {
        // Spread 0 = stacked on the centroid, 1 = resting Venn position;
        // `drift` is an extra offset on top (Converge's off-edge start).
        let rest = circle.restOffset
        let c = LogoGeometry.centroid
        let x = c.width + (rest.width - c.width) * pose.spread + pose.drift.width
        let y = c.height + (rest.height - c.height) * pose.spread + pose.drift.height
        return Circle()
            .fill(LinearGradient(colors: circle.colors, startPoint: .top, endPoint: .bottom))
            .opacity(LogoGeometry.circleOpacity)
            .frame(width: size * LogoGeometry.diameter, height: size * LogoGeometry.diameter)
            .scaleEffect(pose.scale)
            .opacity(pose.opacity)
            .offset(x: x * size, y: y * size)
    }
}

// MARK: - Variants

/// 1 · Converge — each circle starts off its own edge (cool bottom-left, mid
/// top, hot bottom-right) and springs in, staggered 0.1s. ~1.3s.
struct LogoConvergeAnimation: View {
    let size: CGFloat
    var onFinished: () -> Void = {}

    @State private var poses: [LogoCircle: LogoPose] = [
        .cool: LogoPose(drift: CGSize(width: -0.75, height: 0.35), opacity: 0),
        .mid: LogoPose(drift: CGSize(width: 0, height: -0.75), opacity: 0),
        .hot: LogoPose(drift: CGSize(width: 0.75, height: 0.35), opacity: 0),
    ]

    var body: some View {
        LogoMark(size: size, poses: poses)
            // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
            .onAppear(perform: play)
            .logoReduceMotionFallback(size: size, onFinished: onFinished)
    }

    private func play() {
        LogoTiming.stagger(LogoCircle.entranceOrder,
                           step: 0.1,
                           animation: .spring(duration: 1.1, bounce: 0.28),
                           apply: { poses[$0] = .rest },
                           onFinished: onFinished)
    }
}

/// 2 · Bloom — circles grow out of the shared centroid, staggered
/// cool → mid → hot by 0.14s, with an overshooting spring. ~1.3s.
struct LogoBloomAnimation: View {
    let size: CGFloat
    var onFinished: () -> Void = {}

    // 0.01, not 0 — a zero scale is a singular transform (CG console noise).
    @State private var poses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map {
            ($0, LogoPose(spread: 0, scale: 0.01, opacity: 0))
        })

    var body: some View {
        LogoMark(size: size, poses: poses)
            // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
            .onAppear(perform: play)
            .logoReduceMotionFallback(size: size, onFinished: onFinished)
    }

    private func play() {
        LogoTiming.stagger(LogoCircle.entranceOrder,
                           step: 0.14,
                           animation: .spring(duration: 1.0, bounce: 0.38),
                           apply: { poses[$0] = .rest },
                           onFinished: onFinished)
    }
}

/// 3 · Orbit — circles start stacked and small on the centroid, then the
/// group turns two-thirds of a revolution while spreading to rest — a nod
/// to time passing. One gentle spring, ~1.7s; ends at exactly 0°.
struct LogoOrbitAnimation: View {
    let size: CGFloat
    var onFinished: () -> Void = {}

    @State private var poses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map {
            ($0, LogoPose(spread: 0, scale: 0.35, opacity: 0))
        })
    @State private var orbit: Angle = .degrees(-240)

    var body: some View {
        LogoMark(size: size, poses: poses, orbit: orbit)
            // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
            .onAppear(perform: play)
            .logoReduceMotionFallback(size: size, onFinished: onFinished)
    }

    private func play() {
        // Fade in fast so the stack is visible as it starts to turn.
        withAnimation(.easeOut(duration: 0.3)) {
            for circle in LogoCircle.allCases { poses[circle]?.opacity = 1 }
        }
        withAnimation(.spring(duration: 1.7, bounce: 0.12)) {
            orbit = .zero
            for circle in LogoCircle.allCases {
                poses[circle]?.spread = 1
                poses[circle]?.scale = 1
            }
        } completion: {
            onFinished()
        }
    }
}

// MARK: - Model

/// One circle's animated state, in tile-width units. `rest` is the icon.
private struct LogoPose: Equatable {
    var spread: CGFloat = 1
    var drift: CGSize = .zero
    var scale: CGFloat = 1
    var opacity: Double = 1

    static let rest = LogoPose()
    static let restPoses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map { ($0, rest) })
}

private enum LogoCircle: CaseIterable {
    case cool, mid, hot

    /// Bottom to top: mid under, cool over it, hot over both.
    static let drawOrder: [LogoCircle] = [.mid, .cool, .hot]
    /// The stagger order the variants enter in.
    static let entranceOrder: [LogoCircle] = [.cool, .mid, .hot]

    /// Circle centre minus tile centre, in tile widths (icon: centres at
    /// (512, 412), (384, 619), (640, 619) on 1024).
    var restOffset: CGSize {
        switch self {
        case .mid: return CGSize(width: 0, height: -0.098)
        case .cool: return CGSize(width: -0.125, height: 0.104)
        case .hot: return CGSize(width: 0.125, height: 0.104)
        }
    }

    var colors: [Color] {
        let hex = LogoPalette.band(self)
        return [Color(hex: hex.start), Color(hex: hex.end)]
    }
}

private enum LogoGeometry {
    /// Circle diameter ≈ 444/1024 of the tile.
    static let diameter: CGFloat = 0.434
    /// Each circle's own translucency — what makes the overlaps blend.
    static let circleOpacity: Double = 0.85
    /// iOS icon squircle ratio (the PNG itself is square; iOS masks it).
    static let cornerRadius: CGFloat = 0.2237
    /// Mean of the three rest centres — Bloom/Orbit's shared origin.
    static let centroid = CGSize(
        width: LogoCircle.allCases.map(\.restOffset.width).reduce(0, +) / 3,
        height: LogoCircle.allCases.map(\.restOffset.height).reduce(0, +) / 3)
    /// The centroid as a rotation anchor, so the orbit doesn't wobble.
    static let centroidAnchor = UnitPoint(x: 0.5 + centroid.width, y: 0.5 + centroid.height)
}

/// Colours. The circle stops are the identity temperatures' light-mode
/// band stops — copied verbatim from `Theme.Header.bandHex(_:dark: false)`
/// on `owner-tweaks` (not yet on this branch); replace with that call once
/// it merges. The tile cream is sampled off `AppIcon.png`.
private enum LogoPalette {
    static let tile = Color(hex: 0xfdeed6)

    static func band(_ circle: LogoCircle) -> (start: UInt32, end: UInt32) {
        switch circle {
        case .cool: return (0x1774ff, 0x68d7fc)
        case .mid: return (0xe49b23, 0xf3ca5d)
        case .hot: return (0xee6a4d, 0xfa9c86)
        }
    }
}

private enum LogoTiming {
    /// Runs `apply` per item with a growing delay; `onFinished` rides the
    /// last item's completion, so it fires after the final stagger lands.
    static func stagger(_ items: [LogoCircle],
                        step: Double,
                        animation: Animation,
                        apply: @escaping (LogoCircle) -> Void,
                        onFinished: @escaping () -> Void) {
        for (i, item) in items.enumerated() {
            let delayed = animation.delay(step * Double(i))
            if i == items.count - 1 {
                withAnimation(delayed) { apply(item) } completion: { onFinished() }
            } else {
                withAnimation(delayed) { apply(item) }
            }
        }
    }
}

// MARK: - Reduce Motion

/// With Reduce Motion on, every variant collapses to the static mark fading
/// in (0.4s) — the motion variant underneath is replaced, never played.
private struct LogoReduceMotionFallback: ViewModifier {
    let size: CGFloat
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        if reduceMotion {
            LogoMark(size: size)
                .opacity(visible ? 1 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.4)) { visible = true } completion: { onFinished() }
                }
        } else {
            content
        }
    }
}

private extension View {
    func logoReduceMotionFallback(size: CGFloat, onFinished: @escaping () -> Void) -> some View {
        modifier(LogoReduceMotionFallback(size: size, onFinished: onFinished))
    }
}

#if DEBUG
/// Tap anywhere to replay — `.id` rebuilds the variant from its start pose.
private struct LogoReplayPreview<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var replay = 0

    var body: some View {
        VStack(spacing: 16) {
            content().id(replay)
            Text(title).font(.headline)
            Text("Tap to replay").font(.caption).foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.appBackground)
        .contentShape(Rectangle())
        .onTapGesture { replay += 1 }
    }
}

#Preview("Logo · static mark") {
    LogoMark(size: 240)
}

#Preview("Logo · 1 Converge") {
    LogoReplayPreview(title: "Converge") { LogoConvergeAnimation(size: 200) }
}

#Preview("Logo · 2 Bloom") {
    LogoReplayPreview(title: "Bloom") { LogoBloomAnimation(size: 200) }
}

#Preview("Logo · 3 Orbit") {
    LogoReplayPreview(title: "Orbit") { LogoOrbitAnimation(size: 200) }
}

#Preview("Logo · side by side") {
    LogoReplayPreview(title: "Converge · Bloom · Orbit") {
        HStack(spacing: 16) {
            LogoConvergeAnimation(size: 100)
            LogoBloomAnimation(size: 100)
            LogoOrbitAnimation(size: 100)
        }
    }
}
#endif
