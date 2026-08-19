import Foundation

/// Body of the beta suggestion POST — all five fields required by the route
/// (beta-feedback spec §2); `build` is `CFBundleVersion`, so every stored
/// suggestion reads in the context of the exact build that produced it.
struct FeedbackBody: Encodable, Equatable {
    let deviceId: String
    let message: String
    let appVersion: String
    let build: String
    let iosVersion: String
}

/// The feedback-route client (`POST /api/v1/feedback`). Success is `204`
/// (no body) — nothing to decode. The route never touches the weather
/// provider, so there is no 502 mapping here: a 429 is the per-device
/// throttle (20 per rolling 24h) and any other non-2xx is a server error.
actor FeedbackClient: SuggestionSending {
    static let shared = FeedbackClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ body: FeedbackBody) async throws {
        var request = URLRequest(url: APIConfig.baseURL.appendingPathComponent(APIConfig.feedbackPath))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.serverError(statusCode: http.statusCode)
        }
    }
}
