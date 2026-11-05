import SwiftUI

// PROTOTYPE — the opening sequence: the owner-picked Converge logo animation
// (lift B, owner timing) and three candidate reveals into the dashboard, for
// the owner to compare in Xcode previews. Nothing here is wired into the
// launch flow yet.

/// The app mark — Figma component "Size=1024" (93:2): three translucent
/// identity-temperature circles in a Venn — drawn tile-less, straight onto
/// the screen (`LogoScreen` supplies the cream). Geometry measured off the
/// 1024 `AppIcon.png`, as fractions of the (virtual) tile width. The animation draws through this one view
/// and settles on `LogoPose.rest`, so the end frame IS the static mark.
struct LogoMark: View {
    /// Scale of the circle group — the width of the virtual tile the Venn
    /// proportions are measured against (nothing is drawn at that size).
    let size: CGFloat
    fileprivate var poses: [LogoCircle: LogoPose] = LogoPose.restPoses

    init(size: CGFloat) {
        self.size = size
    }

    fileprivate init(size: CGFloat, poses: [LogoCircle: LogoPose]) {
        self.size = size
        self.poses = poses
    }

    var body: some View {
        ZStack {
            // Draw order is the icon's: amber under, coral on top.
            ForEach(LogoCircle.drawOrder, id: \.self) { circle in
                circleView(circle, pose: poses[circle] ?? .rest)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time it")
        .accessibilityAddTraits(.isImage)
    }

    private func circleView(_ circle: LogoCircle, pose: LogoPose) -> some View {
        // `drift` offsets the circle from its resting Venn spot (the off-edge start).
        let x = circle.restOffset.width + pose.drift.width
        let y = circle.restOffset.height + pose.drift.height
        return Circle()
            .fill(LinearGradient(colors: circle.colors, startPoint: .top, endPoint: .bottom))
            .opacity(LogoGeometry.circleOpacity)
            .frame(width: size * LogoGeometry.diameter, height: size * LogoGeometry.diameter)
            .opacity(pose.opacity)
            .offset(x: x * size, y: y * size)
    }
}

// MARK: - Screen

/// The full-screen opening canvas: the launch-screen cream edge to edge
/// (safe areas included, so the hand-off from the launch screen is seamless)
/// with the circle group centred at ~60% of the screen width. Nothing clips
/// the circles, so the off-edge starts fly in from beyond the screen.
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

// MARK: - Converge

/// Converge (owner pick) — each circle starts off its own edge (cool
/// bottom-left, mid top, hot bottom-right) and springs in, staggered 0.1s
/// (~1.5s). Then: hold 0.48s → the mark rises (critically damped, 0.8s) to
/// `LogoGeometry.lift` above the centred lockup → a 0.6s beat → the name
/// fades in drifting up 9pt (0.48s) → hold 1.2s (the welcome) → `onFinished`.
/// Every step is +0.2s on the first cut (owner, 2026-11-05).
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
                           animation: .spring(duration: 1.3, bounce: 0.28),
                           apply: { poses[$0] = .rest },
                           onFinished: reveal)
    }

    /// Phase 2, from the moment the circles settle. Bounce 0 on both — the
    /// rise isn't thrown by anything, so it hasn't earned an overshoot. The
    /// name waits for the rise to land, then a beat (owner, 2026-11-05:
    /// overlapping the rise read abrupt), and fades in slower.
    private func reveal() {
        let hold = 0.48, rise = 0.8, beat = 0.6
        withAnimation(.spring(duration: rise, bounce: 0).delay(hold)) { risen = true }
        withAnimation(.spring(duration: 0.48, bounce: 0).delay(hold + rise + beat)) {
            nameShown = true
        } completion: {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2)) // the welcome: let it land (owner, 2026-11-05)
                onFinished()
            }
        }
    }
}

// MARK: - Lockup

/// The mark with the "Time it" wordmark under it — Figma Cover Hero (93:15):
/// #1C1C1E, mark above name. Owner (2026-11-05): thin, not Figma's SF Pro
/// Bold — light weight, lightly tracked, 0.20 tile. Figma's
/// ratios are against a 180pt *tile*; with the tile gone they are mapped onto
/// the circles: the gap runs from the circles' visible bottom (not the virtual
/// tile edge, which would leave ~0.18 tile of dead cream) and the type is
/// well under Figma's 0.36 tile, so the name sits beneath the mark rather
/// than outweighing it.
/// `risen` lifts the mark so the lockup (circle tops → name baseline) sits
/// `LogoGeometry.lift` above screen centre; the rise derives from its height.
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
                    .font(.system(size: m.fontSize, weight: .light))
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
    static let fontScale: CGFloat = 0.20
    static let gapScale: CGFloat = 0.155
    /// How far below its rest spot the name starts before drifting up.
    static let nameDrift: CGFloat = 9

    let fontSize: CGFloat
    let tracking: CGFloat
    /// Name baseline, measured down from the mark's centre.
    let baselineY: CGFloat
    /// Mark-centre offset at rest after the rise (negative = up).
    let risenMarkY: CGFloat

    init(size: CGFloat) {
        fontSize = size * Self.fontScale
        tracking = 0.04 * fontSize // a pinch of air (owner, 2026-11-05)
        // Visible circle extent: the top circle's top, the lower pair's bottom.
        let r = LogoGeometry.diameter / 2
        let top = (LogoCircle.mid.restOffset.height - r) * size
        let bottom = (LogoCircle.cool.restOffset.height + r) * size
        // "Time it" has no descenders, so its ink runs cap height → baseline.
        let capHeight = UIFont.systemFont(ofSize: fontSize, weight: .light).capHeight
        baselineY = bottom + size * Self.gapScale + capHeight
        let lockupHeight = baselineY - top
        risenMarkY = -lockupHeight / 2 - top - LogoGeometry.lift * size
    }
}

// MARK: - Model

/// One circle's animated state, in group-size units. `rest` is the icon.
private struct LogoPose: Equatable {
    var drift: CGSize = .zero
    var opacity: Double = 1

    static let rest = LogoPose()
    static let restPoses: [LogoCircle: LogoPose] = Dictionary(
        uniqueKeysWithValues: LogoCircle.allCases.map { ($0, rest) })
}

private enum LogoCircle: CaseIterable {
    case cool, mid, hot

    /// Bottom to top: mid under, cool over it, hot over both.
    static let drawOrder: [LogoCircle] = [.mid, .cool, .hot]
    /// The stagger order the circles enter in.
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
    /// How far the risen lockup sits above screen centre, in tile widths
    /// (owner, 2026-11-05: lift B, ~95pt on a 393pt screen).
    static let lift: CGFloat = 0.4
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

/// With Reduce Motion on, the animation collapses to its end frame fading
/// in (0.4s) and the motion underneath is replaced, never played.
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
    func logoReduceMotionFallback<EndFrame: View>(
        onFinished: @escaping () -> Void,
        @ViewBuilder endFrame: () -> EndFrame
    ) -> some View {
        modifier(LogoReduceMotionFallback(onFinished: onFinished, endFrame: endFrame()))
    }
}

// MARK: - Dashboard reveal

/// The three candidate hand-offs from the finished lockup into the app.
enum DashboardReveal: CaseIterable {
    /// The cream screen lifts off upward like a curtain; the app underneath
    /// eases up from 94% scale, as if it was waiting just behind.
    case curtain
    /// The camera flies through the mark: the splash scales up past the
    /// viewer and fades, while the app settles in from 106%.
    case zoomThrough
    /// An iris opens from the mark's centre and the app grows out of the
    /// logo, edge to edge.
    case iris
}

/// Converge, then the chosen reveal into `app`. The splash is removed once
/// the reveal lands, so the app underneath is the only thing left.
struct LogoOpeningSequence<App: View>: View {
    let reveal: DashboardReveal
    @ViewBuilder let app: () -> App

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var splashGone = false

    var body: some View {
        ZStack {
            if reveal == .iris {
                if !splashGone { LogoConvergeAnimation(onFinished: start) }
                app().mask { if splashGone { Color.black } else { iris } }
            } else {
                app()
                    .scaleEffect(revealed ? 1 : appStartScale)
                    .opacity(revealed || reveal == .curtain ? 1 : 0)
                if !revealed {
                    LogoConvergeAnimation(onFinished: start)
                        .transition(splashExit)
                        // A removed ZStack child loses its z-order and drops
                        // behind the app — the exit then plays unseen and the
                        // reveal reads as a hard cut. Pin it on top.
                        .zIndex(1)
                }
            }
        }
    }

    private var appStartScale: CGFloat {
        if reduceMotion { return 1 }
        return reveal == .curtain ? 0.94 : 1.06
    }

    private var splashExit: AnyTransition {
        if reduceMotion { return .opacity }
        switch reveal {
        case .curtain: return .move(edge: .top)
        case .zoomThrough: return .scale(scale: 3).combined(with: .opacity)
        case .iris: return .identity
        }
    }

    /// A circle on the risen mark's centre, grown from nothing to past the
    /// screen's far corner. Reduce Motion skips the growth (a straight fade).
    private var iris: some View {
        GeometryReader { geo in
            let size = geo.size.width * LogoGeometry.screenFraction
            let centre = CGPoint(x: geo.size.width / 2,
                                 y: geo.size.height / 2 + LogoLockupMetrics(size: size).risenMarkY)
            let reach = 2 * hypot(geo.size.width, geo.size.height)
            Circle()
                .frame(width: reach, height: reach)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.001)
                .opacity(reduceMotion && !revealed ? 0 : 1)
                .position(centre)
        }
        .ignoresSafeArea()
    }

    private func start() {
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.35)
            : reveal == .iris ? .spring(duration: 1.1, bounce: 0) : .spring(duration: 0.9, bounce: 0)
        withAnimation(animation) { revealed = true } completion: { splashGone = true }
    }
}

#if DEBUG
/// Tap anywhere to replay — `.id` rebuilds the content from its start state.
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


#Preview("Logo · Converge") {
    LogoReplayPreview { LogoConvergeAnimation() }
}

#Preview("Reveal 1 · Curtain") {
    LogoReplayPreview {
        LogoOpeningSequence(reveal: .curtain) { RevealPreviewDashboard() }
    }
}

#Preview("Reveal 2 · Zoom through") {
    LogoReplayPreview {
        LogoOpeningSequence(reveal: .zoomThrough) { RevealPreviewDashboard() }
    }
}

#Preview("Reveal 3 · Iris") {
    LogoReplayPreview {
        LogoOpeningSequence(reveal: .iris) { RevealPreviewDashboard() }
    }
}

/// The live-cards dashboard the reveals hand off to.
private struct RevealPreviewDashboard: View {
    var body: some View {
        DashboardView(viewModel: PreviewFixtures.dashboardViewModel(),
                      registration: PreviewFixtures.registration(),
                      router: PushRouter())
            .fontDesign(.rounded)
    }
}
#endif
