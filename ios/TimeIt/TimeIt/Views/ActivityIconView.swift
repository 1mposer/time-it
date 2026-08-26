import SwiftUI
import UIKit

/// The single icon-rendering seam: every activity and metric glyph draws
/// through here, so an icon redesign is a one-file change. SF Symbols only;
/// an unknown name falls back to questionmark.circle instead of a blank glyph.
struct ActivityIconView: View {
    let identifier: String
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: Self.resolve(identifier))
            .font(.system(size: size))
    }

    /// Runtime guardrail: a symbol name missing from the OS (typo, or newer
    /// than iOS 17) renders as the fallback, never blank.
    static func resolve(_ identifier: String) -> String {
        UIImage(systemName: identifier) != nil ? identifier : "questionmark.circle"
    }

    /// The activity-icon manifest — the editor's icon picker reads this list,
    /// not whatever the current Templates happen to use.
    static let activityIconManifest: [String] = [
        "figure.outdoor.cycle",
        "figure.fishing",
        "figure.run", // TODO: verify this SF Symbol exists
        "moon.stars.fill",
        "questionmark.circle",
    ]
}
