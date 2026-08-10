# Code Review — `issue-5b-authoring` → `main`

> ✅ **RESOLVED** — all 7 findings triaged and fixed on `issue-5b-authoring` the same day (2026-07-15); the #5b spec banner records it. Historical record.

**Date:** 2026-07-15
**Scope:** `git diff main...issue-5b-authoring` (local branch diff, not a GitHub PR). 36 files changed, all iOS/Swift — the backend engine is untouched by this branch.
**Method:** 7 parallel finder passes (line-by-line scan, removed-behavior audit, cross-file tracer, reuse, simplification, efficiency, altitude/conventions) against the diff, each candidate re-verified by reading the current source directly. Judged from code and diff alone.

**Summary of the change:** adds client-side activity authoring to the iOS app — `ActivityDraft`/`AuthoredActivity` models, a `MetricCatalogProviding` seam (`StaticMetricCatalog`), local persistence via `ActivityStore`, the `ActivityEditorView`/`AddActivityView` authoring UI, and a client-side mirror of the backend's ADR-0005 request validation.

---

## Findings (most severe first)

### 1. `ActivityStore.add()` silently no-ops at the soft cap; the caller always dismisses as if it succeeded
**File:** `ios/TimeIt/TimeIt/Services/ActivityStore.swift:34-38`, `ios/TimeIt/TimeIt/Views/AddActivityView.swift:50-53`

```swift
func add(_ activity: AuthoredActivity) {
    guard !isAtCap else { return }   // no error, no return value
    activities.append(activity)
    persist()
}
```

`AddActivityView`'s `onSave` calls `store.add(activity)` then unconditionally `dismiss()`s. The only real gate today is the ghost add-card's `.disabled(store.isAtCap)` in `DashboardView.swift` — a *pre-check* on opening the Add sheet, not a save-time check.

**Failure scenario:** on iPadOS multi-window (two scenes sharing the same `ActivityStore.shared`), a user opens the Add sheet under the cap in one window, the cap is reached via the other window, then Save is tapped in the first window — the new activity is silently dropped and the sheet closes as if it saved successfully, with zero user-facing error.

---

### 2. The ADR-0005 validation mirror doesn't check that a threshold's shape (flag vs numeric) matches the metric's actual kind
**File:** `ios/TimeIt/TimeIt/Models/AuthoredActivity.swift:100-109`

```swift
if catalog.descriptor(for: metric)?.isThresholdable == false {
    issues.append("\(metric) can be shown but not thresholded")
    continue
}
if threshold.isFlag {
    if threshold.forbidTrue != true {
        issues.append("\(metric): a flag threshold must forbid the alert")
    }
} else { ... }
```

`isThresholdable` is only `false` for `displayOnly` metrics (e.g. `moon`) — it never confirms a `.flag`-shaped threshold is applied to a `.flag`-kind metric. The same gap exists server-side: `src/routes/validateRatingRequest.js`'s `validateThreshold` returns early on `config.type === 'flag'` without checking which metric it's attached to. Traced through `src/decision/decision_engine.js`'s `checkThreshold`: a flag-shaped threshold (`type:"flag"`, no min/max) on a numeric metric like `temp` never fails, regardless of the actual temperature — a silently-always-Perfect threshold. This is exactly the "false-Perfect" class of bug the mirror's own comment (lines 101-104) claims to block.

**Failure scenario:** not reachable through the shipped editor UI (`ActivityDraft.addThreshold` always sets `isFlag` from the correct descriptor kind), but reachable via a corrupted/hand-edited persisted `UserDefaults` blob — `ActivityStore.load()` decodes with no cross-field consistency check, so a malformed `AuthoredActivity` with a flag threshold on `temp` would pass client validation, get POSTed, and silently never fail that threshold.

---

### 3. Clearing the home location doesn't actually fall back to a live GPS fix, contradicting the code's own comment
**File:** `ios/TimeIt/TimeIt/ViewModels/DashboardViewModel.swift:87-114`

```swift
// Warm the GPS fix on every load (even while a home location covers
// this fetch) so clearing the home falls back to a real fix, not Dubai.
locationProvider.requestLocation()
let coordinate = resolveCoordinate()   // reads locationProvider.location synchronously
```

`requestLocation()` is async (delegate-driven, `location` is `@Published` on `LocationManager`), but `resolveCoordinate()` reads the cached value synchronously right after. Nothing in `DashboardViewModel` subscribes to `locationProvider.location` to retry once a fix lands.

**Failure scenario:** on the first load after clearing the home location (or before any prior fix has been cached — e.g. permission was just granted), the request hasn't resolved yet, so the app falls back to the hardcoded Dubai coordinate anyway — not "a real fix" as the comment promises — and nothing re-triggers `loadForecast()` when the real fix arrives later.

---

### 4. Two independently-maintained, already-diverging metric name tables
**Files:** `ios/TimeIt/TimeIt/Models/MetricCatalog.swift` (`StaticMetricCatalog.all`) vs `ios/TimeIt/TimeIt/Models/HourlyWeather.swift:68-81`

| key | `HourlyWeather.label(for:)` | `MetricDescriptor.displayName` |
|---|---|---|
| `windSpeed` | "Wind" | "Wind Speed" |
| `rainFall` | "Rain" | "Rainfall" |
| `moon` | "Moon" | "Moon Phase" |
| `dustAlert` | "Dust" | "Dust Alert" |

The card's chip accessibility label uses the former; the editor/add-flow metric picker uses the latter. Same metric, different displayed name depending on screen, with no test tying the two tables together.

---

### 5. `chipIcon(for:)` instantiates `StaticMetricCatalog()` directly instead of using the injected `MetricCatalogProviding`
**File:** `ios/TimeIt/TimeIt/Views/ActivityCardView.swift:104-106`

```swift
static func chipIcon(for metric: String) -> String {
    StaticMetricCatalog().descriptor(for: metric)?.iconSymbol ?? "questionmark.circle"
}
```

`MetricCatalog.swift:40-42`'s own doc comment calls `MetricCatalogProviding` a seam "so the static catalog can be replaced by a network-backed conformer with zero call-site changes." This is the one call site that doesn't honor that — it would need a manual edit when `RemoteMetricCatalog` (ADR-0006) ships.

---

### 6. `ActivityEditorView.iconChoices` derives the icon picker from `SeedTemplates.all` rather than a dedicated icon manifest
**File:** `ios/TimeIt/TimeIt/Views/ActivityEditorView.swift:21-28`

Conflates "valid activity icons" with "whichever icons the current Templates happen to use" — an icon not used by any Template has no way into the picker except adding a throwaway Template. This is the same "second hardcoded list drifts silently" shape the branch explicitly avoided for metric icons via the catalog-backed `chipIcon` lookup (see #5).

---

### 7. `ActivityStore.move(fromOffsets:toOffset:)` is fully implemented and persists, but has zero UI call sites
**File:** `ios/TimeIt/TimeIt/Services/ActivityStore.swift:51-54`

Grepped the whole app target: no `.onMove`, no `EditButton`, nothing wires drag-reorder anywhere in `DashboardView` or elsewhere — only `ActivityStoreTests.swift` calls `move()` directly. Dead public API that must be carried through future `ActivityStore` refactors for no shipped feature.

---

## Checked and refuted

- **`ActivityCardView`'s nocturnal timeline axis widening (`axisRange`) extrapolating one hour past the last forecast hour** — not a bug. `endIndex` is contractually exclusive (`src/decision/decision_engine.js`'s `findLongestWindow` sets `endIndex = i + 1`), so `hourLabel(at: endIndex)` correctly shows the window's end **boundary** clock time, not a data lookup — this is the intended half-open display, not an off-by-one.
- **`APIClient`'s 400-handling possibly misattributing a non-ADR-0005 400 body as a validation rejection** — refuted; every 400 in this system is contractually the same `{ errors: [...] }` envelope per `CLAUDE.md`'s error table, so `APIError.validationRejection(body:)` parsing any 400 body against that shape is correct, not an assumption.
- **Unconditional `locationProvider.requestLocation()` on every `loadForecast()` call being wasteful** — deliberate, documented design (see finding #3's context), not an oversight.

---

## Not flagged (lower-value, noted for completeness)

- `ActivityEditorView.windowHint` re-derives the same three-way window-validity branch (`startHour == endHour` / `>` / else) that `AuthoredActivity.validationIssues` already computes, with separately-worded text — cosmetic duplication, could drift.
- `DashboardViewModel.authoredActivity(forActivityId:)` / `iconSymbol(forActivityId:)` / `isNocturnal(activityId:)` are three near-identical linear scans over `store.activities` — fine at the current 10-item soft cap, would want consolidating if that cap ever rises.
- `ActivityEditorView`'s `isNew: Bool` parameter is 100%-correlated with `onDelete != nil` at both call sites — could be derived instead of passed, removing one parameter callers must keep consistent.
