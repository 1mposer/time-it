import Foundation

/// Maps the backend's status codes (CLAUDE.md error table) to client errors.
/// 502 is transient (upstream weather provider) — retry framing; 500 is a
/// server defect and must surface differently.
enum APIError: Error, Equatable {
    /// 502 — upstream weather provider failed. Transient.
    case providerUnavailable
    /// 500 or any other unexpected non-2xx status.
    case serverError(statusCode: Int)
    /// Decoding failure or a non-HTTP response.
    case invalidResponse

    var userMessage: String {
        switch self {
        case .providerUnavailable:
            return "Weather data is temporarily unavailable. Try again in a moment."
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
