import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:3000")!
    #else
    // The live Railway deployment (#6b, verified 2026-07-20). Debug builds
    // keep talking to the local backend above; only Release dials this.
    static let baseURL = URL(string: "https://time-it-production.up.railway.app")!
    #endif

    static let ratingPath = "/api/v1/rating"
    static let devicesPath = "/api/v1/devices"
}
