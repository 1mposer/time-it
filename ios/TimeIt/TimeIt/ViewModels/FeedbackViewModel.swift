import Foundation
import UIKit

/// Feedback-route seam (`POST /api/v1/feedback`).
protocol SuggestionSending {
    func send(_ body: FeedbackBody) async throws
}

/// State machine for the suggestion sheet. The one hard rule: a typed
/// suggestion is never discarded — any non-204 keeps `message` intact and
/// surfaces a retryable error (429 gets the throttle copy); success shows a
/// brief confirmation, then the view dismisses.
@MainActor
final class FeedbackViewModel: ObservableObject {

    /// Client mirror of the route's message cap — drives the counter and
    /// Send gate; the server stays authoritative (ADR-0007).
    static let messageLimit = 1000

    enum Phase: Equatable {
        case editing
        case sending
        case sent
    }

    @Published var message = ""
    @Published private(set) var phase: Phase = .editing
    @Published private(set) var errorMessage: String?

    private let sender: SuggestionSending
    private let deviceId: String
    private let appVersion: String
    private let build: String
    private let iosVersion: String

    /// `deviceId` is the same Keychain install UUID the push path uses (push
    /// opt-in is NOT required); passed in from the caller's DeviceRegistration
    /// so UI tests stay on the seamed Keychain.
    init(sender: SuggestionSending,
         deviceId: String,
         appVersion: String? = nil,
         build: String? = nil,
         iosVersion: String? = nil) {
        self.sender = sender
        self.deviceId = deviceId
        self.appVersion = appVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        self.build = build
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.iosVersion = iosVersion ?? UIDevice.current.systemVersion
    }

    /// Send gating mirrors the route's message rules: non-empty after
    /// trimming (whitespace-only is a 400) and within the mirrored cap.
    var canSend: Bool {
        phase == .editing
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && message.count <= Self.messageLimit
    }

    var isOverLimit: Bool {
        message.count > Self.messageLimit
    }

    func send() async {
        guard canSend else { return }
        phase = .sending
        errorMessage = nil
        do {
            try await sender.send(FeedbackBody(deviceId: deviceId,
                                               message: message,
                                               appVersion: appVersion,
                                               build: build,
                                               iosVersion: iosVersion))
            phase = .sent
        } catch {
            // Non-204: text stays put, Send remains the retry.
            phase = .editing
            errorMessage = Self.errorCopy(for: error)
        }
    }

    private static func errorCopy(for error: Error) -> String {
        if case APIError.serverError(let status) = error, status == 429 {
            // Mirrors the route's own 429 message.
            return "Too many suggestions today — try again tomorrow."
        }
        return "Couldn't send your suggestion. Check your connection and try again."
    }
}
