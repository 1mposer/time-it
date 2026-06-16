# Personalization Grill — Design Dialog

Working doc for the personalization design walk-through. One question at a time, top-down. Output will eventually feed into revised #5b/#6a specs.

Started: 2026-06-16.

---

## Why now

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
| Auth/DB stack | **Open** — leaning Supabase, not finalized. |

---

## Backend assumptions (the implicit frontend contract)

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

---

## Open questions (answered top-to-bottom)

### Q1 — Identity model (OPEN)

Current #5a spec is **guest-first**: dashboard opens directly, GPS used immediately, Sign in with Apple is an optional sheet. The app must be useful with zero personalization on first launch.

**Question:** Keep guest-first (signing in only *unlocks more* — saved prefs, custom activities, Pro), or allow guests to personalize too (e.g. threshold edits stored locally, no account)?

**i.e. is sign-in the gate for personalization, or just the gate for cross-device sync?**

> _Answer:_

### Q2 — TBD (depends on Q1)

---

## Resume checklist

- Re-read this file
- Pick up at the first OPEN question
- After each answer: log it under the question, then ask the next one
- When all questions are closed → write/update specs for #5a, #5b, #6a accordingly
