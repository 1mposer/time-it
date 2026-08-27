# Implementation Plan — Activity Editor Wizard Redesign

**Your role:** You are the implementing agent. Execute this plan exactly as specified — every decision below was settled with the project manager and is final. Where the plan is explicit, follow it to the letter; where it is silent, match the codebase's existing conventions (read `CLAUDE.md` and the surrounding Swift files first). Do not substitute components, rename identifiers, change copy strings, or "improve" settled decisions. If you hit a genuine contradiction between this plan and the codebase, stop and report it rather than improvising.

**Audit notice:** Your work will be audited upon completion by a senior developer, section by section against this document — including the §0 constraints, the exact copy strings, the accessibility identifiers, the deletions checklist (§9), the test requirements (§10), and the verification gate below. Unrequested deviations, silent omissions, or skipped tests will be flagged as defects. Leave the working tree building and green.

**Target:** `ios/TimeIt/` (SwiftUI app, iOS 17.0 deployment target).
**Scope:** Replace the single-page `ActivityEditorView` Form with a 4-tab gated wizard. No backend changes, no wire-contract changes, no changes to `AddActivityView`'s template list.
**Verification gate:** `xcodebuild -project ios/TimeIt/TimeIt.xcodeproj -scheme TimeIt -destination 'generic/platform=iOS Simulator' -configuration Debug build` must succeed, unit tests (`TimeItTests`) must pass, and the rewritten UI tests (§10) must pass on an iPhone simulator.

Every decision below was explicitly settled with the PM. Do not substitute alternatives.

---

## 0. Platform constraints (already fact-checked — do not re-litigate)

- **`TabsPickerStyle` is iOS 27+ (beta). DO NOT USE.** Build a custom tab header (§2).
- **`TextFieldLink` is watchOS-only. DO NOT USE.** "Next Step" is a plain `Button`.
- **Native `Slider` cannot render a gradient track.** Build the custom slider in §5.
- `ControlGroupStyle.compactMenu` **is** available (iOS 16.4+) — use it for the threshold-mode menu (§4).

---

## 1. The four tabs

`ActivityEditorView` becomes a wizard with a fixed 4-tab header and a switched content area (plain `switch` on a `@State private var step: Int`; no `TabView`).

| # | Tab | Contents | Complete (→ green) when |
|---|-----|----------|------------------------|
| 0 | **Name & Icon** | Name field + categorized icon browser | trimmed label non-empty **AND** `iconSymbol != "questionmark.circle"` |
| 1 | **Metrics** | Merged metric/threshold rows | ≥1 metric selected **AND** every threshold parses (no build issues attributable to thresholds) |
| 2 | **Range** | From/Until hour wheels, both always visible | `startHour != endHour` **AND** range confirmed (§6) |
| 3 | **Review** | Summary, issues, Save, Delete (edit mode) | `draft.result(against: catalog).activity != nil` |

Existing state model (`ActivityDraft`, `draft.result(against:)`) is reused unchanged except where §4/§6 add fields. Validation stays live — recompute once per render as today.

## 2. Custom tab header (`EditorTabBar` — new view, may live in ActivityEditorView.swift)

- 4 equal-width capsule segments in an `HStack`, labels: `Name`, `Metrics`, `Range`, `Review`.
- **States:** current (accent-filled, `Theme.accentOrange`), complete (`Theme.perfectGreen` tint — green fill or green outline + checkmark, pick one and keep it consistent), incomplete (neutral gray, **never red**), locked (dimmed).
- **Green = live validity**, per the table in §1 — a tab goes green the moment its rule passes and reverts if the user breaks it (e.g. clears the name). Green is never "visited".
- **Gating:** tab *i* is tappable iff tabs `0..<i` are all complete. Backward taps always allowed. Tapping a locked tab does nothing (optional: subtle shake). Edit mode (`isNew == false`, previously saved activity): everything is pre-filled and `window != nil`, so all gates pass immediately and all four tabs are freely tappable.
- Accessibility identifiers: `editor.tab.0` … `editor.tab.3`.

## 3. Tab 0 — Name & Icon

- **Name:** `TextField("Cycling", text: $draft.label)` — the grayed "Cycling" placeholder is the standard placeholder, nothing custom. Keep identifier `editor.name`.
- **Icon browser — data model (new file `Models/IconCatalog.swift`):**

```swift
struct IconCategory: Identifiable {
    let name: String
    var children: [IconCategory]? = nil   // supports future nesting
    var icons: [String] = []
    var id: String { name }
}
```

  One static tree, the **single source of truth** for pickable icons. `ActivityIconView.activityIconManifest` becomes a derived flatten of this tree (recursive: own icons + children's) so resolver fallback, the manifest-audit preview, and the picker can never drift. Adding icons later = appending strings; adding categories = one node.

- **Taxonomy (exact, settled):**
  - **Sports:** figure.outdoor.cycle, figure.run, figure.baseball, figure.basketball, figure.american.football, figure.cricket, figure.golf, figure.rugby, figure.skiing.downhill, figure.skateboarding, figure.tennis, figure.pickleball, soccerball, baseball, tennis.racket
  - **Beach & Water:** figure.surfing, figure.sailing, figure.pool.swim, figure.outdoor.rowing, figure.fishing, figure.volleyball
  - **Wellness:** figure.yoga, figure.mind.and.body, figure.hiking
  - **Night:** moon.stars.fill
- **Removals (settled):** `rugbyball` (not a real SF Symbol) and `questionmark.circle` (now the "no icon chosen" sentinel) are removed from the manifest/tree entirely. No "Games" category.
- **Rendering:** `OutlineGroup(tree, children: \.children)` inside a `List`/scroll section — each node row is the category name with disclosure; when expanded, the category's `icons` render as a `LazyVGrid` (5 columns, the existing 40×40 circle buttons, selected = white glyph on `Theme.accentOrange` circle). Keep per-icon identifier `icon.<symbol>` and `accessibilityLabel(symbol)`.
- **Initial expansion:** the category containing `draft.iconSymbol` starts expanded; from-scratch (sentinel icon) → all collapsed.
- **Legacy icon safety:** if `draft.iconSymbol` is non-sentinel and not in the tree, show it in a small "Current" slot above the tree (selected styling) so editing an activity with an unlisted icon can never lose it. (Replaces today's insert-at-0 behavior.)

## 4. Tab 1 — Metrics (merged thresholds)

One row per `catalog.metrics` descriptor, in catalog order.

- **Collapsed, unselected:** icon + display name (as today). **Tap → selects the metric AND expands the row**, auto-creating a threshold pre-filled from the metric's preset (§5 table) with `required: true`. One tap = a working Must-have threshold, zero typing.
- **Expanded row contains:**
  1. The slider (§5), pre-positioned at the preset.
  2. A **3-way mode control** in a `ControlGroup` styled `.compactMenu` — replaces the required-toggle, Add-threshold, and Remove-threshold rows:
     - **Must-have** → threshold with `required: true`
     - **Nice-to-have** → threshold with `required: false`
     - **Show only** → threshold removed (`draft.removeThreshold`), sliders hidden, metric still selected/displayed
     - Default: Must-have. Identifier: `editor.mode.<key>`.
- **Deselect:** tapping the row header (or its checkmark) of a selected metric deselects and collapses it, discarding its threshold (existing `toggleMetric` semantics).
- **Special rows:** `moon` (displayOnly) — selectable, never expands. `dustAlert` (flag) — expands to the mode menu only (no slider); Must-have/Nice-to-have map to the flag threshold's `required`; Show only removes it.
- Keep row identifier `metric.<key>`.
- **Caption (only text on this tab besides the Did-you-know box):** *"First three metrics show as chips on the card."*
- Legacy state safety: when editing an activity whose selected metric already has a threshold, the row starts expanded-equivalent state consistent with its data (mode menu shows Must-have/Nice-to-have per `required`; Show-only when no threshold).

## 5. Custom gradient slider (new file `Views/ThresholdSlider.swift`)

Custom component (capsule track + circular thumb(s) + `DragGesture`); **no third-party dependency**. Track is a `LinearGradient`; thumbs snap to `MetricRange.step`; tick marks when `step >= 1`, none for rainFall (0.5).

**Catalog additions** (`MetricDescriptor` — defaulted so other call sites don't change):

```swift
enum BoundStyle { case range, maxOnly, minOnly }   // dual-thumb vs single-thumb
enum GradientSemantic { case dangerHigh, dangerLow, dangerBothEnds }
var boundStyle: BoundStyle? = nil        // numeric metrics only
var gradient: GradientSemantic? = nil
var presetMin: Double? = nil
var presetMax: Double? = nil
```

Gradient colors from Theme: dangerHigh = `perfectGreen → accentOrange → badRed` left-to-right; dangerLow = reversed; dangerBothEnds = `badRed → perfectGreen → badRed`.

**Per-metric table (exact values, settled):**

| key | boundStyle | gradient | preset | range/step (existing `MetricRange`, unchanged) |
|---|---|---|---|---|
| temp | range (dual-thumb) | dangerBothEnds | 15–32 | −10…50 / 1 |
| humidity | maxOnly | dangerHigh | ≤ 70 | 0…100 / 5 |
| windSpeed | maxOnly | dangerHigh | ≤ 25 | 0…80 / 1 |
| rainFall | maxOnly | dangerHigh | ≤ 0.2 | 0…20 / 0.5 |
| cloudCover | maxOnly | dangerHigh | ≤ 40 | 0…100 / 5 |
| visibility | minOnly | dangerLow | ≥ 8 | 0…20 / 1 |
| uV | maxOnly | dangerHigh | ≤ 8 | **0…12 / 1** (NOT 1–9 — catalog is source of truth) |

- **Escape hatch (required):** if an existing threshold carries a bound its `boundStyle` doesn't show (e.g. a windSpeed **min** authored pre-redesign), that row renders **dual-thumb** so no data is hidden or lost. A single-thumb slider writes only its own bound and must never null the other bound if one exists (it can't exist on fresh creation, but can on legacy data — the escape hatch covers it).
- **Value label + typing fallback:** current value(s) render as a label ("≤ 25 km/h", "15–32 °C"). **Tapping the label** swaps it for a small numeric `TextField` (exact entry, committed on submit/focus-loss, written back through the existing `minText`/`maxText` draft fields so `parseBound` validation still applies). Reuse identifiers `editor.min.<key>` / `editor.max.<key>` on these fields. This is the **only** keyboard on the tab.
- Slider thumb identifiers: `editor.slider.min.<key>` / `editor.slider.max.<key>` (single-thumb uses whichever bound it edits).
- Slider positions map to the draft via `minText`/`maxText` (write formatted values); this keeps `ActivityDraft`/`ThresholdDraft` unchanged.

## 6. Tab 2 — Range

- **Both hour wheels always visible on entry** (no tap-to-expand): a column — label **From**, wheel under it; label **Until**, wheel under it. `Picker` with `.wheel` style, hours 0–23, labels via `RangeText.hourText` ("12am"…"11pm"). Keep identifiers `editor.startHour` / `editor.endHour`.
- **Night indicator (settled copy):** when `startHour > endHour`, show under the wheels: **`moon.stars` icon + "This is a night activity"** (identifier `editor.nightNote`). Note: icon is `moon.stars`, not `moon.stars.fill`.
- **`startHour == endHour`:** red *"Start and end can't match"*, Next Step disabled.
- **Remove:** the "Overnight — wraps midnight (nocturnal)" hint, the "Same day" hint, and the two-sentence footer.
- **Range confirmation** (`@State private var rangeConfirmed: Bool`): initialized `true` iff the incoming activity already had a window (`existing.window != nil` — pass this fact into the view or expose off the draft init); set `true` by any wheel change, and by the warn-and-proceed path below.
- **The skip warning:** if the user presses Next Step (or taps the Review tab) while the range is valid but unconfirmed (untouched template prefill), the first press shows an inline note under the button — **"Are you sure you want to proceed without adding a range?"** (identifier `editor.rangeWarning`) — and the **second** press proceeds and sets `rangeConfirmed = true`. Any wheel interaction clears the warning.

## 7. Tab 3 — Review

- Compact summary card: icon + name, metric chips with their threshold values (reuse `ThresholdSummary` if it fits, else simple rows: "Temp 15–32 °C · Must-have"), range line ("6am – 10am", or with moon.stars + "night" when wrapped).
- Validation issues list (moves here from the old "Before you can save" section) — red, unchanged content.
- Settled note (always visible): *"You can always change these later by pressing the card in the home screen."*
- **Save Activity** button (bottom primary button on this tab, replaces "Next Step"): enabled iff `buildResult.activity != nil`; calls `onSave` + dismiss exactly as today. Keep identifier `editor.save`. **Remove Save from the toolbar** — toolbar keeps Cancel only (`editor.cancel`).
- **Delete** (edit mode only, `!isNew && onDelete != nil`): destructive button + existing confirmation dialog, identifiers `editor.delete` / `editor.confirmDelete` unchanged.

## 8. Bottom button + copy system

- One primary button pinned at the bottom of every tab: **"Next Step"** on tabs 0–2 (identifier `editor.nextStep`), **"Save Activity"** on tab 3. Next Step is disabled (dimmed) while the current tab is incomplete — except the tab-2 warning path (§6) where it stays enabled to drive warn-then-proceed.
- **Per-tab captions — max one line each** (settled): tab 0 none; tab 1 the chips caption (§4); tab 2 none beyond the conditional night note; tab 3 the change-later note.
- **`DidYouKnowBox` (new small view):** tinted rounded box, lightbulb icon, "Did you know?" header, bullet body, ✕ button. Dismissal is **permanent** via `@AppStorage("didYouKnow.<key>")`. Exactly two instances:
  - Tab 1, key `metricModes`: "• Must-have: bad weather blocks the day. • Nice-to-have: failing only downgrades Perfect to Good. • Show only: on the card, doesn't affect rating."
  - Tab 2, key `nightRange`: "End before start? That's an overnight range — rated per night, made for stargazing."

## 9. Deletions checklist

From `ActivityEditorView.swift`: the horizontal icon `ScrollView` strip, `thresholdsSection`, `thresholdRows`, `issuesSection` (content moves to Review), `windowHint`, all three section footers, the toolbar Save. From `ActivityIconView.swift`: the hardcoded manifest array (now derived from `IconCatalog`), and its entries `rugbyball` + `questionmark.circle` (sentinel stays as *fallback* in `resolve(_:)` — only removed from the *pickable* set). `AddActivityView` and `ActivityDraft`'s public API stay untouched (additive changes only).

## 10. Tests

**Unit tests (add `TimeItTests` coverage):** IconCatalog flatten = manifest (no rugbyball, no questionmark.circle, all symbols resolvable via `UIImage(systemName:)`); per-tab completion rules (name/icon gate incl. sentinel, metrics gate, range gate incl. `rangeConfirmed` seeding from existing window); preset table → threshold values; mode-menu mapping (Must-have/Nice-to-have/Show-only ↔ `required`/threshold-removal); escape-hatch detection (legacy bound outside boundStyle → dual-thumb).

**UI tests (`TimeItUITests.swift`) — these WILL break and must be rewritten, not deleted:**
- From-scratch creation test: now taps an icon (`icon.<symbol>`) on tab 0 (icon is gated-required), navigates via `editor.nextStep`, taps `metric.temp` (auto-preset — the old `editor.addThreshold.temp` flow is gone), optionally exercises the tap-label-to-type path via `editor.min.temp`, handles the range-warning double-press on tab 2, saves via `editor.save` on Review.
- Template test: `template.running` → all tabs green/unlocked → jump to Review → save.
- Delete tests: navigate to the Review tab before asserting `editor.delete`.
- Remove assertions referencing `editor.addThreshold.*` and the absent `editor.windowToggle`.
- New assertions worth adding: locked-tab no-op (tap `editor.tab.3` from an empty scratch draft → still on tab 0), `editor.rangeWarning` appears once then proceeds, `editor.nightNote` when From > Until.

**Previews:** update `ActivityEditorView`'s `#Preview` set — "New (scratch)", "New (template)", "Edit (existing)" via `PreviewFixtures`; add previews for `ThresholdSlider` (all three gradients) and `DidYouKnowBox`.

## 11. Suggested commit sequence

1. `IconCatalog` + derived manifest + icon removals (+ unit tests).
2. `ThresholdSlider` + `MetricDescriptor` additions + per-metric table (+ unit tests, previews).
3. Wizard shell: `EditorTabBar`, step switching, gating, bottom button, `DidYouKnowBox`.
4. Tab contents wired (0–3) + deletions checklist.
5. UI-test rewrite + full verification gate.

## 12. Explicit non-goals

No changes to: backend or wire shapes, `AddActivityView`, `ActivityStore`, seed template values, `RangeText`, dashboard/detail views, the `moon`/`dustAlert` catalog semantics. No third-party packages. No `TabView(.page)` swiping between steps (gating makes swipe semantics ambiguous — switch-only).
