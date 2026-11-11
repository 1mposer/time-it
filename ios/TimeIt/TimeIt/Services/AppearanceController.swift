import Combine
import SwiftUI
import UIKit

/// The one owner of the window's light/dark override (owner ruling
/// 2026-11-11: two modes, the first launch follows the system, then the
/// stored choice rules). It seeds `PreferencesStore.appearance` from the
/// system once, then mirrors every change onto the scene's windows with a
/// cross-dissolve — a window-level override, so sheets and alerts follow and
/// the flip is a real crossfade (SwiftUI does not animate a
/// `preferredColorScheme` change).
@MainActor
final class AppearanceController {
    static let shared = AppearanceController()

    /// The crossfade's length.
    static let crossfadeDuration: TimeInterval = 0.3

    private let preferences: PreferencesStore
    private var subscription: AnyCancellable?

    init(preferences: PreferencesStore? = nil) {
        self.preferences = preferences ?? .shared
    }

    /// Starts mirroring. Idempotent. Inert when a UI-test appearance is
    /// pinned (`pinned != nil`) — the pin's `preferredColorScheme` owns the
    /// window then, and two writers would fight.
    func attach(pinned: ColorScheme?) {
        guard pinned == nil, subscription == nil else { return }
        let windows = Self.windows()
        let systemStyle = windows.first?.traitCollection.userInterfaceStyle
            ?? UITraitCollection.current.userInterfaceStyle
        preferences.seedAppearanceIfNeeded(systemStyle: systemStyle)

        var isFirst = true
        subscription = preferences.$appearance
            .compactMap { $0 }
            .removeDuplicates()
            .sink { appearance in
                Self.apply(appearance, animated: !isFirst)
                isFirst = false
            }
    }

    /// The attach call for the app's root content: computes the UI-test pin
    /// itself (always nil outside DEBUG mock runs).
    func attachForCurrentProcess() {
        attach(pinned: Self.processPin)
    }

    private static var processPin: ColorScheme? {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return ProcessInfo.uiTestAppearance(from: ProcessInfo.processInfo.arguments)
        }
        #endif
        return nil
    }

    private static func apply(_ appearance: AppAppearance, animated: Bool) {
        let style = appearance.interfaceStyle
        for window in windows() where window.overrideUserInterfaceStyle != style {
            guard animated else {
                window.overrideUserInterfaceStyle = style
                continue
            }
            UIView.transition(with: window,
                              duration: crossfadeDuration,
                              options: [.transitionCrossDissolve, .allowUserInteraction]) {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    private static func windows() -> [UIWindow] {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
    }
}
