import SwiftUI

// PROTOTYPE — the opening logo animation, three variants for the owner to
// compare in Xcode previews. Nothing here is wired into the launch flow; the
// chosen variant gets adopted (and this file trimmed) once the owner rules.

/// The app mark — Figma component "Size=1024" (93:2): three translucent
/// identity-temperature circles in a Venn — drawn tile-less, straight onto
/// the screen (`LogoScreen` supplies the cream). Geometry measured off the
/// 1024 `AppIcon.png`, as fractions of the (virtual) tile width. Every animation variant below draws through this one view and
/// settles on `LogoPose.rest`, so the end frame IS the static mark.
struct LogoMark: View {
    /// Scale of the circle group — the width of the virtual tile the Venn
    /// proportions are measured against (nothing is drawn at that size).
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
        ZStack {
            // Draw order is the icon's: amber under, coral on top.
            ForEach(LogoCircle.drawOrder, id: \.self) { circle in
                circleView(circle, pose: poses[circle] ?? .rest)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(orbit, anchor: LogoGeometry.centroidAnchor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time it")
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

// MARK: - Screen

/// The full-screen opening canvas: the launch-screen cream edge to edge
/// (safe areas included, so the hand-off from the launch screen is seamless)
/// with the circle group centred at ~60% of the screen width. Nothing clips
/// the circles, so Converge's off-edge starts fly in from beyond the screen.
struct LogoScreen<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        ZStack {
            LogoPalette.background.ignoresSafeArea()
            GeometryReader { geo in
                content(geo.size.width * LogoGeometry.screenFraction)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
            .ignoresSafeArea()
        }
    }
}

/// The static mark as a full-screen opening screen.
struct LogoStaticScreen: View {
    var body: some View {
        LogoScreen { size in LogoMark(size: size) }
    }
}

// MARK: - Variants

/// 1 · Converge (owner pick) — each circle starts off its own edge (cool
/// bottom-left, mid top, hot bottom-right) and springs in, staggered 0.1s
/// (~1.3s). Then: hold 0.28s → the mark rises (critically damped, 0.6s) until
/// the whole mark + name lockup is centred → 60% into the rise the name
/// fades in drifting up 9pt (0.48s) → hold 0.5s → `onFinished`. ~2.9s total.
struct LogoConvergeAnimation: View {
    var onFinished: () -> Void = {}

    @State private var poses: [LogoCircle: LogoPose] = [
        .cool: LogoPose(drift: CGSize(width: -0.75, height: 0.35), opacity: 0),
        .mid: LogoPose(drift: CGSize(width: 0, height: -0.75), opacity: 0),
        .hot: LogoPose(drift: CGSize(width: 0.75, height: 0.35), opacity: 0),
    ]
    @State private var risen = false
    @State private var nameShown = false

    var body: some View {
        LogoScreen { size in
            LogoLockup(size: size, poses: poses, risen: risen, nameShown: nameShown)
        }
        // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
        .onAppear(perform: play)
        .logoReduceMotionFallback(onFinished: onFinished) {
            LogoScreen { size in LogoLockup(size: size) }
        }
    }

    private func play() {
        LogoTiming.stagger(LogoCircle.entranceOrder,
                           step: 0.1,
                           animation: .spring(duration: 1.1, bounce: 0.28),
                           apply: { poses[$0] = .rest },
                           onFinished: reveal)
    }

    /// Phase 2, from the moment the circles settle. Bounce 0 on both — the
    /// rise isn't thrown by anything, so it hasn't earned an overshoot.
    private func reveal() {
        let hold = 0.28, rise = 0.6
        withAnimation(.spring(duration: rise, bounce: 0).delay(hold)) { risen = true }
        withAnimation(.spring(duration: 0.48, bounce: 0).delay(hold + rise * 0.6)) {
            nameShown = true
        } completion: {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                onFinished()
            }
        }
    }
}

/// 2 · Bloom — circles grow out of the shared centroid, staggered
/// cool → mid → hot by 0.14s, with an overshooting spring. ~1.3s.
struct LogoBloomAnimation: View {
    var onFinished: () -> Void = {}

    // 0.01, not 0 — a zero scale is a singular transform (CG console noise).
    @State private var poses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map {
            ($0, LogoPose(spread: 0, scale: 0.01, opacity: 0))
        })

    var body: some View {
        LogoScreen { size in LogoMark(size: size, poses: poses) }
            // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
            .onAppear(perform: play)
            .logoReduceMotionFallback(onFinished: onFinished)
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
    var onFinished: () -> Void = {}

    @State private var poses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map {
            ($0, LogoPose(spread: 0, scale: 0.35, opacity: 0))
        })
    @State private var orbit: Angle = .degrees(-240)

    var body: some View {
        LogoScreen { size in LogoMark(size: size, poses: poses, orbit: orbit) }
            // onAppear sits inside the fallback, so Reduce Motion never runs `play`.
            .onAppear(perform: play)
            .logoReduceMotionFallback(onFinished: onFinished)
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

// MARK: - Lockup

/// The mark with the "Time it" wordmark under it — Figma Cover Hero (93:15):
/// SF Pro Bold, tracking −1.5 at 64pt, #1C1C1E, mark above name. Figma's
/// ratios are against a 180pt *tile*; with the tile gone they are mapped onto
/// the circles: the gap runs from the circles' visible bottom (not the virtual
/// tile edge, which would leave ~0.18 tile of dead cream) and the type is
/// 0.30 tile rather than Figma's 0.36 — at 0.36 the name reads ~1.6× the
/// circles' width and outweighs a mark that no longer has a tile's mass.
/// `risen` lifts the mark so the lockup (circle tops → name baseline) is
/// optically centred on screen; the rise is derived from the lockup height.
/// The default arguments are the end frame (Reduce Motion shows exactly it).
private struct LogoLockup: View {
    let size: CGFloat
    var poses: [LogoCircle: LogoPose] = LogoPose.restPoses
    var risen = true
    var nameShown = true

    var body: some View {
        let m = LogoLockupMetrics(size: size)
        LogoMark(size: size, poses: poses)
            .overlay {
                Text("Time it")
                    // A fixed size on purpose: this is a logo lockup, so it
                    // never scales with Dynamic Type (`.system(size:)` is
                    // un-scaled; the label below carries it for VoiceOver).
                    .font(.system(size: m.fontSize, weight: .bold))
                    .tracking(m.tracking)
                    .foregroundStyle(LogoPalette.wordmark)
                    .lineLimit(1)
                    .fixedSize()
                    // Pin the baseline, not the text box, to the mark centre.
                    .alignmentGuide(VerticalAlignment.center) { $0[.firstTextBaseline] }
                    .offset(y: m.baselineY + (nameShown ? 0 : LogoLockupMetrics.nameDrift))
                    .opacity(nameShown ? 1 : 0)
            }
            .offset(y: risen ? m.risenMarkY : 0)
            // One element for the whole lockup; the circles are decorative.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Time it")
            .accessibilityAddTraits(.isImage)
    }
}

/// Lockup layout, in points, for a circle group of `size` (the virtual tile).
private struct LogoLockupMetrics {
    /// Wordmark size and mark-to-name gap, in tile widths (see `LogoLockup`).
    static let fontScale: CGFloat = 0.30
    static let gapScale: CGFloat = 0.155
    /// How far below its rest spot the name starts before drifting up.
    static let nameDrift: CGFloat = 9

    let fontSize: CGFloat
    let tracking: CGFloat
    /// Name baseline, measured down from the mark's centre.
    let baselineY: CGFloat
    /// Mark-centre offset that centres the lockup on screen (negative = up).
    let risenMarkY: CGFloat

    init(size: CGFloat) {
        fontSize = size * Self.fontScale
        tracking = -1.5 / 64 * fontSize
        // Visible circle extent: the top circle's top, the lower pair's bottom.
        let r = LogoGeometry.diameter / 2
        let top = (LogoCircle.mid.restOffset.height - r) * size
        let bottom = (LogoCircle.cool.restOffset.height + r) * size
        // "Time it" has no descenders, so its ink runs cap height → baseline.
        let capHeight = UIFont.systemFont(ofSize: fontSize, weight: .bold).capHeight
        baselineY = bottom + size * Self.gapScale + capHeight
        let lockupHeight = baselineY - top
        risenMarkY = -lockupHeight / 2 - top
    }
}

// MARK: - Model

/// One circle's animated state, in group-size units. `rest` is the icon.
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

    /// Circle centre minus group centre, in group sizes (icon: centres at
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
    /// Group size as a fraction of the screen width.
    static let screenFraction: CGFloat = 0.6
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
/// it merges. The background is the launch screen's asset colour, so the
/// hand-off from launch screen to animation is seamless.
private enum LogoPalette {
    static let background = Color("LaunchBackground")
    /// The wordmark ink — Figma's #1C1C1E (the cream background is light-only).
    static let wordmark = Color(hex: 0x1C1C1E)

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

/// With Reduce Motion on, every variant collapses to its end frame fading
/// in (0.4s) — the static mark, or Converge's lockup — and the motion variant
/// underneath is replaced, never played.
private struct LogoReduceMotionFallback<EndFrame: View>: ViewModifier {
    let onFinished: () -> Void
    let endFrame: EndFrame

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        if reduceMotion {
            endFrame
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
    func logoReduceMotionFallback(onFinished: @escaping () -> Void) -> some View {
        logoReduceMotionFallback(onFinished: onFinished) { LogoStaticScreen() }
    }

    func logoReduceMotionFallback<EndFrame: View>(
        onFinished: @escaping () -> Void,
        @ViewBuilder endFrame: () -> EndFrame
    ) -> some View {
        modifier(LogoReduceMotionFallback(onFinished: onFinished, endFrame: endFrame()))
    }
}

#if DEBUG
/// Tap anywhere to replay — `.id` rebuilds the variant from its start pose
/// (for Converge, the whole sequence: circles, rise and wordmark).
private struct LogoReplayPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var replay = 0

    var body: some View {
        content()
            .id(replay)
            .contentShape(Rectangle())
            .onTapGesture { replay += 1 }
    }
}

#Preview("Logo · lockup end frame") {
    LogoScreen { size in LogoLockup(size: size) }
}

#Preview("Logo · static mark") {
    LogoStaticScreen()
}

#Preview("Logo · 1 Converge") {
    LogoReplayPreview { LogoConvergeAnimation() }
}

#Preview("Logo · 2 Bloom") {
    LogoReplayPreview { LogoBloomAnimation() }
}

#Preview("Logo · 3 Orbit") {
    LogoReplayPreview { LogoOrbitAnimation() }
}

#Preview("Logo · side by side") {
    // Three phone-aspect panels; the clip is preview-only, for the comparison.
    HStack(spacing: 12) {
        ForEach(["Converge", "Bloom", "Orbit"], id: \.self) { name in
            LogoReplayPreview {
                switch name {
                case "Converge": LogoConvergeAnimation()
                case "Bloom": LogoBloomAnimation()
                default: LogoOrbitAnimation()
                }
            }
            .aspectRatio(9.0 / 19.5, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    .padding(12)
}
#endif
