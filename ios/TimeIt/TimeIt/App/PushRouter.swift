import Foundation

/// Push receipt routing: a Perfect-window alert tap lands on the dashboard
/// with the named Activity's card visible; any other tap just opens the app.
@MainActor
final class PushRouter: ObservableObject {
    static let shared = PushRouter()

    /// The Activity to bring into view; the dashboard consumes (nils) it.
    @Published var focusActivityId: String?

    /// Reads the detector payload — custom keys sit at the ROOT of userInfo
    /// beside "aps", not nested.
    func handle(userInfo: [AnyHashable: Any]) {
        guard userInfo["type"] as? String == "perfectWindow",
              let activityId = userInfo["activityId"] as? String else {
            return
        }
        focusActivityId = activityId
    }
}
