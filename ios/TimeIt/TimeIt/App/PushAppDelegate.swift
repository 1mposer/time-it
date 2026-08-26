import UIKit
import UserNotifications

/// The APNs receiving end: hex-encodes the device token into
/// DeviceRegistration, and routes notification taps through PushRouter.
/// Skipped entirely in UI-test mock runs — those inject their own fakes.
@MainActor
final class PushAppDelegate: NSObject, UIApplicationDelegate {

    /// Assigns the notification delegate before launch finishes so a tap
    /// that cold-starts the app still reaches didReceive.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.isUITestMockRun {
            return true
        }
        #endif
        UNUserNotificationCenter.current().delegate = self
        DeviceRegistration.shared.appDidLaunch()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hexToken = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        DeviceRegistration.shared.updateAPNsToken(hexToken)
    }

    /// Deliberately silent — fires on every enable in Simulator; nothing actionable.
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
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

    /// Foreground arrivals still banner — an alert is worth surfacing in-app too.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
