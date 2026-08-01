# Handoff — #5c audit findings, for the implementing agent

**Date:** 2026-08-01
**Audited commits:** `0db0c99` (feat, 14 files, +797/−173) + `ec4230d` (docs handoff) on `main` — still **not pushed**.
**Audit method:** two-axis review (Standards vs Spec) via independent subagents over
`git diff 0db0c99^...ec4230d`, followed by manual re-verification of every load-bearing claim
against the code. Your implementation handoff (`handoff-5c-implementation-audit.md`) was checked
claim-by-claim and is now superseded by this document.

**Verdict: solid work, not yet pushable.** Nothing in your handoff was false — every code-level
claim checked out, down to line numbers and the diff stat. But the audit found one finding that
undermines the spec's core flow (F1), two quick design-guideline breaches (F2, F3), and a
handful of smaller items. Fix F1–F3 before push; the rest are your call / follow-ups.

---

## 1. Must fix before push

### F1 — The "Enable Location" CTA never gets to fire the permission prompt *(spec-defeating)*

Spec §1: *"'Enable location' (fires the iOS location-permission prompt)"* — the CTA is supposed
to be the onboarding trigger.

Actual behavior: `loadForecast()` calls `locationProvider.requestLocation()` **unconditionally,
before** the nil-chain guard (`DashboardViewModel.swift:206`, guard at `:208`), and
`LocationManager.requestLocation()` calls `manager.requestWhenInUseAuthorization()`
(`LocationManager.swift:52`). So on a fresh install the system prompt fires **at launch**,
before the user has ever seen the empty state. By the time the CTA is visible, the prompt has
already been answered — the CTA's prompt branch is effectively unreachable, and the CTA-driven
onboarding the spec designed doesn't exist in practice.

This predates #5c (the launch-time `requestLocation()` was already there), but #5c is the
location-onboarding issue, so it lands on this commit. Likely fix shape: split "request a fix"
from "request authorization" on `LocationProviding` — `loadForecast()` should only ask for a fix
when status is already granted; only the CTA (via `requestLocationAccess()`) triggers
`requestWhenInUseAuthorization()`. Re-check the auth-grant sink (`DashboardViewModel.swift:136-143`)
still warms the first fix afterwards — that path becomes the *only* road from grant to first load.

### F2 — CTA touch targets below the 44pt minimum

`ios/guidelines/Guidelines.md:155`: *"All interactive elements have a minimum 44×44pt touch
target."* In `DashboardView.swift`'s `noLocationState`:
- the **Enable Location** capsule ≈ 33pt tall (15pt font + 9pt vertical padding);
- the **Place your own location** text button ≈ 18pt.

Neither has a `.frame(minHeight: 44)` / `.contentShape` compensation. Bump both.

### F3 — `Theme.accentInteractive` `#007AFF` contradicts the declared source of truth

`Theme.swift`'s own header names `ios/guidelines/Guidelines.md` "the visual source of truth",
but Guidelines.md has no `#007aff` token — its button/accent color is **`#ff9500` orange**
(Guidelines.md:17: "Active tab, buttons, Good window highlight, PRO badge"). The new token
(`Theme.swift:23`) invents an undocumented color and paints the CTA blue where the guide assigns
buttons orange. Either switch the CTA to `accentOrange`, or — if the blue genuinely comes from
the approved Figma frames — add the token to Guidelines.md so the source of truth stays true.
Do not leave the contradiction standing silently.

---

## 2. Should fix (follow-up acceptable, note in STATUS if deferred)

### F4 — City search admits street addresses

Spec §1 asked for *"results filtered to localities"*. `Geocoding.swift` uses
`resultTypes = .address` + `guard let locality`, then names rows `placemark.name ?? locality`.
Street-level placemarks also carry a `locality`, so "123 Main St" rows can surface, and the
name+region dedup won't collapse them into their city. Consider dropping results whose
`placemark.name` differs from `locality` when a `thoroughfare`/`subThoroughfare` is present, or
equivalent — keep the "Dubai Marina" neighborhood case working (it was deliberately preserved).

### F5 — `.restricted` is routed to a dead end

`DashboardViewModel.swift:169-172` treats `.restricted` like `.denied`, so the CTA deep-links a
restricted user (parental controls / MDM — cannot toggle the switch) into Settings. Low
frequency, but the honest UX is distinct copy (or no Settings link) for `.restricted`.

### F6 — Coverage gaps around the denied path

- The denied → Settings deep-link branch (`DashboardView.swift:189-199`) has **zero** automated
  coverage; your handoff correctly flagged it manual-only. After F1 restructures this area, add
  at least a unit test that a denied status routes `requestLocationAccess()` to the
  open-Settings path rather than the prompt path.
- Acceptance §3.1 says *"Fresh install, location **denied**"*, but the XCUI fresh-install test
  runs `.notDetermined` (nil `StaticLocationProvider`). Add a `UITEST_LOCATION_DENIED`-style
  variant, or amend the spec's acceptance wording to match what's provable hermetically.

---

## 3. Handoff-claim corrections (your `handoff-5c-implementation-audit.md`)

Every substantive claim was independently verified. **False claims: zero** — including the
Dubai-constant deletion (repo-wide grep clean), the sink operator-order reasoning, the full
test-surgery table, and your §3 rejected-finding rebuttal (confirmed: all three post-await paths
guard-return at `DashboardViewModel.swift:227/236/240` before `isLoading = false`). Three claims
were **overstated** — recalibrate these if you re-document:

1. *"a home cleared mid-flight can't resurrect itself into the cache"* — too strong. The
   generation guard (`:227`) precedes the cache write, but clearing home only **schedules**
   `Task { loadForecast() }`; `loadGeneration` doesn't increment until that task runs. If load
   A's continuation is dequeued on the main actor before the superseding task starts, A still
   writes the cleared home. Narrow window, and your own §3.2 flaky-test post-mortem describes
   exactly this scheduling gap. Either bump the generation inside the sink (before scheduling)
   to make the claim true, or soften the claim.
2. *"fresh install → … no fabricated temp"* — the assertion is
   `XCTAssertFalse(app.staticTexts["24°C"].exists)`, one literal mock-fixture string. The
   `showsWeather` flag does remove the whole row, but the test is weaker than the claim;
   asserting on the header's weather-group identifier would match the wording.
3. The handoff presents the CTA as the prompt trigger and never mentions the launch-time prompt
   (F1). Fixing F1 makes the description true.

Unverifiable but consistent (no action): the 133/133 · 17/17 run (method counts at `0db0c99`
match exactly: 133 unit `func test`s, 17 XCUI); all Figma-fidelity claims (no artifact in-repo);
the §3 subagent process history.

---

## 4. Judgement-call cleanups (optional, batch with any of the above)

- **Duplicated mock-run detection** — `arguments.contains("UITEST_MOCK_SUCCESS") || …FAILURE`
  lives in both `TimeItApp.makeViewModel()` and `GeocoderFactory.makeDefault()`
  (`Geocoding.swift:58`). Extract one "is this a mock run?" helper.
- **Empty-string sentinel** — a GPS fix persists as `SavedLocation(name: "", …)` and
  `displayName` special-cases `saved.name.isEmpty ? "Last known location"`
  (`DashboardViewModel.swift:68, 79`). An optional `name` (or a `.gps` case) would be honest.
- **Flag pair** — `CityPickerView`'s `searchFailed` + `searchErrored` are mutually exclusive
  bools reset in triplets; a single `enum SearchOutcome { idle, empty, errored }` is the state
  machine that's actually there.
- **Middle man (mild)** — `SettingsView` holds `geocoder: GeocodingProviding?` solely to forward
  it to `CityPickerView` (`SettingsView.swift:10, 53`).
- **Fragile row identity** — `ForEach(Array(results.enumerated()), id: \.offset)`
  (`CityPickerView.swift:50`) keys by position while results churn per keystroke. Mirrors the
  deleted #5b pattern, so convention-consistent — but the smell moved rather than died.
- Trivial: CTA copy "Enable Location" vs CONTEXT.md's "Enable location" capitalization.

---

## 5. Confirmed clean (no action — recorded so it isn't re-litigated)

- Active-location chain matches CONTEXT.md verbatim: home → GPS → last-resolved → none; no
  fabricated coordinate anywhere; nil → no POST + `hasNoLocation` + nil header name.
- Domain language, ADR-0005 request shape, and the API contract surface untouched.
- `SavedLocation.region` optional with nil default; pre-#5c persisted data decodes (migration
  test exists and pins it). Clearing home keeps the last-resolved cache.
- Both sink operator orders (`dropFirst().compactMap`; `removeDuplicates().dropFirst()`) are
  correct for the stated replay/no-change-callback reasons.
- XCUI suite stays hermetic; `UITEST_RESET` wipes all three keys; `UITEST_LOCATION` present in
  every launch that needs it, including `testServerFailureShowsErrorState`.
- Scope creep (`region` field, `showsWeather`, auth-grant auto-warm, `GeocoderFactory`,
  connectivity-vs-no-results copy) reviewed and **accepted** — all purpose-aligned.
- WeatherKit agent's files (`AuthoredActivity.swift`, `TimeIt.xcscheme`, its handoff) untouched
  by both commits, as required.

---

## 6. Process

1. Fix **F1, F2, F3** (and pick up any §4 items you touch in passing). F1 changes behavior —
   update the affected unit tests and your handoff's CTA description together.
2. Re-run both suites; a fresh-install XCUI pass must show the empty state **without** the
   system prompt having fired (F1's observable acceptance).
3. F4–F6: fix now or log as explicit follow-ups in STATUS §5 — silent deferral is what this
   audit exists to prevent.
4. Amend `0db0c99`/`ec4230d` or stack a fix commit — owner's preference is a fix commit so the
   audit trail (this file) stays anchored to the audited hashes.
5. Docs close-out (ROADMAP/STATUS marking #5c built) stays **blocked** until the fixes land and
   the owner confirms — same convention your handoff already honored. Do not push until then.
