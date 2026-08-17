import UIKit
import UserNotifications

/// The APNs receiving end (spec §2/§3): hex-encodes the device token into
/// DeviceRegistration, and routes notification taps through PushRouter.
/// Skipped entirely in UI-test mock runs — those inject their own fakes.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return true
        }
        #endif
        // Delegate assignment must happen before launch finishes so a tap
        // that cold-starts the app still reaches didReceive.
        UNUserNotificationCenter.current().delegate = self
        DeviceRegistration.shared.appDidLaunch()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        DeviceRegistration.shared.updateAPNsToken(hexToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Silent: on Simulator (and until the owner adds the APNs
        // entitlement) this fires on every enable — nothing actionable.
    }
}

extension PushAppDelegate: UNUserNotificationCenterDelegate {

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            PushRouter.shared.handle(userInfo: userInfo)
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Foreground arrivals still banner — a Perfect window found while the
        // user happens to be in the app is still worth surfacing.
        completionHandler([.banner, .sound])
    }
}
