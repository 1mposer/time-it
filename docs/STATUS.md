# STATUS — now / next / blocked

> **Last updated: 2026-08-11** — Meteosource renewed on the **Standard** plan (endpoint switched `flexi`→`standard`) + Railway Hobby upgrade; earlier same day: Figma-first UI gate recorded ([ADR-0008](adr/0008-figma-first-ui-gate.md)). Prior: priority reset + docs consolidation 2026-08-10 on `reconcil` (rationale + full audit: [`docs/audit/AI_audit/`](audit/AI_audit/)). This file is deliberately one screen: a snapshot only. Per-item status and the ship order live in [ROADMAP](issues/ROADMAP.md) — the single home; nothing here restates it.

**Read order:** [`CLAUDE.md`](../CLAUDE.md) → [`CONTEXT.md`](CONTEXT.md) → this file → [ROADMAP](issues/ROADMAP.md).

## 1. Truth rule — which doc owns which facts

| Fact class | Single home |
|---|---|
| Code as it exists (architecture, contracts, tests) | [`CLAUDE.md`](../CLAUDE.md) |
| Domain vocabulary | [`CONTEXT.md`](CONTEXT.md) |
| Decisions of record + rationale | [`adr/`](adr/) · [`personalization_grill.md`](personalization_grill.md) (frozen) |
| Per-item status, ship order, deferrals + promote conditions | [`issues/ROADMAP.md`](issues/ROADMAP.md) |
| Now / next / blocked snapshot | this file |
| Vendor API behavior | [`API_documentation/`](API_documentation/) |
| Figma / design-system truth | [`design/FIGMA.md`](design/FIGMA.md) |
| Private operational facts | `OWNER_NOTES.local.md` (git-ignored) |

A fact stated in two homes is a bug — link, don't restate. Completed specs (in [`issues/completed/`](issues/completed/)) are historical records: bannered, never edited again.

## 2. Now / next / blocked

- **NOW:** nothing in flight. The WeatherKit track was discarded and deferred post-ship (owner decision 2026-08-10); the working tree is clean.
- **NEXT (ship order — ROADMAP has the full table):** owner ops (bundle-ID rename to `com.timeit.app.dev`) → spec 14 Figma catch-up pass → spec 14 minimal cut → iOS push opt-in client → live acceptance → **TestFlight**.
- **BLOCKED:** spec 14 rendering + the push client's opt-in UI wait on the Figma catch-up approval ([ADR-0008](adr/0008-figma-first-ui-gate.md)); live acceptance additionally needs the push client; TestFlight waits on the owner-ops items ([ROADMAP](issues/ROADMAP.md) items 4 + 9).

## 3. Standing flags (not blockers)

- **Known limitations (recorded, accepted):** DST *inside* a time-of-day window is untested (Asia/Dubai has no DST) — do not assert DST-correctness for windows. Half-hour zones (e.g. +05:30) render `ha`-style clock labels :30 off in both the iOS `TimeDeriver` and the server `jobs/labels.js`.
- **Client mirrors:** the client deliberately re-implements slices of server logic — read [ADR-0007](adr/0007-client-side-mirrors.md) before touching threshold semantics on either side.
- **UI is Figma-first:** frames precede code — decision of record: [ADR-0008](adr/0008-figma-first-ui-gate.md); frame backlog: [FIGMA.md §7](design/FIGMA.md).
- **Deferred-with-conditions:** metrics route + `RemoteMetricCatalog` + error-`code` enum + stale-activity reconciliation; analytics events table; #8; WeatherKit; Pro/StoreKit; cloud sync — each with its promote condition in [ROADMAP §Deferred](issues/ROADMAP.md).

## 4. Built state (one line each — detail in CLAUDE.md and `issues/completed/`)

- **Backend:** engine + `POST /api/v1/rating` + device routes + both push jobs — built, 172 tests green, deployed on Railway (single replica, always-on; production `initDb()` ran 2026-08-03).
- **iOS:** #5a core + #5b authoring + #5c location onboarding — built, audited, real-device-verified (138 tests). Push opt-in client: unbuilt ([spec](issues/current/implement-spec-push-client.md)).
- **Design:** Figma design system v1 + wizard frames + #5c frames — built ([FIGMA.md](design/FIGMA.md)); the spec 14 catch-up pass is pending and gates the spec 14 rendering ([ADR-0008](adr/0008-figma-first-ui-gate.md)).

*History: `git log`. (STATUS_LOG.md was deleted 2026-08-10 — git history keeps it.)*
