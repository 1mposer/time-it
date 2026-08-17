import Foundation

/// The devices-route client (`PUT`/`DELETE /api/v1/devices/:deviceId`).
/// Success is `204` (no body) — nothing to decode; non-OK statuses map like
/// APIClient's (502 = provider failure, anything else a server error).
actor DevicesClient: DeviceSnapshotSending {
    static let shared = DevicesClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func putSnapshot(deviceId: String, body: DeviceSnapshotBody) async throws {
        var request = URLRequest(url: Self.url(for: deviceId))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    func deleteDevice(deviceId: String) async throws {
        var request = URLRequest(url: Self.url(for: deviceId))
        request.httpMethod = "DELETE"
        let (_, response) = try await session.data(for: request)
        try Self.check(response)
    }

    private static func url(for deviceId: String) -> URL {
        APIConfig.baseURL.appendingPathComponent("\(APIConfig.devicesPath)/\(deviceId)")
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            return
        case 502:
            throw APIError.providerUnavailable
        default:
            throw APIError.serverError(statusCode: http.statusCode)
        }
    }
}
