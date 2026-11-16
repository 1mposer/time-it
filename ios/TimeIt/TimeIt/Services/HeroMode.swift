import Foundation

/// The detail hero's two faces (lane RETHINK): Report (default) and
/// Explore, remembered per Activity in `PreferencesStore`.

enum HeroMode: String, Codable, Equatable {
    case report, explore
}
