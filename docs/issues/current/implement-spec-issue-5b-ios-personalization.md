# Implementation spec — Issue #5b: Activity authoring & personalization

> Build the **authoring layer** on top of the #5a core read-only dashboard: the user can **add, edit, and delete** their own Activities (from a Template or from scratch), choose **display metrics**, set **Thresholds** and an optional time-of-day **Window**, set a **home location**, and have all of it **persist** locally across launches. The dashboard stops POSTing a hardcoded two-Template constant and instead POSTs the user's **persisted, mutable Activity list**. The backend is unchanged — it is activity-agnostic ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)) and already accepts any valid `{ lat, lon, activities[] }` body ([ADR-0005](../../adr/0005-custom-activity-request-schema.md)); **all of #5b is client-side.**

> Design decisions: [`design-decisions-issue-5.md`](design-decisions-issue-5.md) — the shared visual/UX + nav reference (ghost add-card, card gear = authoring editor, no PRO badge, no `-pro` variants). Read it for colour/typography/layout.
> Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md) — canonical for layout, colour, typography. Extend the SF Symbols manifest for any new Template icons; **never invent a symbol name** (blank-glyph failure — use `questionmark.circle` + a `// TODO: verify SF Symbol` and flag it).
> HIG reference: the **`apple-hig`** skill (`.claude/skills/apple-hig/`) — consult it for forms, lists, pickers, sheets, swipe actions, and text-field behaviour. Obey the same two hard constraints as #5a: **iOS 17+ only** (no post-17 APIs/symbols — they render blank or fail to compile) and **do not bulk-load the HIG corpus** (tiered routing per `SKILL.md`; pull `text-fields`, `pickers`, `lists-and-tables`, `sheets`, `steppers`, `onboarding`/`launching` on demand).
> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md) — re-read **Activity**, **Threshold**, **Window**, **Display metrics**, and **Lite / Pro** (metric-access + quantity, client-enforced) before starting.
> Authoritative wire shape: [`CLAUDE.md`](../../../CLAUDE.md) "API response contract" + [ADR-0005](../../adr/0005-custom-activity-request-schema.md) (request) + [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md) (response).
> Depends on: **Issue #5a — `time-it/ios/TimeIt/` must exist and build/test cleanly** (62 tests green) before starting. This spec modifies the shipped #5a code in place.
> Required by: Issue #6 (deploy + APNs).

**TDD required.** Write all tests before any implementation. Run red first, implement until green. Keep every #5a test green — this is additive, not a rewrite.

---

## Scope — LOCKED (owner-confirmed 2026-07-12)

Three scoping calls were settled with the owner. They are **decided, not open** — build to them.

1. **Metric picker — client-side static catalog now, with a clean upgrade seam to `GET /api/v1/metrics` later. ✅ DECIDED.**
   The server catalog route (`GET /api/v1/metrics`) is **unbuilt and unpinned** (needs an ADR-0006 that is deliberately not yet written — STATUS §5). Ship a **client-side static metric catalog** (a hand-maintained mirror of the LIVE set in `src/weather/metricCatalog.js`). **Design it behind a `MetricCatalogProviding` seam so the static source can be swapped for the network route with no call-site changes** (owner's ask: allow later evolution). See §4 — the seam is a hard requirement, not a nicety. Mitigation for client/server drift: only LIVE metrics are ever offered, so a POST can never 400 on an unknown metric.

2. **Pro tier / StoreKit — DEFERRED. ✅ DECIDED.**
   Per `CONTEXT.md:72`, Pro = **metric-access + quantity** gating, but every LIVE metric is currently free and the premium metrics (Douglas scale, swell — Issue #7) are **coming-soon** and already hard-400'd — so metric-access has nothing live to gate, leaving only quantity, which does not justify the full StoreKit 2 surface. **Do not build StoreKit/paywall/entitlements in #5b.** Apply a **soft quantity cap** (a plain constant, no purchase) so the authoring UX is complete. §8 retains the full Pro spec for a later wave (revisit once Issue #7 lands a real premium metric); it is **out of scope** here.

3. **Persistence — local only, no cloud sync. ✅ DECIDED.**
   The iCloud/anon-device **sync** model is explicitly **undesigned** (STATUS §5, grill PENDING #1). Persist locally only (§3). **Do not** build CloudKit/iCloud sync in #5b — a future issue owns cross-device sync.

**Net build:** full authoring + local persistence + client-side metric picker (swappable seam) + soft quantity cap; **no StoreKit.**

---

## Context

#5a shipped a **read-only** dashboard: it POSTs a hardcoded constant of two seed Templates (`SeedTemplates.all`, immutable, passed into `DashboardViewModel`) and renders one card per returned Activity. There is **no way for the user to change what Activities exist.** #5b makes the Activity list the user's own: **create/edit/delete**, backed by **local persistence**, seeded on first launch with the same two Templates so the first run is identical to today.

Everything is client-side. The backend already evaluates whatever valid Activities it receives ([ADR-0002](../../adr/0002-activity-agnostic-engine.md)); the client's new job is to **author valid bodies** and **never POST an invalid one** — because validation is **atomic** ([ADR-0005](../../adr/0005-custom-activity-request-schema.md) §6), a single bad Activity 400s the **whole request** and the entire dashboard fails to render. The editor therefore mirrors the ADR-0005 rules client-side (§7) so a malformed Activity can never be saved, let alone sent.

**Not in this spec** (deferred, with rationale in "Scoping recommendations"): StoreKit/Pro purchase (§8, deferred), cloud/iCloud sync, the server `GET /api/v1/metrics` route, and any accounts/sign-in (cut permanently, [ADR-0001](../../adr/0001-no-accounts-guest-first.md)).

---

## Architecture additions

Additive to the #5a MVVM structure. No third-party packages. iOS 17+, SwiftUI.

- **`ActivityStore`** (`@MainActor`, `ObservableObject`, shared singleton, `Services/`) — the single source of truth for the user's authored Activity list. Owns an ordered `[AuthoredActivity]`, seeds the two Templates on first launch, exposes create/update/delete/reorder, and **persists on every mutation** (§3). Replaces the immutable `SeedTemplates.all` constant as the dashboard's activity source.
- **`AuthoredActivity`** (`Models/`) — the client-side authored model (the editable superset). Carries UI metadata (icon symbol, template origin) plus the wire fields. It **projects to `ActivityInput`** (the existing #5a `Encodable`) at POST time. See §2.
- **`MetricCatalog`** (client-side, `Models/` or `Services/`) — the static list of selectable LIVE metrics with display label, unit, chip icon, value kind (numeric vs flag), and a `pro` flag (for later tier gating). Drives the metric picker and threshold editor. See §4.
- **`PreferencesStore`** (`@MainActor`, `ObservableObject`, shared singleton, `Services/`) — owns `homeLocation: SavedLocation?` (and, if Pro is built, `isPro`). Persists locally. `DashboardViewModel.loadForecast()` uses `homeLocation` coords when set, GPS otherwise. See §5.
- **`DashboardViewModel`** — modified to read its activity list from `ActivityStore` (not the seed constant) and its coords from `PreferencesStore.homeLocation` (falling back to GPS, then Dubai). See §6.
- **New Views**: the ghost **add-card** (dashboard), **`AddActivityView`** (Template chooser / from-scratch), **`ActivityEditorView`** (label + icon + metric picker + threshold editor + optional window), reached for **create** (from add flow) and **edit** (from the card gear). **`SettingsView`** grows a home-location picker. See §5–§6.
- **No `AuthManager`, `AppState`, `OnboardingView`, Keychain, `ProPaywallView` (unless Pro is flipped on), `-pro`/`isPro` activity variants, or PRO badge** — these are all from the deleted pre-rebuild model. Do not resurrect them.

Xcode groups unchanged (`App/`, `Models/`, `Services/`, `ViewModels/`, `Views/`, `Networking/`). New tests in `TimeItTests/` and `TimeItUITests/`.

---

## 1. What changes in the shipped #5a code

Concrete deltas to existing files (do not break #5a behaviour or tests):

- **`Models/SeedTemplates.swift`** — repurpose from "the app's fixed activity list" into a **Template catalog**: the curated starting points a user can add from. Keep the two existing Templates (`cycling`, `fishing-lite`) and add a few more curated ones (§4.1). Each Template is now a *starting point for authoring*, not the shipped list. `SeedTemplates.all` is used only to (a) seed `ActivityStore` on first launch and (b) populate the "Add from Template" list.
- **`ViewModels/DashboardViewModel.swift`** — stop taking `activities: [ActivityInput] = SeedTemplates.all`; instead observe `ActivityStore.shared` for the current list and project each `AuthoredActivity` to `ActivityInput` at POST time. Resolve coords via `PreferencesStore.homeLocation` → GPS → Dubai.
- **`Views/DashboardView.swift`** — append the ghost **add-card** after the card list; add a **card gear** tap target that opens `ActivityEditorView` for that Activity (the #5a card gear was stubbed/omitted). Card list is now driven by `ActivityStore`, still rendered in request order (which equals store order).
- **`Views/ActivityCardView.swift`** — wire the previously-stubbed gear (`ActivityCardView.swift:46`) to an **edit** action; add a **delete** affordance (swipe action or a control in the editor). Still **no PRO badge, no `-pro` logic** (design-decisions Q3).
- **`Views/SettingsView.swift`** — add a **Home location** section (picker: search city → geocode, or "Use current location"). Keep About. No Pro row unless §8 is flipped on.
- **`Networking/RatingRequest.swift`** — `ActivityInput` / `Threshold` gain the ability to encode an optional **`window`** (`{ startHour, endHour }`, integers 0–23, omitted when absent) — #5a deliberately never sent one. Everything else is unchanged.
- **`Services/TimeDeriver.swift`** (+ `ActivityCardView` day label + `ActivityDetailView` day headers) — **implement nocturnal day labels.** #5a's `dayName(forDayIndex:)` hardcodes `0 → "Today"`, `1 → "Tomorrow"`, else weekday, and was **never exercised for a nocturnal activity** (both seeds are diurnal). Per [ADR-0004](../../adr/0004-day-bucketed-rating-wire-shape.md) §51, a nocturnal (wrapped-window) activity's `dayIndex` is the **evening's** ordinal, so `0` must read **"Tonight"**, `1` **"Tomorrow night"**, else the **weekday + "night"** (e.g. "Friday night"). The label helper therefore needs to know whether the activity being labelled is nocturnal (has a wrapped `window`) — thread that in from the card/detail. Once #5b lets users author a wrapped window, this path is live; verify and implement it rather than assuming #5a covers it. Diurnal labels are unchanged.

---

## 2. Data model: `AuthoredActivity`

A `Codable`, `Identifiable`, value-type model — the editable source of truth for one user Activity. Fields:

- `id: String` — client-authored, **stable for the life of the Activity**, and **unique within the POST body** (echoed back as `activityId`, [ADR-0005](../../adr/0005-custom-activity-request-schema.md) §2). Generate a UUID string on create; never mutate it on edit.
- `label: String` — non-empty, user-supplied.
- `iconSymbol: String` — an SF Symbol name from the manifest (chosen from Template, or picked in the editor). Falls back to `questionmark.circle` if unknown.
- `templateOrigin: String?` — the `id` of the Template this was created from (`nil` for from-scratch). Metadata only; not sent to the server.
- `displayMetrics: [String]` — ordered render superset; each entry is a LIVE metric key. Non-empty.
- `thresholds: [String: Threshold]` — the evaluated subset; **`thresholds.keys ⊆ displayMetrics`**. May be empty (show-but-don't-judge is legal — a metric can be displayed without a threshold).
- `window: WindowSpec?` — optional `{ startHour: Int, endHour: Int }`, both `0…23`, location-local hours, half-open `[startHour, endHour)`. `nil` = whole day. `startHour < endHour` = same-day; `startHour > endHour` = **nocturnal / night-stitch**; `startHour == endHour` is **invalid** (must be rejected in the editor, §7).

**Projection to the wire:** `AuthoredActivity` maps to the existing `ActivityInput` by dropping UI-only fields (`iconSymbol`, `templateOrigin`) and including `window` only when non-nil. `Threshold` is the existing #5a `Encodable` (numeric `{ min?, max?, required }` with ≥1 bound, or flag `{ type:"flag", forbidTrue:true, required }`).

**Icon resolution:** the #5a card derives the icon partly via `label.contains("fishing")`; #5b makes the icon **explicit** (`iconSymbol`). The card should prefer `iconSymbol` and keep the `contains` heuristic only as a legacy fallback.

---

## 3. Persistence (`ActivityStore` + local storage)

**DECIDED (Scoping #3): local persistence only — no cloud sync.**

- **`ActivityStore`** holds `@Published private(set) var activities: [AuthoredActivity]` in store/request order.
- **First-launch seeding:** when no persisted data exists, seed with the two #5a Templates (`cycling`, `fishing-lite`) so the first run matches today's dashboard exactly. Persist immediately so the seed is stable.
- **Mutations:** `add(_:)`, `update(_:)` (matched by `id`), `delete(id:)`, `move(from:to:)` (reorder). Every mutation **persists synchronously** then republishes.
- **Storage mechanism:** encode `[AuthoredActivity]` to JSON and store under a single `UserDefaults` key (e.g. `authoredActivities`). It is a small, bounded list (soft cap §8; hard ceiling ~50 per ADR-0005). *(SwiftData is a valid alternative on iOS 17; UserDefaults+Codable is simpler and sufficient for a single ordered list — prefer it unless the owner wants SwiftData.)*
- **Migration/robustness:** if decode fails (corrupt/older shape), fall back to the seed set rather than crashing; log and re-persist.

---

## 4. Client-side metric catalog (`MetricCatalog`)

**DECIDED (Scoping #1): static client-side catalog now, behind a swap seam for the future `GET /api/v1/metrics` route.**

**Swap seam (hard requirement).** Do not let views read a global constant directly. Define a `MetricCatalogProviding` abstraction (protocol) with a single responsibility: *supply the list of selectable `MetricDescriptor`s.* Ship one conformer now — `StaticMetricCatalog` — holding the constant list below. `ActivityEditorView` / the picker depend on the **protocol**, injected (default = the static conformer), never on the constant. When `GET /api/v1/metrics` lands (ADR-0006, unwritten), a `RemoteMetricCatalog` conformer drops in **with zero call-site changes** — the whole evolution is one new file + one injection point. This is the owner's explicit "allow for evolution later" requirement; treat the seam as non-negotiable even though today there is only one conformer.

The static conformer supplies a constant list describing each **selectable** metric. It must include **only LIVE metrics** — the source of truth is `src/weather/metricCatalog.js` `LIVE_METRICS`. Mirror exactly: `temp`, `humidity`, `windSpeed`, `rainFall`, `cloudCover`, `visibility`, `uV`, `moon`, `dustAlert`. **Do not** offer any coming-soon metric (`darkness`, `douglasScale`, `swellHeight`, `swellLength`, `tide`, `seaWarning`) — the backend hard-400s them, which (atomic) fails the whole dashboard.

Each catalog entry carries:
- `key: String` — the metric key sent on the wire (must match the backend exactly).
- `displayName: String` — human label (e.g. "Wind Speed").
- `unit: String` — for the threshold editor (e.g. "km/h", "°C", "%", "mm").
- `iconSymbol: String` — chip icon from the manifest (design-decisions §B).
- `kind: numeric | flag` — numeric metrics take `min`/`max`; `dustAlert` (and `seaWarning`, once live) is a **flag** (`forbidTrue`). `moon` is a special-case string-array metric — **display-only** in #5b (no threshold UI); include it as displayable but not thresholdable.
- `pro: Bool` — reserved for tier gating (all `false` today; see §8). Present so the picker can grey/lock Pro metrics when Pro ships.
- `range: (min, max, step)?` — sensible slider/stepper bounds for the numeric editor (e.g. temp −10…50 °C step 1). UI hint only; not a validation rule.

Add a `// TODO: RemoteMetricCatalog via GET /api/v1/metrics (pending ADR-0006, unwritten)` marker on the static conformer and a one-line note that the constant list must stay in sync with `metricCatalog.js` until the route lands. The `MetricDescriptor` shape is provider-agnostic so both conformers produce the same type.

> **Rendering is already complete for all 9 LIVE metrics — do NOT restrict the picker to a subset, and do NOT re-derive chip rendering.** The #5a `HourlyWeather.formatted(for:)` + `label(for:)` already handle every LIVE metric (`moon` → first phase label, `dustAlert` → "Dust"/"No dust", nullable trio → `"—"`), `ActivityCardView` has an icon for each, and `MetricTier.tier(for:)` returns **neutral** for metrics with no colour-tier table (`rainFall`, `visibility`, `moon`, `dustAlert`) — those render as valid grey chips. So displaying/thresholding `dustAlert` (a flag) is safe: its chip already renders. Only the five tiered metrics (`temp`, `uV`, `windSpeed`, `humidity`, `cloudCover`) get colour; the rest are intentionally neutral. Verify this holds before relying on it (`HourlyWeather.swift`, `ActivityCardView.swift` `MetricTier`).

### 4.1 Template catalog (expand `SeedTemplates`)

Templates are curated `AuthoredActivity` starting points. Keep the two #5a Templates and add a handful more so "Add from Template" is useful. **Every Template must use only LIVE metrics, satisfy `thresholds.keys ⊆ displayMetrics`, set `required` on every threshold, and be a valid ADR-0005 body** (the `SeedTemplateTests` tripwire, extended). Provisional thresholds are acceptable (mark them) — the exact numbers are still unpinned (STATUS §4). Suggested additions (owner may edit): a diurnal land Activity (e.g. Running / Padel) and a nocturnal one (e.g. Stargazing, `window: { startHour: 22, endHour: 4 }`) to exercise the **night-stitch** path end-to-end. Extend the SF Symbols manifest (design-decisions §A) for any new icon — verified names only.

---

## 5. New & modified views

### `AddActivityView` (new)
Presented from the ghost **add-card** (design-decisions §Interactions). Two paths:
1. **From a Template** — a list of the Template catalog (icon + name + a one-line summary of its metrics). Selecting one opens `ActivityEditorView` **pre-filled** with a *copy* of the Template (new unique `id`, `templateOrigin` set) so the user can tweak before saving.
2. **From scratch** — opens `ActivityEditorView` empty (blank label, no metrics, no thresholds), for a fully custom Activity.

On save, the new `AuthoredActivity` is appended via `ActivityStore.add(_:)` and the dashboard refetches.

### `ActivityEditorView` (new)
The core authoring surface — a `Form`-style sheet used for **both create and edit**. Sections:
- **Name & icon** — a text field for `label` (non-empty) and an icon picker over the manifest's Template icons.
- **Metrics** (the **metric picker**) — multi-select over `MetricCatalog` (LIVE only). Selected metrics become `displayMetrics`, in selection order. A metric marked `pro` is shown locked when Pro is enabled and the user is not Pro (§8); otherwise all selectable.
- **Thresholds** — for each selected **numeric** metric, an optional threshold: `min` and/or `max` (at least one bound if a threshold is added at all), and a **required** toggle. For each selected **flag** metric (`dustAlert`), a "forbid when true" toggle + required. A selected metric with **no** threshold is legal (show-but-don't-judge). Enforce `thresholds.keys ⊆ displayMetrics` structurally (you can only add a threshold for a selected metric).
- **Time window** (optional) — a toggle "Only at certain hours"; when on, two hour pickers (`startHour`, `endHour`, 0–23). Show a live hint: same-day vs **overnight** (wrap) vs the invalid `startHour == endHour` (block save). Off = whole day (`window` omitted).
- **Delete** (edit mode only) — a destructive action that calls `ActivityStore.delete(id:)` and dismisses.

Save is **disabled until the Activity is valid** per §7. On save: create → `add`, edit → `update`. Then the dashboard refetches so ratings reflect the change.

### `DashboardView` (modify)
- Card list driven by `ActivityStore.activities` (still request order).
- Append the **ghost add-card** at the end → presents `AddActivityView`.
- The **card gear** (previously stubbed) → presents `ActivityEditorView` in edit mode for that Activity.
- Optional: swipe-to-delete on a card (in addition to the editor's delete).
- After any store mutation, re-run `loadForecast()` so ratings update.

### `SettingsView` (modify)
Add a **Home location** section:
- Current home location (city name if set, else "Using current location").
- "Set home location" → a search field (city/place) geocoded via `CLGeocoder` to `lat`/`lon`, stored as `SavedLocation` in `PreferencesStore`. Include "Use current location" to clear it (back to GPS).
Keep the About section. **No Pro row / notifications / account** (Pro only if §8 flipped on; notifications are #6c; accounts are cut).

### `ProPaywallView` (deferred — §8 only)
Not built unless Pro is in scope. If built, see §8.

---

## 6. ViewModel changes (`DashboardViewModel`)

- Source the activity list from `ActivityStore.shared.activities`, projecting each to `ActivityInput` for the POST. Preserve request order.
- `loadForecast()` resolves coords as: `PreferencesStore.homeLocation` (if set) → device GPS (`LocationManager`) → Dubai fallback (`25.1627, 55.2077`).
- Re-fetch when the store or home location changes (observe the published values, or expose a `refresh()` the views call after a mutation).
- Keep the #5a helpers (`cardDay`, `windowStartHour`, `windowHours`) unchanged — they operate on the response, which is unaffected.
- **Empty-list state:** if the user deletes their last Activity, the store must not POST an empty `activities[]` (ADR-0005 requires non-empty). Show a friendly empty-dashboard state prompting "Add an activity" (the add-card remains visible), and **skip the POST** until at least one Activity exists.

---

## 7. Client-side validation (mirror ADR-0005 — the atomic-400 guard)

The editor must make it **impossible to save an Activity that would 400**, because one bad Activity 400s the **whole request** (atomic — the entire dashboard fails). Enforce, live, before enabling Save:

- `label` non-empty.
- `id` unique within the store (guaranteed by UUID on create; never mutated on edit).
- `displayMetrics` non-empty; **every metric is a LIVE catalog metric** (unknown/coming-soon impossible because the picker only offers LIVE).
- `thresholds.keys ⊆ displayMetrics` (structural — thresholds only exist for selected metrics).
- Every numeric threshold has **≥1 bound** (`min` and/or `max`) and `min ≤ max` when both present.
- Every threshold has `required` set (a Bool toggle — always present).
- Flag thresholds are `{ type:"flag", forbidTrue:true, required }`; **`requireTrue` is not offered** (rejected by the backend, Issue #8).
- `window`, when present: `startHour` and `endHour` are `0…23` and **`startHour != endHour`** (equal is rejected). Wrap (`startHour > endHour`) is valid (nocturnal).
- Activity count ≤ the soft cap (§8) and always < the ~50 hard ceiling (ADR-0005).

Surface violations inline in the editor (disable Save + show why). Additionally, as a backstop, if a POST ever returns a **400** with a structured `{ errors: [{ path, message }] }`, surface a non-crashing message that names the offending Activity (parse `path` → `activities[i]`). *Full stale-activity reconciliation (auto-detecting a metric that went coming-soon and stripping it) is still undesigned (STATUS §5) and is out of scope — the LIVE-only picker makes this path unreachable for Activities authored in-app.*

---

## 8. Pro tier — DEFERRED (spec retained for a later wave)

**DECIDED (Scoping #2): do NOT build in #5b.** Reason: Pro = metric-access + quantity (`CONTEXT.md:72`), but no LIVE metric is Pro-only today (premium metrics are coming-soon and already 400'd), so only quantity is gateable — too thin to justify StoreKit. Revisit once Issue #7 lands a real premium marine metric.

**Until then — soft quantity cap (in scope):** enforce a plain constant limit on authored Activities (e.g. free tier = a small N), with a friendly "limit reached" message on the add-card. No purchase, no StoreKit, no paywall. This keeps the authoring UX complete and makes turning Pro on later a matter of raising the cap behind an entitlement.

**When Pro is flipped on (future):**
- `PreferencesStore.isPro` derived from **StoreKit 2** `Transaction.currentEntitlements` for a single product (e.g. `com.timeit.app.pro_monthly`); not persisted directly (queried on launch + on transaction updates).
- `MetricCatalog.pro` metrics become locked in the picker for non-Pro users; the quantity cap is raised for Pro.
- **`ProPaywallView`** fetches the StoreKit product (localised name/price), offers purchase + restore; on success `isPro` flips and locks lift. Present it when a non-Pro user taps a locked metric or hits the cap.
- **No `-pro` activity variants, no PRO badge on cards** (design-decisions Q3) — gating is on metrics and count, never on separate Activity copies.

---

## 9. Tests (TDD — write first)

Keep all #5a tests green. Add:

### Unit (`TimeItTests/`)
**`ActivityStoreTests`**
- First-launch seeding produces the two Templates in order; `hasSeeded` prevents re-seeding.
- `add` appends and persists; a fresh store instance `load()`s the same list (round-trip through UserDefaults).
- `update(_:)` replaces by `id` without changing order or `id`; `delete(id:)` removes; `move` reorders and persists.
- Corrupt/undecodable persisted data falls back to the seed set (no crash).

**`AuthoredActivityProjectionTests`**
- Projects to a valid `ActivityInput`: drops `iconSymbol`/`templateOrigin`; includes `window` only when present; omitted otherwise.
- A nocturnal `window` (`startHour > endHour`) encodes both hours; a whole-day Activity omits the key entirely.

**`ActivityValidationTests`** (the atomic-400 guard — the most important suite)
- Empty label → invalid. Empty `displayMetrics` → invalid.
- A threshold key not in `displayMetrics` is structurally impossible (assert the model can't represent it, or the validator rejects it).
- Numeric threshold with no bound → invalid; `min > max` → invalid; both-bounds equal is valid.
- Missing `required` is impossible (always a Bool); flag never emits `requireTrue`.
- `window` with `startHour == endHour` → invalid; wrap window valid; out-of-range hour invalid.
- Only LIVE metrics are selectable (catalog contains no coming-soon key).

**`MetricCatalogTests`** — the `StaticMetricCatalog` keys are exactly the backend LIVE set (pin against the known list; this is the drift tripwire until ADR-0006). No coming-soon key present. Every entry has an icon in the manifest. The picker depends on `MetricCatalogProviding` (protocol), so a test double conformer can be injected — assert the picker renders whatever the provider returns (proves the swap seam works without a live route).

**`SeedTemplateTests`** (extend #5a) — every Template (including new ones) is a valid ADR-0005 body: LIVE-only, subset invariant, unique `id`, `required` on each threshold; any nocturnal Template has a valid wrap `window`.

**`TimeDerivationTests`** (extend #5a) — nocturnal day labels: for a wrapped-window activity, `dayIndex 0` → "Tonight", `1` → "Tomorrow night", else "<Weekday> night" (in the response zone); diurnal labels ("Today"/"Tomorrow"/weekday) unchanged. Guard against device-zone leakage as in #5a.

**`PreferencesStoreTests`** — `homeLocation` persists and restores; clearing returns to nil (GPS). `DashboardViewModel` uses `homeLocation` coords when set, GPS otherwise, Dubai when both absent.

**`DashboardViewModelTests`** (extend) — activity list comes from `ActivityStore`; deleting the last Activity yields the empty state and **no POST**; adding one triggers a refetch.

### Acceptance (`TimeItUITests/`)
- Ghost add-card is visible after the seeded cards; tapping it opens `AddActivityView`.
- Add-from-Template pre-fills the editor; saving adds a new card (count increases, request order preserved).
- Add-from-scratch: entering a label, selecting metrics, adding a threshold, saving → new card appears.
- Save is **disabled** until valid (e.g. empty label or a metric with no bound keeps it disabled).
- Editing an existing card via its gear changes its label/metrics and the card reflects it after refetch.
- Deleting an Activity removes its card; deleting the last one shows the empty state (no crash).
- Setting a home location in Settings persists across an app relaunch.
- **No PRO badge anywhere** (regression guard).
- Persistence: relaunch shows the user's authored list, not the seeds (once modified).

---

## 10. Acceptance criteria

- [ ] Zero build errors and warnings; all #5a tests still green.
- [ ] User can **add** an Activity from a Template and from scratch; it appears as a card in request order.
- [ ] User can **edit** an Activity (label, icon, metrics, thresholds, window) via the card gear; changes persist and re-rate.
- [ ] User can **delete** an Activity; deleting the last one shows an empty state and skips the POST (no empty `activities[]`).
- [ ] Activities **persist locally** across launches; first launch seeds the two Templates.
- [ ] Metric picker offers **only LIVE metrics**; the editor **cannot save** an ADR-0005-invalid Activity (subset, bounds, `required`, window hours, `startHour != endHour`).
- [ ] Optional **time-of-day window** is authorable, including a **nocturnal (wrap)** window; the client sends it and the response's night-stitched `days[]` renders with correct **nocturnal day labels** ("Tonight" / "Tomorrow night" / "<Weekday> night"), not "Today"/"Tomorrow".
- [ ] **Home location** is settable in Settings and used over GPS; clearing returns to GPS→Dubai.
- [ ] **No PRO badge, no `-pro` variants, no accounts.** A soft quantity cap is enforced (constant), with StoreKit/Pro fully deferred (§8) unless the owner opted in.
- [ ] The dashboard still renders per-activity `days[]` correctly (never assumes 7); all clock/day labels remain in the response `timezone`.
</content>
</invoke>
