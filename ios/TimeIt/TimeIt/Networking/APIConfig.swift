import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:3000")!
    #else
    // The live Railway deployment — only Release builds dial this.
    static let baseURL = URL(string: "https://time-it-production.up.railway.app")!
    #endif

    static let ratingPath = "/api/v1/rating"
    static let devicesPath = "/api/v1/devices"
    static let feedbackPath = "/api/v1/feedback"
}
