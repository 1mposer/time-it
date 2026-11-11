import SwiftUI

// The opening sequence (owner rulings 2026-11-11, Lane A item 3): the
// owner-picked Converge logo animation (lift B, owner timing), then the
// zoom-through reveal into the dashboard. Cold launch only, a tap skips it,
// a push-tap launch never waits on it, and Reduce Motion collapses it to the
// end frame. `OpeningGate` is the one entry point (TimeItApp).

/// The app mark — Figma component "Size=1024" (93:2): three translucent
/// identity-temperature circles in a Venn — drawn tile-less, straight onto
/// the screen (`LogoScreen` supplies the cream). Geometry measured off the
/// 1024 `AppIcon.png`, as fractions of the (virtual) tile width. The
/// animation draws through this one view and settles on `LogoPose.rest`, so
/// the end frame IS the static mark.
struct LogoMark: View {
    /// Scale of the circle group — the width of the virtual tile the Venn
    /// proportions are measured against (nothing is drawn at that size).
    let size: CGFloat
    fileprivate var poses: [LogoCircle: LogoPose] = LogoPose.restPoses

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
        .logoReduceMotionFallback(onFinished: onFinished)
    }

    /// Phase 1 — the circles spring in 0.1s apart; phase 2 rides the last
    /// circle's completion, so it starts once the final one lands.
    private func play() {
        let order = LogoCircle.entranceOrder
        for (i, circle) in order.enumerated() {
            let spring = Animation.spring(duration: 1.3, bounce: 0.28).delay(0.1 * Double(i))
            if i == order.count - 1 {
                withAnimation(spring) { poses[circle] = .rest } completion: { reveal() }
            } else {
                withAnimation(spring) { poses[circle] = .rest }
            }
        }
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

/// The mark with the "Time it" wordmark under it — Figma Cover Hero (93:15),
/// mark above name, the wordmark in the brand accent and SF Pro Rounded (the
/// app's design, owner ruling Q12b). Owner (2026-11-05): thin, not Figma's SF Pro
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

/// Colours. The circle stops are the identity temperatures' LIGHT band
/// stops in both modes (owner ruling Q14a: the mark is identity, not the
/// temperature band), read from the one band table. The background is the
/// launch screen's asset colour (cream light, sage ground dark), so the
/// hand-off from the launch screen is seamless; the wordmark takes the brand
/// accent (mint in dark, Q13a).
private enum LogoPalette {
    static let background = Color("LaunchBackground")
    static let wordmark = Theme.accentBrand

    static func band(_ circle: LogoCircle) -> (start: UInt32, end: UInt32) {
        let band: Theme.HeaderBand
        switch circle {
        case .cool: band = .cool
        case .mid: band = .mid
        case .hot: band = .hot
        }
        let hex = Theme.Fade.bandHex(band, dark: false)
        return (hex.start, hex.end)
    }
}

// MARK: - Reduce Motion

/// With Reduce Motion on, Converge collapses to its end frame — the risen
/// lockup — fading in (0.4s); the motion underneath is replaced, never played.
private struct LogoReduceMotionFallback: ViewModifier {
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    func body(content: Content) -> some View {
        if reduceMotion {
            LogoScreen { size in LogoLockup(size: size) }
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
        modifier(LogoReduceMotionFallback(onFinished: onFinished))
    }
}

// MARK: - Opening gate

/// Whether the opening sequence plays — the owner's rules (2026-11-11, Q15a):
/// only on a cold launch, never for a UI-test run that opts out, never once a
/// push tap is already routing somewhere.
enum OpeningPolicy {
    static func shouldPlay(coldLaunch: Bool, pushRoutePending: Bool, uiTestSkip: Bool) -> Bool {
        coldLaunch && !pushRoutePending && !uiTestSkip
    }

    /// The XCUI opt-out argument (the launch helper passes it on every run
    /// except the one test that watches the opening).
    static let uiTestSkipArgument = "UITEST_SKIP_OPENING"
}

/// True while the opening sequence covers the app — the dashboard defers its
/// first-run location prompt until it turns false (owner ruling Q16).
private struct OpeningInProgressKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var openingInProgress: Bool {
        get { self[OpeningInProgressKey.self] }
        set { self[OpeningInProgressKey.self] = newValue }
    }
}

/// The app root: Converge, then the zoom-through reveal into `app`. The app
/// is mounted underneath from the first frame (its fetch hides behind the
/// logo); a tap or an arriving push route finishes the opening at once.
struct OpeningGate<App: View>: View {
    @ObservedObject var router: PushRouter
    @ViewBuilder let app: () -> App

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase

    enum Phase { case playing, revealing, done }

    init(plays: Bool, router: PushRouter, @ViewBuilder app: @escaping () -> App) {
        self.router = router
        self.app = app
        _phase = State(initialValue: plays ? .playing : .done)
    }

    var body: some View {
        ZStack {
            app()
                .scaleEffect(phase == .playing && !reduceMotion ? Self.appStartScale : 1)
                .opacity(phase == .playing ? 0 : 1)
                .environment(\.openingInProgress, phase != .done)
            if phase == .playing {
                LogoConvergeAnimation(onFinished: reveal)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: reveal)
                    .accessibilityAction(named: "Skip", reveal)
                    .accessibilityIdentifier("opening.splash")
                    .transition(splashExit)
                    // A removed ZStack child loses its z-order and drops
                    // behind the app — the exit then plays unseen. Pin it.
                    .zIndex(1)
            }
        }
        .onChange(of: router.focusActivityId) { _, id in
            if id != nil { reveal() }
        }
    }

    /// The app settles in from 106% as the splash flies past the viewer.
    static var appStartScale: CGFloat { 1.06 }
    /// The splash's exit scale (owner tune `c443ac6`: scale 3).
    static var splashExitScale: CGFloat { 3 }

    private var splashExit: AnyTransition {
        reduceMotion ? .opacity : .scale(scale: Self.splashExitScale).combined(with: .opacity)
    }

    private func reveal() {
        guard phase == .playing else { return }
        let animation: Animation = reduceMotion
            ? .easeInOut(duration: 0.35)
            : .spring(duration: 0.9, bounce: 0)
        withAnimation(animation) { phase = .revealing } completion: { phase = .done }
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

#Preview("Opening · Zoom through") {
    LogoReplayPreview {
        OpeningGate(plays: true, router: PushRouter()) { RevealPreviewDashboard() }
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
