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

    /// The activity-icon manifest — derived from the `IconCatalog` tree (the
    /// single source of truth), so the picker, this fallback list, and the
    /// audit preview can never drift. The sentinel stays a *fallback* in
    /// `resolve(_:)` but is not in the pickable set.
    static let activityIconManifest: [String] = IconCatalog.allIcons
}
#Preview("Icon manifest") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 24) {
            ForEach(ActivityIconView.activityIconManifest, id: \.self) { name in
                VStack(spacing: 6) {
                    ActivityIconView(identifier: name, size: 28)
                    Text(name)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding()
    }
}
