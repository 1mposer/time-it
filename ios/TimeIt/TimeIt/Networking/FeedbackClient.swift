import Foundation

/// Body of the beta suggestion POST — all five fields required by the route;
/// `build` is `CFBundleVersion`.
struct FeedbackBody: Encodable, Equatable {
    let deviceId: String
    let message: String
    let appVersion: String
    let build: String
    let iosVersion: String
}

/// The feedback-route client (`POST /api/v1/feedback`). Success is `204` —
/// nothing to decode; a 429 is the per-device throttle, any other non-2xx a
/// server error. No 502 mapping — the route never touches the provider.
actor FeedbackClient: SuggestionSending {
    static let shared = FeedbackClient()

    /// Worst-case duration of the sheet's sending state — dismiss is disabled
    /// mid-send, so the 60s URLSession default would lock the sheet.
    static let requestTimeout: TimeInterval = 15

    /// Internal (not private) so the seam tests can pin the configuration.
    let session: URLSession

    init(session: URLSession? = nil) {
        self.session = session ?? Self.makeDefaultSession()
    }

    /// This client's own configured session — the timeout cap is deliberately
    /// not global to the other clients.
    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = requestTimeout
        return URLSession(configuration: configuration)
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
