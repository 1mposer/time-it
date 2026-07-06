import Foundation

enum APIConfig {
    #if DEBUG
    static let baseURL = URL(string: "http://localhost:3000")!
    #else
    // TODO(#6): replace with the Railway HTTPS URL when the backend deploys.
    static let baseURL = URL(string: "https://timeit-production.up.railway.app")!
    #endif

    static let ratingPath = "/api/v1/rating"
}
