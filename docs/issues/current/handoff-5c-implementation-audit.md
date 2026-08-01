# Handoff — #5c implementation, for owner audit

**Date:** 2026-08-01
**Commit under audit:** `0db0c99` on `main` (14 files, +797/−173) — **not pushed**; push is the
owner's call after this audit.
**Spec:** [`implement-spec-issue-5c-location-onboarding.md`](implement-spec-issue-5c-location-onboarding.md)
**Design source:** the four approved Figma frames — Light `172:492` (Dashboard / No Location),
`172:1266` (City Picker); Dark `173:996`, `173:1295`.

---

## 1. What changed, per file

### Behavior core
- **`ViewModels/DashboardViewModel.swift`** — the Dubai constant (old lines 16/143) is deleted.
  `resolveCoordinate()` became `resolveActiveLocation() -> ActiveLocation?` — the chain is
  **home → live GPS fix → last-resolved cache → nil**. On nil: no POST, `hasNoLocation = true`
  (a new flag *beside* `!hasActivities` — different screens), `activeLocationName = nil`.
  On success: `preferences.lastResolvedLocation` is written (only when changed, and only by the
  newest in-flight generation — a home cleared mid-flight can't resurrect itself into the cache).
  `activeLocationName` drives the header label: picked city name / `"Current location"` /
  cached name (empty cached name → `"Last known location"`); it is also seeded synchronously in
  `init` so launch doesn't flash "NO LOCATION" before the first load.
  The late-GPS-fix sink changed in two load-bearing ways:
  - `.dropFirst().compactMap { $0 }` — dropFirst eats exactly the subscription replay (the
    `@Published`/`CurrentValueSubject` seed); the order matters — the reverse would swallow the
    first real fix whenever the replay was nil (the fresh-install case, acceptance §3.3).
  - a **nil `lastFetchedCoordinate` now counts as a meaningful move** — the first granted fix
    triggers the first load instead of being discarded.
  New authorization sink: `removeDuplicates().dropFirst()` (this exact order dedupes
  CLLocationManager's guaranteed initial no-change callback against the replayed seed) →
  a genuine grant calls `requestLocation()`, whose fix then flows through the location sink.
  `preferences` is now `let` (non-private) so the dashboard's picker sheet writes to the same
  store the requests resolve from.
- **`Services/LocationManager.swift`** — `LocationProviding` gains `authorizationStatus` +
  `authorizationPublisher`. Implemented via `locationManagerDidChangeAuthorization` with the
  status captured nonisolated and hopped to the main actor; initial value read synchronously in
  `init` from the instance property.
- **`Services/PreferencesStore.swift`** — new `lastResolvedLocation: SavedLocation?` persisted
  under `lastResolvedLocationKey`, same JSON mechanism as home. Clearing home does NOT clear it.
  `SavedLocation` gains optional `region` (`nil` default → pre-#5c persisted data still decodes;
  a migration test pins this).
- **`Services/Geocoding.swift`** — `CLGeocoderService` (unused after the Settings upgrade) is
  replaced by `MapKitGeocoderService`: `MKLocalSearch` with `resultTypes = .address`, filtered
  to results carrying a `locality`, named `placemark.name ?? locality` (keeps "Dubai Marina"
  honest instead of flattening to "Dubai"), deduped by name+region,
  `MKError.placemarkNotFound → []`. `GeocoderFactory.makeDefault()` centralizes the
  mock-vs-real choice previously private to SettingsView. **Not MKLocalSearchCompleter** — spec
  forbids it (delegate-driven, can't conform to the one-shot seam).

### UI
- **`Views/DashboardView.swift`** — new `noLocationState` branch (after `!hasActivities`, before
  `isLoading` in the ladder): two grayed skeleton cards (55% opacity, flat `timelineTrack`
  shapes mirroring the card anatomy, identifiers `skeletonCard.0/1`), `location.slash` 44pt,
  title/subtitle copy verbatim from the Figma frame, capsule **Enable Location** (prompts, or
  deep-links to `UIApplication.openSettingsURLString` when `locationPermissionDenied`), text CTA
  **Place your own location** → city-picker sheet.
- **`Views/CityPickerView.swift` (new)** — "Set Location" sheet; as-you-type search debounced
  300 ms via `.task(id: query)` (auto-cancel per keystroke); rows show city left / region right;
  tap → `preferences.homeLocation = place` → dismiss (the #5b home-change sink refetches);
  distinct messages for "no results" vs "search failed" (connectivity). Footnote text from Figma.
- **`Views/SettingsView.swift`** — the #5b free-text + Search-button row is replaced by a
  "Set home location" row presenting the same picker (`settings.setHome`); "Use current
  location" clear button kept. The Location footnote no longer mentions Dubai.
- **`Views/HeaderView.swift`** — new location line above the time: SF Pro Medium 11, tracking
  1.4, white 85%, uppercased (exact values read from the Figma Header component). New
  `showsWeather` flag hides temp + wind/humidity in the no-location state (per the approved
  frame — no placeholder weather for a location that doesn't exist).
- **`Views/Theme.swift`** — one addition: `accentInteractive` `#007AFF` (Semantic
  `accent/interactive`).

### Test plumbing
- **`App/TimeItApp.swift`** — `UITEST_RESET` now wipes the third key
  (`lastResolvedLocationKey`); new `UITEST_LOCATION` arg feeds `StaticLocationProvider` a fixed
  fix (25.2048, 55.2708); without it the provider stays nil → the no-location path.
- **`Networking/MockRatingService.swift`** — `StaticLocationProvider` is now configurable
  (`location:` init; auth status `.authorizedWhenInUse` when seeded, `.notDetermined` when nil).

---

## 2. Test surgery (spec §2 reconciliation — audit checklist)

| Spec item | What was done |
|---|---|
| (a) `testFallsBackToDubaiWhenLocationNil` | **Replaced** by `testNoLocationAnywhereSkipsPostAndRaisesSignal` (no POST, `hasNoLocation`, nil name, `requestLocation` still fired) |
| (a′) `testLateGpsFixTriggersRefetchWhenFirstLoadUsedTheFallback` | **Replaced** by `testFirstFixAfterNoLocationLoadTriggersTheFirstFetch` (fetchCount 0 → first fix → POST at the fix) |
| (a′) `testGpsFixNearTheFetchedCoordinateDoesNotRefetch` | **Rewritten**: first load now rates a seeded real fix; same-place fix still doesn't refetch |
| (b) `UITEST_LOCATION` | Added to the default `launchApp` args, both persistence-test relaunches, and `testServerFailureShowsErrorState` (that one was initially missed — caught in review, see §3) |
| (c) `testHomeLocationPersistsAcrossRelaunchAndClears` | Re-recorded via `settings.setHome` + the shared `pickCity` helper; no `settings.searchButton` reference remains |
| (d) `UITEST_RESET` | Wipes `lastResolvedLocationKey` (fresh-install test depends on it) |

**New unit tests:** chain precedence (GPS>cached, cached-feeds-fetch, plus header-name asserts on
the existing home>GPS test), write-on-success / not-on-failure / GPS-writes-empty-name
persistence, authorization-grant-warms-a-fix, PreferencesStore cache persist/restore +
clear-home-keeps-cache + pre-#5c decode migration.
**New XCUI tests:** fresh install → skeletons + CTAs + "NO LOCATION" + no fabricated temp;
place-a-city → cards render + "DUBAI MARINA" header; cached relaunch with home cleared and no
GPS → cards + cached label.

---

## 3. Review cycle (three independent subagents, all findings resolved)

Two confirmed defects, both fixed before commit:
1. `testServerFailureShowsErrorState` lacked `UITEST_LOCATION` — would have hit the no-location
   state and never reached the failing mock API.
2. `testSuccessfulFetchPersistsTheResolvedLocation` set home *after* VM init — the home-change
   sink's unawaited load superseded the awaited one (generation guard) → flaky nil. Fixed by
   seeding home pre-init (the suite's established pattern); `testHomeLocationWinsOverGPS`
   hardened the same way.

Risks hardened: auth-sink operator order (spurious per-launch GPS spin-up), header
"NO LOCATION" launch flash, neighborhood-name flattening in the geocoder, connectivity vs
no-results messaging, stale `hasNoLocation` in the no-activities branch, dashboard picker
bypassing the injected store, redundant cache rewrites, skeleton identifiers + missing XCUI
skeleton assertion.

One reviewer finding **rejected** after manual verification: a claimed unguarded
`isLoading = false` race — every stale-generation path returns before that line.

---

## 4. Verification

- Unit: **133/133** · XCUI: **17/17** — iPhone 17 simulator (iOS 26.5). Repro:
  ```
  xcodebuild test -project ios/TimeIt/TimeIt.xcodeproj -scheme TimeIt \
    -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:TimeItTests   # unit
  xcodebuild test ... -only-testing:TimeItUITests                                    # XCUI
  ```
- Acceptance §3 items **needing a real-device / manual pass** (hermetically unprovable):
  §3.1/§3.3 the real permission prompt + grant flow and the Settings deep-link after denial;
  §3.2 production `MKLocalSearch` result quality (city vs neighborhood queries, result
  ordering) — the XCUI suite exercises these only through the mock seam.

## 5. Not touched / open

- **WeatherKit agent's files** left unstaged as required: `Models/AuthoredActivity.swift`,
  `TimeIt.xcscheme`, `handoff-weatherkit-provider-abstraction.md`.
- Backend untouched (spec: client-side only). Figma untouched this pass.
- Docs close-out (ROADMAP/STATUS §5 marking #5c built) deliberately **not** written — repo
  convention is to close out after owner confirmation; do it once this audit passes.
