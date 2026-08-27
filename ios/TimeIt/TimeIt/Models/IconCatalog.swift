import Foundation

/// One node of the icon browser's category tree. `children` supports future
/// nesting; today the tree is one level of categories.
struct IconCategory: Identifiable {
    let name: String
    var children: [IconCategory]? = nil
    var icons: [String] = []
    var id: String { name }
}

/// The single source of truth for pickable activity icons (settled taxonomy).
/// `ActivityIconView.activityIconManifest` is a derived flatten of this tree,
/// so the resolver fallback, the manifest-audit preview, and the picker can
/// never drift. Adding icons later = appending strings; adding categories =
/// one node. `rugbyball` (not a real SF Symbol) and `questionmark.circle`
/// (the "no icon chosen" sentinel) are deliberately absent.
enum IconCatalog {

    static let tree: [IconCategory] = [
        IconCategory(name: "Sports", icons: [
            "figure.outdoor.cycle", "figure.run", "figure.baseball", "figure.basketball",
            "figure.american.football", "figure.cricket", "figure.golf", "figure.rugby",
            "figure.skiing.downhill", "figure.skateboarding", "figure.tennis",
            "figure.pickleball", "soccerball", "baseball", "tennis.racket",
        ]),
        IconCategory(name: "Beach & Water", icons: [
            "figure.surfing", "figure.sailing", "figure.pool.swim",
            "figure.outdoor.rowing", "figure.fishing", "figure.volleyball",
        ]),
        IconCategory(name: "Wellness", icons: [
            "figure.yoga", "figure.mind.and.body", "figure.hiking",
        ]),
        IconCategory(name: "Night", icons: [
            "moon.stars.fill",
        ]),
    ]

    /// Every pickable icon, in tree order.
    static let allIcons: [String] = flatten(tree)

    /// Recursive flatten: a node's own icons, then its children's.
    static func flatten(_ nodes: [IconCategory]) -> [String] {
        nodes.flatMap { node in
            node.icons + flatten(node.children ?? [])
        }
    }

    /// The category whose subtree contains `icon` — drives the browser's
    /// initial expansion. nil for the sentinel or an unlisted legacy icon.
    static func category(containing icon: String) -> IconCategory? {
        tree.first { contains(icon, in: $0) }
    }

    private static func contains(_ icon: String, in node: IconCategory) -> Bool {
        node.icons.contains(icon) || (node.children ?? []).contains { contains(icon, in: $0) }
    }
}
