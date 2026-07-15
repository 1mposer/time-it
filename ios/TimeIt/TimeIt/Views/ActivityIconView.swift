import SwiftUI
import UIKit

/// The single icon-rendering seam (#5b §2): every activity and metric glyph
/// draws through here, so a future icon redesign (custom asset-catalog art, or
/// animated icons once the no-package rule is deliberately relaxed) is a
/// one-file change. SF Symbols only for now — identifiers come from the
/// manifest (design-decisions §A/§B); an unknown name falls back to the
/// questionmark.circle guardrail instead of a blank glyph.
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

    /// The activity-icon manifest (design-decisions §A Table A + the guardrail)
    /// — the editor's icon picker reads THIS list, not whatever the current
    /// Templates happen to use. Add to the manifest table first, then here.
    static let activityIconManifest: [String] = [
        "figure.outdoor.cycle",
        "figure.fishing",
        "figure.run", // TODO: verify SF Symbol (⚠︎ in the manifest)
        "moon.stars.fill",
        "questionmark.circle",
    ]
}
