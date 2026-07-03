# Personalization Grill — Design Dialog

Working doc for the personalization design walk-through. One question at a time, top-down. Output will eventually feed into revised #5b/#6a specs.

Started: 2026-06-16. **Status: grill COMPLETE (2026-06-17) — read the cold-start handoff below.**

---

## ⚡ Cold-start handoff (read this first)

The personalization grill is **complete**: design questions Q1–Q9 are all locked. This file plus three ADRs are the canonical design record — no further grilling is needed. A fresh agent should read *this block* → the **Decisions locked** table → whichever **ADR** is relevant, then treat the Q-sections as rationale (the *why*), not new instructions.

### Artifacts (the canonical set — read in this order)

| # | Artifact | What it holds |
|---|---|---|
| 1 | **this doc** (`docs/personalization_grill.md`) | full decision log + rationale for every personalization choice |
| 2 | [`adr/0001-no-accounts-guest-first.md`](adr/0001-no-accounts-guest-first.md) | why there are no user accounts (Sign in with Apple cut) |
| 3 | [`adr/0002-activity-agnostic-engine.md`](adr/0002-activity-agnostic-engine.md) | why the engine evaluates caller-supplied activity profiles (Templates + custom), not a hardcoded list |
| 4 | [`adr/0003-seven-day-horizon-flat-hours-day-buckets.md`](adr/0003-seven-day-horizon-flat-hours-day-buckets.md) | 7-day forecast, flat hours, day-bucketed evaluation |
| 5 | [`adr/0004-day-bucketed-rating-wire-shape.md`](adr/0004-day-bucketed-rating-wire-shape.md) | the day-bucketed `/rating` **response** wire shape (`activities[].days[]`) — post-grill; pins the output side of Q6 |
| 6 | [`adr/0005-custom-activity-request-schema.md`](adr/0005-custom-activity-request-schema.md) | the `POST` **request** body `{ lat, lon, activities[] }` — post-grill; pins the input side of Q2/Q3 |
| 7 | [`CONTEXT.md`](CONTEXT.md) | domain glossary — **migrated for this grill in Phase 1/2** (Activity/Templates, metric catalog, Lite/Pro, 7-day Forecast are all now current) |
| 8 | `ios/` React mockup | visual reference **only**; real app is SwiftUI native. Its bottom bar is superseded (dropped, Q8). |

### LOCKED — build to these (detail in "Decisions locked" + the per-Q sections)

- **Identity:** no accounts; guest/local-first; iCloud sync; anonymous device id for push (Q1, ADR-0001).
- **Engine:** activity-agnostic — client sends activity profiles; curated list → **Templates** (Q2, ADR-0002).
- **Pro:** premium-metrics + quantity (free = basic metrics + unlimited Templates + 3 from-scratch); soft-lock on downgrade (Q3).
- **Pre-launch data:** wire **Air Quality + Marine** swappable adapters (Q4).
- **Notifications:** type follows **activity shape** (Daily Digest vs Window Watch); live whole-day alerts = Pro (Notification/CRON model).
- **Storage:** drop Supabase; one **Node + Railway Postgres**; append-only events table at launch (Q5).
- **Forecast:** **7-day / 168 flat hours**; day-bucketed engine output (Q6, ADR-0003).
- **iOS shape:** **5 surfaces / 8 screens, no bottom bar**; paywall contextual + transparent; onboarding splash-free (Q6–Q9, "Page inventory — final (v1)").

### Open work at grill close — now tracked in STATUS (do NOT read this as current)

This was the open-work snapshot at grill close (2026-06-17). **Live status now lives in [`STATUS.md`](STATUS.md) §4–§5** — this doc is a frozen rationale record and no longer tracks progress. Since grill close:

- ✅ **Custom-activity request schema — PINNED** ([ADR-0005](adr/0005-custom-activity-request-schema.md), Phase 2 built): `POST { lat, lon, activities[] }`, half-open local-hour window. The day-bucketed `/rating` *response* shape was likewise pinned in [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) (`activities[].days[]`, dense null days, `days[0]` card default — old audit blocker B2, resolved).
- ✅ **CONTEXT.md migration — DONE** (Phase 1/2): every glossary term was applied; the "CONTEXT.md migration" section near the end is kept only as the record of *what* changed.
- ✅ **Provider verification — Meteosource base DONE** (`flexi` ~164 clean hourly); Air Quality + Marine still pending, each when its adapter lands.
- ◻️ **Still open (see [STATUS.md](STATUS.md) §4):** Template-override + client sync schemas; v1-vs-fast-follow launch sequencing; the **spec rewrites** (fold the locked decisions here + in the ADRs into #5a / #5b / #6a–#6c) — the grill's final output, still outstanding.

### Historical sections (context only — NOT current truth)

"Why now", "Backend assumptions", and "Personalization features on the table" describe the **pre-grill starting state**. They are bannered and kept for rationale. **Where any of them conflicts with the Decisions locked table or a Q-section, the latter wins.**

---

## Why now (historical — the pre-grill motivation; note Supabase was later *dropped*, see Q5)

- Backend through #10 is stable. Next would normally be #5a (SwiftUI dashboard).
- User is considering **Supabase** for auth + DB instead of the DIY Postgres + JWT plan in #6a. This is an architectural pivot that affects #5a's networking layer, not just #6a.
- Mockup (`ios/`) is React (Figma Make output) — used as visual reference only. Real app is **SwiftUI native** per #5a spec.
- Existing #5b / #6a specs scope only *activity filtering* + *home location* (both local). They do **not** cover custom activities or threshold overrides — both of which the user wants.

Conclusion: grill first, lock the design, then start #5a. Doing #5a first risks rewriting the networking and navigation layers.

---

## Decisions locked

| Decision | Choice |
|---|---|
| Frontend stack | SwiftUI native (per #5a spec). React mockup in `ios/` is reference-only. |
| Timing | Grill personalization design before any iOS code lands. |
| Identity model | **No accounts.** Sign in with Apple cut entirely. Guest-first, local-first. |
| Cross-device sync | iCloud (KVS/CloudKit), not a backend account. Same person's Apple devices only. |
| Auth/DB stack | Auth deleted. Storage **resolved** — see the Storage row below + Q5. |
| Engine model | **Activity-agnostic.** Engine evaluates caller-supplied profiles; no built-in list. `evaluateAll(hours)` → `evaluateAll(hours, activities)`; `/rating` gains a POST form. See [ADR-0002](adr/0002-activity-agnostic-engine.md). |
| Activity definition | A user-authored profile: `{ label, chosen metrics, threshold per metric, optional time-of-day }`. |
| Curated list | Becomes **Templates** — seed defaults a user adopts then modifies. The `src/activities/*` files stop being "the activities." |
| Pro model | **Metrics + quantity.** Free = basic metrics + unlimited curated Templates + **3 from-scratch** custom activities. Pro = all metrics (incl. premium data) + unlimited. Client-enforced; backend stays stateless. |
| Pre-launch data | Wire **2 swappable adapters: Air Quality + Marine.** Bounded real APIs; double as NCM-ready slots. seaWarning / tide / astronomy stay deferred. |
| Notifications | Type follows **activity shape**, not tier. Whole-day → Daily Digest; ranged → Window Watch. Tier gates quantity + metrics. Live intra-day whole-day alerts = **Pro**. See Notification / CRON model. |
| Storage | **Drop Supabase. One Node/Express backend + Railway Postgres.** Minimal append-only events table at launch (anonymous install id + flexible details field); notifications phase adds device/push/state tables to the same database. Holidays + astronomy = static reference files (or a future adapter), not the database. |
| Navigation shell | **Dashboard = single home surface; NO bottom bar** (the mockup's bar was dropped in Q8 — settings → top-right gear, add → ghost card, home is the root). Authoring / settings / paywall present as **sheets**; card → timeline = **detail push**. See "Page inventory — final (v1)". |
| Forecast horizon | **Extend 24h → 7-day (168 hourly).** Wire stays **flat**: `hours[]` is 168 entries, addressed by `index` 0..167 against `forecastStart`. **Rolling window** — always day 0..6 relative to "now"; no absolute/running day counter ("day 299" never arises). Calendar *layout* deferred post-launch. |
| Evaluation bucketing | **Per-day buckets, derived — not a nested week object.** Engine searches *within each day* (no cross-midnight window fusion). Each activity result is up to 7 day-results: `{ dayIndex 0..6, rating, startIndex, endIndex, duration }` (or `rating: null`). The week **is** the response — no `week{}` container in the contract. Optional single `bestDayIndex` summary field if a page needs it. Absolute dates derived on demand (`forecastStart + index`), never a day number. See [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md). |

---

## Backend assumptions (the implicit frontend contract)

> ⚠️ **Pre-grill baseline — HISTORICAL, superseded.** This describes the backend *before* the grill. Superseded by: "activity-fixed" / "hardcoded activities" → user-authored Templates + custom (Q2, [ADR-0002](adr/0002-activity-agnostic-engine.md)); "24 hourly records" → 168 / 7-day (Q6, [ADR-0003](adr/0003-seven-day-horizon-flat-hours-day-buckets.md)); "all 5 activities returned" → engine evaluates caller-supplied profiles, day-bucketed. Per-user threshold overrides, custom activities, and per-user timezone (via the activity `window`) are now all in scope. **Where this conflicts with the Decisions locked table, the table wins.**

Backend is **stateless, user-agnostic, activity-fixed**.

**What the backend gives you per `GET /api/v1/rating?lat&lon`:**
- `forecastStart` (UTC, Z-suffixed) + 24 hourly records
- All 5 hardcoded activities, in canonical order, with `rating` + window (or `rating: null`)
- `displayMetrics` per activity — telling the client which fields to render

**What the SwiftUI app must own:**
- Timezone arithmetic (`forecastStart + index → local clock`)
- Filtering activities for display (e.g. Pro entitlement, user-selected subset)
- Filtering `hours[]` to a specific activity's window
- "Now" / current-hour highlight (compute against system time)
- The Session concept (where in the window the user actually goes)

**What the backend does NOT support today:**
- User identity / auth
- Per-user threshold overrides
- Custom user-defined activities
- Lite/Pro gating (StoreKit is planned client-side; backend returns all 5 to everyone)
- Per-user timezone

---

## Personalization features on the table

> Status: **RESOLVED.** Feature scope settled in Q2–Q4 (custom activities, threshold edits, Pro, push), and the page-level items are now the **final page inventory — tree item 5 is COMPLETE**; see "Page inventory — final (v1)". Note: the "Profile / account screen" listed below is **cut** (no accounts, Q1) — it folded into Settings. Original inventory kept for reference only.

From conversation so far:

- [ ] **Filter visible activities** — user picks which of the 5 to see. Already in #5b (local-only).
- [ ] **Save home location** — pinned lat/lon, no GPS each launch. Already in #5b (local-only).
- [ ] **Edit thresholds on built-ins** — e.g. "I tolerate up to 38°C." **Not in any spec.** Requires either decision-engine change (accept per-request thresholds) or full server-side user prefs.
- [ ] **Create custom activities** — user-defined activity with their own thresholds (e.g. "Padel"). **Not in any spec.** Biggest scope addition.
- [ ] **Pro subscription** — StoreKit 2 gating for Pro cards. Sketched in #5b.
- [ ] **Profile / account screen** — sign-in state, identity, sub status. Sketched in #5b.
- [ ] **Push notifications** — daily digest + perfect-window detection. Planned for #6c.

Pages implied so far: Dashboard (exists in mockup), Threshold Edit, Add Custom Activity, Profile, Subscription, Settings, Onboarding. Final count TBD.

---

## The design tree (top-down)

1. **Identity model** — guest-first vs sign-in-gated? What does signing in unlock vs gate?
2. **Auth stack** — Supabase vs roll-your-own; does SwiftUI hit Supabase directly or via Node?
3. **Persistence model** — local-only / backend-synced / local-first-then-sync?
4. **Feature scope** — which of the features above ship in v1?
5. **Page inventory** — total page count, hierarchy, navigation pattern (tabs, stacks, sheets)
6. **Per-page design** — what each page does, inputs/outputs, edge cases
7. **Data shapes** — threshold-override schema, custom-activity schema, sync model

**Progress (2026-06-17):**
- ✅ **1 Identity** — no accounts; guest-first; local-first + iCloud sync; anonymous device id for push. [ADR-0001](adr/0001-no-accounts-guest-first.md)
- ✅ **2 Auth/storage** — auth deleted; one Node backend + Railway Postgres; Supabase dropped.
- ✅ **3 Persistence** — local-first dashboard; iCloud cross-device; server store for analytics (launch) + push (later).
- ✅ **4 Feature scope (what)** — activity-agnostic engine [ADR-0002](adr/0002-activity-agnostic-engine.md); Pro = metrics + quantity; Model-2 Template billing; notification/CRON model. *Open: v1-vs-fast-follow sequencing.*
- ✅ **5 Page inventory** — DONE (Q6–Q9). **5 top-level surfaces / 8 screens:** Dashboard (root), Timeline detail (push), Authoring sheet (chooser→editor→metric-picker), Paywall sheet, Settings sheet. Nav shell, 7-day horizon, per-day bucketing, read/write split, one-authoring-screen, paywall placement + transparency, onboarding (no splash, device defaults, location-only prompt, 2 free-metric seeds + ghost add-card), settings contents, **no bottom bar** — all locked. See "Page inventory — final (v1)".
- ◻️ **6 Per-page design** — NOT STARTED.
- 🟡 **7 Data shapes** — partial: activity profile `{ label, metrics, threshold/metric, window:{startIndex,endIndex} }` *(window shape superseded by [ADR-0005](adr/0005-custom-activity-request-schema.md): local-hour `{startHour,endHour}`)*, served metric catalog `{ key, label, unit, type, bounds, availability, tier, description, proReason? }` (Q7), events-table shape, **day-bucketed activity result `{ dayIndex 0..6, rating, startIndex, endIndex, duration }`** (Q6). *Open: full custom-activity + Template-override + sync schemas.*

---

## Open questions (answered top-to-bottom)

### Q1 — Identity model (LOCKED)

Current #5a spec is **guest-first**: dashboard opens directly, GPS used immediately, Sign in with Apple is an optional sheet. The app must be useful with zero personalization on first launch.

**Question:** Keep guest-first (signing in only *unlocks more* — saved prefs, custom activities, Pro), or allow guests to personalize too (e.g. threshold edits stored locally, no account)?

**i.e. is sign-in the gate for personalization, or just the gate for cross-device sync?**

> _Answer (2026-06-16):_ **Neither — sign-in is removed entirely.** No web companion or social features are planned, so there is no need to identify a *human* across accounts; we only ever need to identify a *device*.
>
> Sign in with Apple was doing two jobs, both reassigned to better-fit tools:
> - **Cross-device sync (phone↔iPad)** → **iCloud** (`NSUbiquitousKeyValueStore`, or CloudKit private DB if the prefs blob outgrows the ~1 MB / 1024-key limit). Syncs across the user's own Apple devices with no login UI and no backend.
> - **Server-pushed notifications (#6c)** → **anonymous device identity** (install ID in Keychain + APNs token). Push targets a device, not a human.
>
> Pro already follows the Apple ID via StoreKit "Restore Purchases" — no app account needed. Analytics are aggregate, so they use the anonymous install ID, not identity.
>
> **Consequence — pure win:** the entire #6a auth stack is deleted (Apple JWKS verification, JWT issuance/storage, the `users` table, and the local→server merge/migration story, since there is no account to merge into). `user_preferences` becomes keyed by anonymous device ID; `device_tokens` stays. App Store Guideline 4.8 imposes no obligation because we offer no other login.
>
> **Identity ladder (locked):**
> - **Tier 0 (v1):** anonymous local — all personalization + Pro, zero network identity.
> - **Tier 1 (#6c):** anonymous device ID + APNs token synced to backend — enables push.
> - **Tier 2:** real human account — **not on the roadmap**; the door stays closed.

### Q2 — Evaluation architecture for personalized thresholds (LOCKED)

Q1 deleted the auth half of the original "auth + DB" question. Before the storage/Supabase question, a more foundational one that directly shapes the #5a networking layer: **the user wants threshold overrides on built-ins and custom user-defined activities — where does the *evaluation* of those personalized thresholds happen, and how does the client deliver them to the engine?**

> _Answer (2026-06-16):_ **Option A — per-request thresholds, engine becomes activity-agnostic.** See [ADR-0002](adr/0002-activity-agnostic-engine.md). The client authors **Activities** locally (`{ label, chosen metrics, threshold per metric, optional time-of-day }`), stores them locally, and sends them in the request body; the stateless engine evaluates whatever it's given. Rejected: server-stored-per-user (fights Q1, needs storage just to render the dashboard) and client-side engine (duplicates the crown jewel).
>
> The user generalized this further and correctly: **the backend never knew what an "activity" was** — it knows metrics, thresholds, and Windows. So the curated activity list isn't special; it's just **Templates** (seed defaults). The engine is fully agnostic to the platform's curated list.
>
> **Cross-contamination this opens (the real cost):**
> 1. **Pro/Lite collapses** → must be redefined (resolved in Q3).
> 2. **Placeholder-data trap** — the curated list silently hid fake-data metrics (`darkness=0`, etc.); free authoring would let a user threshold on them and get a silent false **Perfect**. The metric catalog must flag *available* vs *coming-soon* and hide the latter from authoring.
> 3. **Time-of-day is a new dimension** — engine has no "only these hours" concept today, and "12–2pm" is *local* (timezone). **RESOLVED in Q2 loose-end (b):** the activity carries `window: { startIndex, endIndex }` (UTC indices, client-converted) and the backend evaluates the range. (Earlier "client clips" lean was rejected — Window Watch needs the backend to evaluate the range server-side while the app is closed.)
> 4. **Metric catalog becomes a first-class contract** — key, label, unit, type (numeric vs `flag`), bounds, availability flag. Lean: **served by backend** (`GET /api/v1/metrics`) so it auto-adapts as new sources land.
> 5. **`displayMetrics` shifts** — user-chosen now, not backend-decided. CONTEXT.md needs updating.
> 6. Lesser: `flag`-vs-numeric authoring controls; user sets `required` (must-have vs nice-to-have); backend input validation; golden-snapshot / `activities.length` tests reworked.

**Q2 loose ends (RESOLVED 2026-06-17):**
- **(a) Metric catalog — served, `GET /api/v1/metrics`.** Updates server-side as AQI/Marine/NCM land; the available→coming-soon flip is a backend change, no App Store release. Baking it in would couple metric growth to app releases — wrong, given the whole pre-launch plan is *adding sources*.
- **(b) Time-ranged window — `window: { startIndex, endIndex }` (UTC indices) on the Activity profile.** Client converts "2–4pm local" → UTC once (UAE +4, no DST). Engine constrains its search to the window; absent window = whole-day. One representation serves both the dashboard rating and the cron Window Watch (the backend *must* receive the range — Window Watch evaluates it server-side while the app is closed, so client-clipping alone won't do).

### Q3 — Pro model redefinition (LOCKED)

With Lite/Pro-as-activities dead, what does Pro gate?

> _Answer (2026-06-16):_ **A mix of (a) premium metrics + (b) quantity.**
> - **Free:** basic (free-tier) metrics — `temp`, `humidity`, `windSpeed`, `rainFall`, `cloudCover`, `visibility`, `uV`, `moon`, `dustAlert` — and up to **3** custom Activities.
> - **Pro:** **all** metrics incl. premium/specialised data (air quality, marine, future NCM) + **unlimited** Activities.
> - Enforced **client-side** (consistent with #5b's existing StoreKit decision — backend stays stateless and just logs). StoreKit mechanism survives; `isPro` detection moves from "activityId ends in `-pro`" to `Transaction.currentEntitlements`.
> - The free/premium metric partition **maps onto data-availability tiers** — the old Lite/Pro logic survives at the *metric* level instead of the *activity* level.
>
> **Sub-decisions:**
> - **(i) Downgrade integrity — RESOLVED. Soft-lock, never delete; re-subscribe is a full restore.**
>   - *Quantity overflow:* lock from-scratch activities beyond 3; user **picks which 3 stay active, defaulting to most-recently-used**; rest greyed "re-subscribe to reactivate." Template-derived activities never lock **on the quantity cap** (a premium metric still locks them — see the next bullet).
>   - *Premium-metric activities:* lock entirely (can't be honestly evaluated free; silent-drop would resurrect the false-Perfect trap). For Template-derived ones, offer one-tap **"remove the premium metric to keep using it free."**
>   - *Pro notifications:* revert to free Daily Digest; live whole-day alerts stop.
>   - Enforcement client-side (StoreKit reports lapsed entitlement); backend stops Pro cron jobs on next sync. Nothing deleted → re-subscribe restores exactly.
> - **(ii) Template counting — RESOLVED: Model 2.** Adopting *and editing* curated **Templates** (the set list) is **free and unlimited** — this is how the "edit thresholds on built-ins" feature ships. The 3-activity free cap applies **only to from-scratch** custom activities (activities not derived from a Template). Pro lifts the cap + unlocks premium metrics. The engine doesn't distinguish Template-derived from from-scratch (ADR-0002); the distinction lives **only** in the billing rule. Metric gate and quantity gate are orthogonal — a free Template edit still can't add a premium metric.
> - **(iii) Notifications — RESOLVED;** see Notification / CRON job model below.

### Q4 — Pre-launch premium data sources (LOCKED)

Pure-quantity Pro under-tests the premium hypothesis; the audience is multi-segment (cyclists, running, fishing, tanning, kite surfing, padel + potential stargazing, night swimming, BBQ); and a credible launch is instrumental to re-warming a **cold partnership with the UAE National Center of Meteorology (NCM)** — the real long-term data moat.

> _Answer (2026-06-16):_ **Wire two new data sources pre-launch: Air Quality (PM2.5/PM10/AQI) + Marine (wave/swell height & period, sea-surface temp).** Chosen for max audience coverage (AQI = land segments; Marine = water segments → together cover all primary + most potential audience), bounded real APIs (e.g. Open-Meteo Air Quality / Marine), and clean commercial licensing.
> - Wire as **swappable Adapters** (`src/weather/adapters/`) — they become the exact slots NCM data later fills, and double as a working multi-source proof for the NCM pitch.
> - This **fixes the "empty Pro tier at launch"** problem — premium metric-gating now has real substance day one.
> - **Held the line:** `seaWarning` (no source), `tide` (no source), astronomy/`darkness` (new vendor) stay deferred — those are the unbounded ones.
> - Caution: don't over-polish interim sources; keep them swappable for NCM. Verify commercial-use licensing (NCM will care about provenance).
> - Roadmap impact: backend data work moves pre-launch but parallelizes with #5a iOS work.

### Notification / CRON job model (LOCKED — resolves Q3.iii)

The blur: notification type was wrongly mapped to *tier*. It actually maps to **activity shape**. Custom activities introduced a second shape (a user-fixed time-range), which asks a different question and needs a different job.

**Two activity shapes → two evaluation patterns:**

| Shape | Question | Pattern |
|---|---|---|
| **Whole-day** (no time constraint — tanning, cycling, set-list) | "*Where* in the next 24h is the best window?" | Evaluate once, find-best-window-anywhere |
| **Time-ranged** (user-fixed window — paragliding 2–4pm, yoga) | "Is *my fixed window* going to be good?" | Re-evaluate hourly as the forecast refines, until the window opens |

**Principles (all confirmed 2026-06-16):**

- **P1 — Notification type follows activity shape, never tier.** Whole-day → **Daily Digest** (one morning push). Time-ranged → **Window Watch** (hourly re-eval until the window opens; push only on rating *change*).
- **P2 — Tier gates quantity + metrics only.** A free user's ranged custom activity gets Window Watch exactly like a Pro's; free users just get ≤3 activities and basic metrics. *(This corrected the earlier wrong "digest=free, realtime=pro" framing.)*
- **P3 — Window Watch is bounded:** stop watching after the window-start passes; notify only on meaningful transitions (None→Good/Perfect; Good/Perfect→Bad), de-duped via `notification_state` — not hourly. Cheap because the 30-min location cache collapses weather fetches in a geographically concentrated market, leaving only CPU-cheap threshold eval.
- **P4 — Timezone:** window is user-local; client converts to a UTC index-range on sync. UAE has no DST + fixed +4, so trivially safe for launch.
- **P5 — Push requires server-side activities.** For the cron to evaluate a custom activity while the app is closed, the activity definition must sync to the backend (anonymous-device-ID store, identity Tier 1). Local-first for the dashboard; server-side copy required for push. **Feeds Q5** (activities table keyed by anon device ID).

**The one fork, resolved:** live intra-day *"a new Perfect window just opened"* alerts for **whole-day** activities = **Pro feature.** Free users get the morning **Daily Digest** for their (set-list + custom) activities; Pro adds live whole-day alerts on top. Ranged-activity **Window Watch** stays available to both tiers (it's intrinsic to the feature). Checks out against all three user stories (pro paraglider = watch; free tanning/cycling = digest; free morning yoga = watch).

Maps onto the existing #6c jobs ~1:1: "daily digest" → Daily Digest (now shape-aware); "perfect-window detector" → Window Watch + Pro whole-day live alerts.

### Q5 — Server-side storage / Supabase (depends on Q3/Q4)

What server-side storage do we actually need, when, and does Supabase still earn its place now that its auth selling point is gone? (Candidates: analytics events store; #6c push prefs + device tokens keyed by anonymous device ID.)

> _Answer (2026-06-17):_ **Drop Supabase** (its reason for consideration was auth, which Q1 deleted). **One Node/Express backend, Railway Postgres behind it** — the client already must talk to Node for rating + metrics, so a single backend avoids two API surfaces and preserves the analytics-funnel property (ADR-0002). What dropping Supabase sacrifices: its sign-in system (irrelevant — no accounts), its built-in data-browser screen (use a standalone database viewer), direct app→database access (deliberately unwanted — would mean two backends), and live-streaming/file-hosting (unused). Net: nothing the product needs.
>
> **What we store, and when:**
> - **Metric catalog** — static, served by Node; no database needed.
> - **Analytics** — **scaffold at launch.** One append-only events table: `{ anon_install_id, timestamp, event_type, details (flexible) }`. Answers "how many users" (distinct install ids — approximate: reinstalls/multi-device overcount) and "what they do." Flexible `details` field = log new event types without schema change.
> - **Device / push store** — added in the notifications phase (#6c) to the *same* Postgres: device id + token, the user's synced activities, home location, tier flag, notification prefs, `notification_state` de-dup.
>
> **Holidays + astronomical events (full moon, eclipses):** the user wanted a DB + live-updating service for these — **overcooked.** They're small and predictable (eclipses/moon phases are fixed physics, known years ahead; holidays change ~yearly). Solution: **static reference files served like the catalog**, or folded into the astronomy adapter when it lands. They surface as **flags on forecast hours** ("this hour is a full moon"), flowing through the same pipeline — and form the basis for the future "alert me on a meteor shower / eclipse" feature (Issue #8 `requireTrue`). Not database rows, not a live service.
>
> **To-do flag:** disclose anonymous analytics in the App Store privacy notice.

### Q6 — Forecast horizon, bucketing & navigation shell (LOCKED, page-inventory branch)

Opened tree item 5 (page inventory). The visual mockup confirms the dashboard as the single home surface; the bottom bar (home / add / settings) is actions, not peer tabs. Two user ideas surfaced — a **calendar** and a **multi-day timeline view** ("check tomorrow / next week instead of relying on push"). Both need data beyond today, which exposed the gating decision: the backend serves **24 hours only**.

> _Answer (2026-06-17):_
> - **Horizon → 7-day (168 hourly).** Providers return multi-day; cost is small. Unlocks the timeline drill-down and keeps the calendar door open.
> - **Calendar deferred post-launch** — it's a *layout*, not a *job*. The timeline view absorbs most "what's tomorrow?" need. Revisit when it has a defined job (e.g. tap a future day to pre-schedule a Session/reminder).
> - **Timeline view = drill-down detail screen** from a card, not a peer surface. Fits the dashboard-as-home shell.
>
> **Bucketing — the real design consequence.** The single-best-window search assumed a 24h bucket. Over 168h it would return windows days away or fuse a Thu-evening + Fri-morning block into a meaningless "30-hour Perfect window." Resolution:
> - **Wire stays flat.** `hours[]` = 168, addressed by `index` 0..167 against `forecastStart`. "Day" is a *derived* view (`floor(index/24)` → 7 buckets), not a stored container.
> - **Evaluation output is day-bucketed.** Each activity result → up to 7 `{ dayIndex 0..6, rating, startIndex, endIndex, duration }`. Engine searches within each day. Dashboard card shows day 0 by default; timeline view renders all 7.
> - **No `week{}` nested object.** A week container carries no payload of its own (box around 7 boxes) and would harden a grouping the client may want to slice differently (e.g. "next 48h" spanning two days). The week *is* the response. Optional single derived `bestDayIndex` ("best cycling day: Thu") only if a page wants it.
> - **"Day 299" is a non-problem.** Rolling window — every request is a fresh day 0..6 relative to `forecastStart`. No running day counter. Absolute calendar position, when ever needed, is the **derived date** (`forecastStart + index → 2026-06-22`), not a day number.
>
> **Code cost (explored 2026-06-17):** the decision engine (`findLongestWindow`, midnight logic) iterates `ratings.length` — **zero engine changes** to handle 168. Core change is one line in `parse.js` (`slice(0,24)` → `slice(0, FORECAST_HOURS)` behind a constant). Remainder is test churn (~15 fixtures + ~6 assertions hardcode `24`/`0..23`). ~half a day, mechanical. Difficulty: **moderate, not invasive.**
>
> **Open consequences to carry forward:**
> - **Contract bump** — `hours[]` 24→168, `index` 0..167; iOS decoder must not assume 24. The day-bucketed activity result is a new shape (feeds tree item 7).
> - **Daily Digest must day-scope** — "best window in next 24h" = slice day 0 out of 168 before searching, else Monday's push reports Saturday's window. Window Watch (time-ranged) unaffected.
> - **⚠️ Provider verification required before final lock** — many providers serve hourly resolution only for the first 48–72h, then 3-hourly/daily. Confirm Meteosource (+ the air-quality / marine sources) return clean *hourly* data across all 7 days against a live response. If they degrade, the week view is coarser than the dashboard and the "168 clean hourly entries" assumption is wrong.
> - **Payload ~7×** (×further for air-quality + marine fields) — still tens of KB, but raises the value of the 30-min location cache and a possible "today vs full-week" response split.

### Q7 — Paywall placement & metric transparency (LOCKED, page-inventory branch)

> _Answer (2026-06-17):_ **One paywall sheet, contextual triggers, gated-but-visible.**
> - **Triggers (all from the Q3 gates):** tap a locked premium metric in the picker; save a 4th from-scratch activity; toggle live whole-day alerts on. Plus a passive **"Upgrade to Pro" row in Settings**. No standalone upgrade tab.
> - **Gated items are shown, disabled — never hidden.** Premium metrics appear greyed/"Pro" in the picker; the 4th slot is visible. This is the discovery mechanism for the air-quality/marine metrics — if hidden, the gate never triggers and the user never learns Pro has substance.
> - **Why contextual:** the sheet appears at the moment of demonstrated intent and can say *why* this specific thing is Pro. Converts better than a passive tab; keeps the focused dashboard shell uncluttered. One screen, many entry points.
>
> **Metric transparency — two catalog fields (locked):** each served metric-catalog entry carries plain-language copy so the user knows exactly what they pay for. Server-served ⇒ editable without an app release.
> - `description` (every metric) — *what it measures*, e.g. "Air Quality — fine-particle pollution (PM2.5/PM10)."
> - `proReason` (Pro metrics only) — *why it's paid*, e.g. "Air Quality comes from a specialised paid source, so it's part of Pro."
> - Kept separate because they answer different questions and surface in different places: the **picker** expands both inline when a locked metric is tapped; the **contextual paywall** header repeats the triggering metric's `proReason`. Same copy, served once, reused in both — no duplicated strings.
> - **Framing principle:** the honest answer is almost always *"it comes from a data source we pay for"* — true, sympathetic, and it sets up the NCM story ("now sourced from the UAE National Center of Meteorology"). Avoid invented feature justifications.

### Q8 — Onboarding, first-launch & dashboard density (LOCKED, page-inventory branch)

> _Answer (2026-06-17):_ **Launch straight to usable content — no splash/logo, no blocking walkthrough.**
> - **Teaching = progressive disclosure + contextual first-touch hints** (a tooltip the first time a specific feature is touched), never a full-UI overlay tour. Standard iOS components + predictable placement carry the weight; users infer function from the design.
> - **Defaults pulled from the device, not prompted:** units (°C/°F, km/h/mph), timezone, locale. The **single unavoidable prompt is location permission** — iOS won't surface location silently and the app is inert without it; fire it *contextually at first forecast*, not behind a splash gate.
> - **Sensibly-empty dashboard:** seed **2** curated Templates (not 4), chosen from **free-metric** activities so nothing shows a lock on first launch (lean: **Cycling + Fishing-lite** — land + water, core audience, both free-tier). Plus a **ghost "add" card** at the list end → activity creation (from-scratch or from a Template). The near-empty state signals "this is yours to shape" while still delivering immediate real ratings.
>
> **Consequence — bottom bar dropped.** Moving "add" to a card leaves the mockup's bottom bar with only home + settings (a vestigial 2-item tab bar), and the mockup already duplicates settings (top-right avatar + bottom person). Resolution: **no bottom bar.** Settings → **top-right gear/avatar** (standard iOS, already in mockup); add → ghost card; home is the root.

### Q9 — Settings contents (LOCKED, page-inventory branch)

> _Answer (2026-06-17):_ **Top-right gear → Settings sheet. Ship only live controls; hide a feature's section until it lands.**
> - **At launch:**
>   - **Home location** — view/change saved lat/lon (the #5b "save home location" feature).
>   - **Subscription** — tier status; **Upgrade to Pro** if free (passive paywall entry, Q7) / **Manage Subscription** if Pro; **Restore Purchases** (StoreKit — the only "restore" path, no account).
>   - **Privacy** — anonymous-analytics disclosure (satisfies the App Store privacy to-do) + **opt-out toggle**.
>   - **About** — version, support/contact, rate-the-app.
> - **Deferred — hidden until #6c:** **Notifications** (Daily Digest time, per-activity toggles, Pro live-alerts). No inert switches shipped at launch.
> - **Units: no toggle** — inferred from device (Q8); add an override only if users ask.

### Page inventory — final (v1)

**5 top-level surfaces; 8 distinct screens** (authoring is one sheet with 3 internal steps). System dialogs (location permission, StoreKit purchase/manage) and the deferred Notifications section are not counted as built screens.

| # | Surface | Kind | Entered from | Notes |
|---|---|---|---|---|
| 1 | **Dashboard** | root | app launch | 2 seeded Templates + ghost add-card; weather header; top-right settings gear. No bottom bar. |
| 2 | **Activity timeline detail** | push | tap a card | 7-day expanded hourly view (read-only). |
| 3 | **Authoring** | sheet | ghost add-card (new) / per-card gear (edit) | one sheet, seeded 3 ways. Internal steps ↓ |
| 3a | · Start-point chooser | step | *new path only* | "Choose a Template" gallery vs "Start from scratch". Edit path skips this. |
| 3b | · Editor | step | after 3a, or directly on edit | name, metrics, thresholds, optional time window; save-time free-3 guard. |
| 3c | · Metric picker | step | from editor | browse catalog: available/coming-soon + free/Pro; `description` + `proReason`. |
| 4 | **Paywall** | sheet | contextual triggers (locked metric / 4th save / live-alert toggle) + Settings | one sheet, gated-but-visible. |
| 5 | **Settings** | sheet | top-right gear | location, subscription, privacy, about. Notifications hidden until #6c. |

**Navigation map:** single `NavigationStack` rooted at Dashboard → Timeline detail (push). Authoring, Paywall, Settings are sheets; Authoring carries its own internal stack (chooser → editor → metric picker). Onboarding adds **no custom screen** — just the OS location prompt + contextual first-touch tooltips (Q8).

---

## CONTEXT.md migration — DONE (Phase 1/2)

The grill redefined these core glossary terms; the migration was **applied to [`CONTEXT.md`](CONTEXT.md) when the Phase 1/2 code landed** (code + docs together, no drift). This list is kept as the record of *what changed* — every term below now reads the new way in CONTEXT.md:

- **Activity** — from "code-level entity the engine evaluates (hardcoded list)" → "user-authored profile; engine is activity-agnostic."
- **Template** (new term) — curated seed-default Activity.
- **Lite / Pro** — from "data-availability activity tiers (`-lite`/`-pro`)" → "metric-access + quantity subscription gating."
- **Display metrics** — drop "the backend decides"; user-chosen for custom activities.
- **Metric catalog** (new term) — the authoritative set of pickable metrics + per-metric `{ availability, tier, description, proReason? }`; served by the backend so copy/availability change without an app release.
- **Forecast** — from "24 hourly entries" → "168 hourly entries (7-day rolling), flat-addressed by `index` 0..167 against `forecastStart`" (Q6).
- **Index** — drop "0–23"; now "0 to N-1 (0..167 for the 7-day forecast)" (Q6).
- **Day bucket** (new term) — a derived 24-hour slice of the forecast (`floor(index/24)`, `dayIndex` 0..6); the unit the engine searches for a best **Window**. Not a stored container.

---

## Session status — CLOSED (2026-06-17)

The personalization grill is **complete**; Q1–Q9 are locked. No further grilling is required to start building. **Forward progress is tracked in [`STATUS.md`](STATUS.md), not here** — the items below are the grill-close to-do snapshot, annotated with what has since landed.

1. ✅ **Engine + contract decisions built** — Phase 1/2 shipped the activity-agnostic POST contract ([ADR-0002](adr/0002-activity-agnostic-engine.md) / [ADR-0004](adr/0004-day-bucketed-rating-wire-shape.md) / [ADR-0005](adr/0005-custom-activity-request-schema.md)).
2. ◻️ **Spec rewrites still outstanding** — **#5a** (core SwiftUI app), **#5b** (personalization), **#6a→#6c** (push) must fold in every locked decision here + in the ADRs; the current `docs/issues/current/*` specs remain pre-rebuild (see STATUS §5).
3. ✅ **CONTEXT.md migration applied** with the Phase 1/2 code (section above).
4. ✅ **Provider verification** — Meteosource base done; Air Quality + Marine pending their adapters (STATUS §4).
