import Foundation
import UIKit

/// Feedback-route seam (`POST /api/v1/feedback`).
protocol SuggestionSending {
    func send(_ body: FeedbackBody) async throws
}

/// State machine for the feedback sheet (either kind). The one hard rule: a
/// typed note is never discarded — any non-204 keeps `message` intact and
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

    /// The note above the editor — the owner's line, the same on both sheets
    /// (ruling 2026-11-11).
    static let note = "Please explain what it is you like, dislike, or would suggest."

    @Published var message = ""
    @Published private(set) var phase: Phase = .editing
    @Published private(set) var errorMessage: String?

    let kind: FeedbackKind
    private let sender: SuggestionSending
    private let deviceId: String
    private let appVersion: String
    private let build: String
    private let iosVersion: String

    /// `deviceId` is the same Keychain install UUID the push path uses (push
    /// opt-in is NOT required); passed in from the caller's DeviceRegistration
    /// so UI tests stay on the seamed Keychain.
    init(kind: FeedbackKind = .suggestion,
         sender: SuggestionSending,
         deviceId: String,
         appVersion: String? = nil,
         build: String? = nil,
         iosVersion: String? = nil) {
        self.kind = kind
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
                                               iosVersion: iosVersion,
                                               kind: kind))
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
        return "Couldn't send. Check your connection and try again."
    }
}

extension FeedbackKind {
    /// The sheet title — the ⓘ menu row that opened it.
    var title: String {
        switch self {
        case .suggestion: return "Send a suggestion"
        case .liked: return "What have you liked?"
        }
    }

    /// The editor's placeholder.
    var placeholder: String {
        switch self {
        case .suggestion: return "Type your suggestion…"
        case .liked: return "Type what you liked…"
        }
    }

    /// The ⓘ menu row's SF Symbol.
    var symbol: String {
        switch self {
        case .suggestion: return "lightbulb"
        case .liked: return "heart"
        }
    }
}
