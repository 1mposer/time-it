import XCTest
@testable import TimeIt

/// Pins the wizard ✕ (fresh-eyes row 13a, owner 2026-11-12): a stock
/// confirmation only when the draft changed — "Discard this activity?" for a
/// new one, "Discard changes?" for an edit; a clean draft closes at once.
final class EditorDismissTests: XCTestCase {

    private let catalog = StaticMetricCatalog()

    /// The editor's opening snapshot: the draft after the show-only adoption.
    private func opened(_ activity: AuthoredActivity) -> ActivityDraft {
        var draft = ActivityDraft(from: activity)
        draft.adoptShowOnlyMetrics(catalog: catalog)
        return draft
    }

    func testCleanDraftDismissesWithoutDialog() {
        let new = opened(.blank())
        XCTAssertNil(EditorDismiss.confirmationTitle(isNew: true, initial: new, current: new))
        let edit = opened(Fixtures.liveSeeds[0])
        XCTAssertNil(EditorDismiss.confirmationTitle(isNew: false, initial: edit, current: edit))
    }

    func testDirtyDraftAsksToDiscard() {
        let new = opened(.blank())
        var typed = new
        typed.label = "Padel"
        XCTAssertEqual(EditorDismiss.confirmationTitle(isNew: true, initial: new, current: typed),
                       "Discard this activity?")

        let edit = opened(Fixtures.liveSeeds[0])
        var moved = edit
        moved.endHour = (edit.endHour + 1) % 24
        XCTAssertEqual(EditorDismiss.confirmationTitle(isNew: false, initial: edit, current: moved),
                       "Discard changes?")
    }

    func testUndoingAChangeMakesTheDraftCleanAgain() {
        let edit = opened(Fixtures.liveSeeds[0])
        var draft = edit
        draft.label = "Cycling!"
        draft.label = edit.label
        XCTAssertNil(EditorDismiss.confirmationTitle(isNew: false, initial: edit, current: draft),
                     "dirty means different from the opening draft, not touched")
    }
}
