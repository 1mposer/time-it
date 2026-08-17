import Foundation

/// Push receipt routing (spec §3): a Perfect-window alert tap lands on the
/// dashboard with the named Activity's card visible; a digest tap (or any
/// unrecognized payload) just opens the dashboard. No deeper routing in v1.
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()

    /// The Activity to bring into view; the dashboard consumes (nils) it.
    @Published var focusActivityId: String?

    /// Detector payload (#6d): `{ type: 'perfectWindow', activityId,
    /// bucketDate }` — custom keys at the ROOT of userInfo beside "aps"
    /// (the apns2 `data:` merge).
    func handle(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "perfectWindow",
              let activityId = userInfo["activityId"] as? String else {
            return
        }
        focusActivityId = activityId
    }
}
