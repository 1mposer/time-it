import SwiftUI

/// The dashboard's pull-to-refresh with a tunable trigger distance (owner
/// report 2026-11-05: "the refresh still triggers too early on the pull
/// down"). The system control's threshold cannot be changed, so on iOS 18+
/// the list decides for itself: while the finger is down the system
/// spinner's spokes are revealed with the pull (the threshold is announced,
/// one light haptic the moment it is crossed — the commitment); a release
/// while armed runs the refresh and the spinner turns until it finishes.
/// Nothing is held down — the list springs home on the scroll view's own spring and the spinner
/// sits over the band above the first item. Below iOS 18 (no scroll phase
/// API) the system `.refreshable` stays.
enum PullRefresh {
    /// The rubber-banded top overscroll (points) a release must reach —
    /// owner-tunable. At the UIKit curve with a 700pt viewport this is
    /// ~240pt of finger travel (the system control fires well before).
    static let threshold: CGFloat = 110
    /// The spinner's frame (`UIActivityIndicatorView.Style.medium` is 20pt).
    static let indicatorSize: CGFloat = 20
    /// The spinner's resting top inset over the band.
    static let indicatorTop: CGFloat = 6

    /// 0…1 — how much of the threshold the pull has covered (the spokes shown).
    static func progress(overscroll: CGFloat) -> CGFloat {
        guard threshold > 0 else { return 1 }
        return min(max(overscroll / threshold, 0), 1)
    }

    /// Easing back under this fraction of the threshold (finger still down)
    /// disarms the pull; crossing the threshold again re-arms it, with one
    /// more haptic. The gap is the hysteresis that keeps a finger resting on
    /// the threshold from buzzing.
    static let disarmFraction: CGFloat = 0.8

    /// Whether `overscroll` reaches the threshold (arms the pull).
    static func fires(overscroll: CGFloat) -> Bool {
        overscroll >= threshold
    }

    /// The armed state after the finger-down overscroll moves to `overscroll`.
    /// Armed is the commitment (apple-fluid-motion: decide by the committed
    /// threshold, not the resting position): the release refreshes iff armed,
    /// so the haptic and the refresh always agree.
    static func armed(wasArmed: Bool, overscroll: CGFloat) -> Bool {
        if wasArmed { return overscroll >= threshold * disarmFraction }
        return fires(overscroll: overscroll)
    }
}

/// Applies the tunable pull-to-refresh to a `ScrollView` whose top overscroll
/// the caller already reads (`overscroll`, the dashboard's stagger value).
struct PullToRefreshModifier: ViewModifier {
    let overscroll: CGFloat
    let action: () async -> Void

    @State private var dragging = false
    @State private var armed = false
    @State private var refreshing = false
    @State private var hapticTick = 0

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollPhaseChange { oldPhase, newPhase in
                    dragging = newPhase == .interacting
                    guard oldPhase == .interacting, newPhase != .interacting else { return }
                    // Release: the pull committed at the haptic — armed
                    // refreshes, wherever the finger eased to before lifting.
                    if armed { runRefresh() }
                    armed = false
                }
                .onChange(of: overscroll) { _, value in
                    // Finger down only: arm (one haptic) at the threshold,
                    // disarm under `disarmFraction` of it, re-arm past it.
                    guard dragging else { return }
                    let next = PullRefresh.armed(wasArmed: armed, overscroll: value)
                    guard next != armed else { return }
                    armed = next
                    if next { hapticTick += 1 }
                }
                // VoiceOver / Switch Control: the indicator is hidden and the
                // system control is gone on this branch, so the list carries
                // the action itself (same guard — no double trigger).
                .accessibilityAction(named: Text("Refresh")) { runRefresh() }
                .sensoryFeedback(.impact(weight: .light), trigger: hapticTick)
                .overlay(alignment: .top) {
                    PullRefreshIndicator(progress: PullRefresh.progress(overscroll: overscroll),
                                         pulling: dragging && overscroll > 0,
                                         refreshing: refreshing)
                        .padding(.top, PullRefresh.indicatorTop)
                        // Rides down with the pull, under the finger's pace.
                        .offset(y: overscroll * 0.5)
                        .allowsHitTesting(false)
                }
        } else {
            content.refreshable { await action() }
        }
    }

    /// Runs the refresh unless one is already running.
    private func runRefresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            await action()
            refreshing = false
        }
    }
}

/// The system activity indicator (the Apple refresh spinner — owner ruling
/// 2026-11-05: the original symbol, not an arc): its spokes are revealed
/// clockwise with the pull, exactly as `UIRefreshControl` draws them, and it
/// spins while refreshing.
struct PullRefreshIndicator: View {
    let progress: CGFloat
    let pulling: Bool
    let refreshing: Bool

    var body: some View {
        SystemSpinner(animating: refreshing, color: Theme.UIColors.onGradient)
            .frame(width: PullRefresh.indicatorSize, height: PullRefresh.indicatorSize)
            .mask {
                PieWedge(fraction: refreshing ? 1 : progress)
            }
            .opacity(refreshing || (pulling && progress > 0) ? 1 : 0)
            .animation(Theme.Motion.value, value: refreshing)
            .accessibilityHidden(true)
    }
}

/// A wedge from 12 o'clock sweeping `fraction` of the circle clockwise.
struct PieWedge: Shape {
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else { return path }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        path.move(to: centre)
        path.addArc(center: centre, radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * Double(min(fraction, 1))),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// `UIActivityIndicatorView`, shown still (all spokes) when not animating.
struct SystemSpinner: UIViewRepresentable {
    var animating: Bool
    var color: UIColor

    func makeUIView(context: Context) -> UIActivityIndicatorView {
        let view = UIActivityIndicatorView(style: .medium)
        view.hidesWhenStopped = false
        view.color = color
        return view
    }

    func updateUIView(_ view: UIActivityIndicatorView, context: Context) {
        view.color = color
        if animating, !view.isAnimating { view.startAnimating() }
        if !animating, view.isAnimating { view.stopAnimating() }
    }
}

extension View {
    /// Pull-to-refresh that fires only past `PullRefresh.threshold` of
    /// overscroll (iOS 18+; the system control below).
    func pullToRefresh(overscroll: CGFloat, action: @escaping () async -> Void) -> some View {
        modifier(PullToRefreshModifier(overscroll: overscroll, action: action))
    }
}
