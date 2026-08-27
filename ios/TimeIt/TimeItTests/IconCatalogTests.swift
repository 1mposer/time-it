import XCTest
import UIKit
@testable import TimeIt

/// Pins the icon taxonomy tree as the single source of truth for pickable
/// icons: the manifest is a derived flatten, so the resolver fallback, the
/// manifest-audit preview, and the picker can never drift.
final class IconCatalogTests: XCTestCase {

    func testManifestIsExactlyTheTreeFlatten() {
        XCTAssertEqual(ActivityIconView.activityIconManifest, IconCatalog.allIcons,
                       "the manifest must be derived from the tree — a second list would drift")
    }

    func testRemovedIconsAreNotPickable() {
        XCTAssertFalse(IconCatalog.allIcons.contains("rugbyball"),
                       "rugbyball is not a real SF Symbol — removed (settled)")
        XCTAssertFalse(IconCatalog.allIcons.contains("questionmark.circle"),
                       "questionmark.circle is the no-icon-chosen sentinel, never pickable")
    }

    func testSentinelStaysAsResolverFallback() {
        XCTAssertEqual(ActivityIconView.resolve("not.a.real.symbol"), "questionmark.circle",
                       "the sentinel is removed from the pickable set only, not from resolve(_:)")
    }

    func testEverySymbolInTheTreeResolves() {
        for symbol in IconCatalog.allIcons {
            XCTAssertNotNil(UIImage(systemName: symbol),
                            "\(symbol) is not a resolvable SF Symbol on this OS")
        }
    }

    func testSettledTaxonomy() {
        XCTAssertEqual(IconCatalog.tree.map(\.name), ["Sports", "Beach & Water", "Wellness", "Night"])

        func icons(_ name: String) -> [String] {
            IconCatalog.tree.first { $0.name == name }?.icons ?? []
        }
        XCTAssertEqual(icons("Sports"),
                       ["figure.outdoor.cycle", "figure.run", "figure.baseball", "figure.basketball",
                        "figure.american.football", "figure.cricket", "figure.golf", "figure.rugby",
                        "figure.skiing.downhill", "figure.skateboarding", "figure.tennis",
                        "figure.pickleball", "soccerball", "baseball", "tennis.racket"])
        XCTAssertEqual(icons("Beach & Water"),
                       ["figure.surfing", "figure.sailing", "figure.pool.swim",
                        "figure.outdoor.rowing", "figure.fishing", "figure.volleyball"])
        XCTAssertEqual(icons("Wellness"), ["figure.yoga", "figure.mind.and.body", "figure.hiking"])
        XCTAssertEqual(icons("Night"), ["moon.stars.fill"])
    }

    func testCategoryContainingFindsTheIconsCategory() {
        XCTAssertEqual(IconCatalog.category(containing: "figure.fishing")?.name, "Beach & Water")
        XCTAssertEqual(IconCatalog.category(containing: "moon.stars.fill")?.name, "Night")
        XCTAssertNil(IconCatalog.category(containing: "questionmark.circle"),
                     "the sentinel belongs to no category — from-scratch starts all-collapsed")
        XCTAssertNil(IconCatalog.category(containing: "star.circle"),
                     "an unlisted legacy icon has no category — it renders in the Current slot")
    }

    func testFlattenRecursesIntoChildren() {
        // The tree supports future nesting — a child category's icons must
        // flatten in too, or a nested icon would vanish from the manifest.
        let nested = IconCategory(name: "Parent",
                                  children: [IconCategory(name: "Child", icons: ["figure.run"])],
                                  icons: ["soccerball"])
        XCTAssertEqual(IconCatalog.flatten([nested]), ["soccerball", "figure.run"])
    }
}
