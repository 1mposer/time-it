# Implementation spec — Issue #5c: Location onboarding (worldwide) — delete the Dubai fallback

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — see **Active location**.
> Design decisions: [`design-decisions-issue-5.md`](design-decisions-issue-5.md) · visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md).
> Depends on: [#5b](implement-spec-issue-5b-ios-personalization.md) (built — `PreferencesStore`, home-location picker, `GeocodingProviding` seam) and [#6b](implement-spec-issue-6b-railway-deploy.md) (live URL, so onboarding is tested against production).
> Required by: [#6c](implement-spec-issue-6c-registration-and-digest.md) — push registration **requires a real location**; this issue is how a user gets one.

This spec is self-contained. All client-side; the backend is untouched. **TDD required** — keep every #5a/#5b test green.

---

## Context

The app ships to the **worldwide** App Store (UAE-first marketing, not UAE-only product). #5a's **silent Dubai fallback is deleted** (grill 2026-07-16): a user in Toronto who hasn't granted location must never see Dubai weather presented as theirs. With no location, the dashboard shows an honest empty state instead of fabricated data.

**Decisions made (do not relitigate):**
- **Active location chain:** home (picked city) → live GPS fix → **last resolved location** (new persisted cache) → **none** → grayed empty state. The Dubai coordinate constant is deleted from the resolution path.
- **Empty state:** activity cards render grayed/skeleton (unrendered data) with kind copy and two CTAs — **"Enable location"** (fires the iOS location-permission prompt) and **"Place your own location"** (city picker sheet).
- **City picker:** MapKit city search behind the **existing** `GeocodingProviding` seam (`geocode(_ query:) async throws -> [SavedLocation]`, `Services/Geocoding.swift` — audited 2026-07-16): add an `MKLocalSearch`-backed conformer and call it **debounced as-you-type** (no Search button). Do **not** reach for `MKLocalSearchCompleter` — it is delegate-driven (streams incremental results) and cannot conform to the one-shot seam; the debounced one-shot gives the same worldwide-autocomplete UX without breaking the seam or its test injection. No API key, no bundled country/city dataset. Picking a city sets `PreferencesStore.homeLocation` — the same store #5b built; #6c later reuses it for registration.
- **Permission-status seam (new work item):** `LocationProviding` today exposes only `location`/`locationPublisher`/`requestLocation()` (audited) — it cannot distinguish *not-yet-asked* from *denied*. Extend it with `authorizationStatus` (+ a change signal) so the "Enable location" CTA can prompt in the first case and deep-link to system Settings in the second.
- **Last resolved location:** whenever a rating request succeeds, persist the coordinates it used (+ display name if known). On later launches with no home and no GPS, rate against this cache — real data the user has seen before, clearly labelled with the location name in the header.

---

## 1. What changes in the shipped code

- **`ViewModels/DashboardViewModel.swift`** — coordinate resolution becomes the Active-location chain above: `resolveCoordinate()` (today non-optional, ending in the Dubai constant) becomes **optional-returning**, and `loadForecast()` skips the POST on nil and raises a new no-location signal. **Shape warning (audited 2026-07-16):** the VM has *no state enum* — it is discrete `@Published` flags (`forecast`/`isLoading`/`errorMessage`…) with an if/else ladder in `DashboardView`, and today's `!hasActivities` empty state means "no activities", **not** "no location". Model no-location as its own flag/branch **beside** that state — they are different screens ("no activities" → add-card CTA; "no location" → grayed cards + the two location CTAs). On successful fetch, write the used coordinate to `PreferencesStore.lastResolvedLocation`.
- **`Services/PreferencesStore.swift`** — add `lastResolvedLocation: SavedLocation?` (persisted like `homeLocation`). Clearing home does **not** clear it.
- **`Views/DashboardView.swift`** — new `.noLocation` empty state: the card list renders as grayed skeleton cards (no values), plus the two CTAs. "Enable location" requests When-In-Use authorization (and deep-links to system Settings if previously denied); "Place your own location" presents the city-picker sheet.
- **New: city-picker sheet** — search field that calls the `GeocodingProviding` seam **debounced as-you-type** through a new `MKLocalSearch`-backed conformer (results filtered to localities), tap a result → save as `homeLocation`. Reachable from the empty-state CTA **and** from the existing Settings home-location row, which upgrades from the #5b free-text-plus-Search-button flow to this as-you-type UI (the manual Search button is removed — see the XCUI re-record note in §2). Mock-injected in tests exactly as the `CLGeocoderService` conformer is today.
- **Delete** the Dubai fallback constant and its silent-substitution branch. **Add** a header location label — net-new plumbing (audited: the #5a header renders only time + current-hour weather, and `DashboardView` passes it just `currentHour`): thread the Active location's display name through and render it (picked city name, "Current location", or the cached name).

---

## 2. Tests

- Unit: resolution-chain precedence (home > GPS > lastResolved > none), lastResolved persistence write-on-success, nil chain → no POST + no-location signal (never coordinates).
- **Existing-test reconciliation (mandatory — audited 2026-07-16):** the old suite was written *around* Dubai, so "keep everything green" needs surgery, not preservation: (a) **replace** `testFallsBackToDubaiWhenLocationNil` (it asserts the deleted behaviour, pinning `25.1627`) with the nil-chain → no-location test above; (b) the XCUI `StaticLocationProvider` returns `nil` — which used to silently become Dubai and feed every card/header assertion — so add a **`UITEST_LOCATION`** launch arg making the mock provider return a fixed coordinate, keeping the existing card/header XCUI tests fed; (c) **re-record** `testHomeLocationPersistsAcrossRelaunchAndClears` — it taps `settings.searchButton`, which the as-you-type upgrade removes.
- XCUI (new): fresh install + no location → grayed cards + both CTAs visible; picking a city via the mock-seamed search renders real cards; relaunch with cached lastResolved renders data with the cached label.

---

## 3. Acceptance criteria

- [ ] Fresh install, location denied: grayed skeleton cards + "Enable location" + "Place your own location"; **no weather data shown**.
- [ ] "Place your own location" → worldwide city search → picking a city loads that city's ratings and persists as home.
- [ ] "Enable location" → iOS prompt → grant → dashboard rates the GPS fix (existing #5b re-rate path).
- [ ] With home cleared and GPS unavailable, a previously successful location still renders (last-resolved cache) with its name in the header.
- [ ] The Dubai constant no longer exists in the resolution path.
- [ ] Full iOS suite green — #5a/#5b tests preserved **except** the Dubai-fallback assertions, which are *replaced* per §2 (never silently deleted), and the re-recorded Settings search XCUI test.

---

## Related artifacts

- [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) — push registration requires a real location; no fallback-location pushes.
- [#5b spec §5](implement-spec-issue-5b-ios-personalization.md) — the home-location store/seam this issue extends.
