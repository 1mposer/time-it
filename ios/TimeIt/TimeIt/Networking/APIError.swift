import Foundation

/// Maps the backend's status codes (CLAUDE.md error table) to client errors.
/// 502 is transient (upstream weather provider) — retry framing; 500 is a
/// server defect and must surface differently; 400 is a validation rejection
/// (should be unreachable — the editor mirrors ADR-0005 — but surfaced
/// non-crashingly as the #5b §7 backstop).
enum APIError: Error, Equatable {
    /// 502 — upstream weather provider failed. Transient.
    case providerUnavailable
    /// 400 — the server rejected the request body (atomic validation).
    case validationRejected(message: String)
    /// 500 or any other unexpected non-2xx status.
    case serverError(statusCode: Int)
    /// Decoding failure or a non-HTTP response.
    case invalidResponse

    var userMessage: String {
        switch self {
        case .providerUnavailable:
            return "Weather data is temporarily unavailable. Try again in a moment."
        case .validationRejected(let message):
            return message
        case .serverError:
            return "Something went wrong on the server."
        case .invalidResponse:
            return "Received an unexpected response from the server."
        }
    }

    /// True when retrying is likely to help (provider hiccup, not a defect).
    var isTransient: Bool {
        self == .providerUnavailable
    }
}

// MARK: - The 400 backstop (#5b §7)

extension APIError {

    private struct BackendErrorBody: Decodable {
        struct Item: Decodable {
            let path: String?
            let message: String
        }
        let errors: [Item]
    }

    /// Parses the uniform `{ errors: [{ path?, message }] }` envelope
    /// (ADR-0005 §6) and names the offending Activity by mapping the `path`'s
    /// `activities[i]` index to its label. Returns nil when the body doesn't
    /// match the envelope (caller falls back to the generic mapping).
    static func validationRejection(body: Data, activityLabels: [String]) -> APIError? {
        guard let parsed = try? JSONDecoder().decode(BackendErrorBody.self, from: body),
              let first = parsed.errors.first else {
            return nil
        }
        if let path = first.path, let label = activityLabel(fromPath: path, labels: activityLabels) {
            return .validationRejected(message: "\"\(label)\" was rejected by the server: \(first.message)")
        }
        return .validationRejected(message: "The server rejected the request: \(first.message)")
    }

    /// "activities[2].thresholds.temp" → labels[2].
    private static func activityLabel(fromPath path: String, labels: [String]) -> String? {
        guard let open = path.range(of: "activities["),
              let close = path[open.upperBound...].firstIndex(of: "]"),
              let index = Int(path[open.upperBound..<close]),
              labels.indices.contains(index) else {
            return nil
        }
        return labels[index]
    }
}
