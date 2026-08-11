# PROJECT_PHILOSOPHY — what time-it is, derived from its own artifacts

**Audit date:** 2026-08-10 · Phase 1 of the reconciliation audit (branch `reconcil`).
Sources: CONTEXT.md, ADR-0001–0006, personalization_grill.md, STATUS.md, the spec corpus, git history.

---

## The thesis (the statement the owner should recognize)

> **time-it answers one closed question for an outdoor hobbyist: "during my hours, at my
> place, for my thing — is it worth going out this week?" — and it would rather say
> nothing than say something it can't back with real data.**

One deep evaluation engine, agnostic to everything: activities (caller-supplied,
ADR-0002), providers (adapter boundary), timezones (time-boundary module), tiers
(client-enforced). Every opinion about *what* to evaluate lives on the client; the server
owns only *evaluation truth*. The product's entire currency is that the rating can be
trusted — which is why the false-Perfect guard shows up at every layer (coming-soon
metrics hard-400, absent data fails thresholds, hours are never fabricated or
interpolated).

## The problems it refuses to solve

Derived from explicit rejections, not convention:

1. **Identifying humans.** No accounts, no auth stack, no merge story (ADR-0001). The
   only identity is a disposable anonymous install UUID.
2. **Storing user state server-side.** `/rating` is stateless; the push path holds a
   client-authoritative *copy* that can be deleted without loss (ADR-0006).
3. **Being a weather app.** It never presents raw forecast as the product; the forecast
   is input to a verdict. Display metrics exist to *justify* the verdict.
4. **Answering with fabricated confidence.** No interpolated hours, no placeholder
   thresholds, no fallback location ("the app never fabricates a location", #5c).
5. **Enforcing money server-side.** Tier gating is client-side; the server's ~50-activity
   ceiling is a DoS guard, deliberately not a paywall.

## Design commitments the structure implies

- **Deep modules, thin edges.** Provider-specifics stop at the adapter; locale stops at
  the time-boundary; APNs stops at `src/notifications/`. ADR-0002 rejected a client-side
  engine in exactly these words: *"duplicates the crown-jewel Window logic, two engines
  drift."*
- **Contracts before code.** Grill → ADR → spec → build, with the wire shape pinned by
  golden snapshots and the docs carrying explicit drift tripwires (STATUS truth rule,
  drift table).
- **Docs are the primary interface.** The read order (CLAUDE → CONTEXT → STATUS) is
  designed for agents; specs are written to be executable by a fresh session without the
  owner present.
- **Ship lean, decide late.** No migration framework, single replica, idempotent
  `initDb()`, iCloud-over-backend sync — every infrastructure choice defers weight until
  a user forces it.

---

## Where stated philosophy and practiced philosophy have diverged

This is the diagnostic section: each divergence is a place where scope creep or drift
entered.

### D1 — "Two engines drift" is being reversed without an ADR

ADR-0002 rejected client-side evaluation to protect the single engine. Since then the
frozen wire contract has forced **three client-side mirrors of server logic**: the
static metric catalog (`StaticMetricCatalog` mirrors `metricCatalog.js`), the clock-label
logic (`TimeDeriver` mirrors `jobs/labels.js` — CLAUDE.md itself calls them twins), and
now **spec 14 §3 adds a fourth and largest: `HourQuality`, a client mirror of
`evaluateHour`**. Each mirror has a pinning test, but no doc names the pattern, counts
the mirrors, or records the decision that mirroring is the accepted price of a frozen
wire. That decision is being made implicitly, three times, instead of once in an ADR.

### D2 — The anti-drift docs are themselves drifting

The docs system was *designed* to prevent drift (truth rule, drift table, "STATUS does
not restate decisions — it points"). In practice:

- STATUS §5 is a single ~1,400-word bullet that restates spec content, ADR content, and
  build history — the exact restatement the file's own header forbids.
- `personalization_grill.md`'s "Decisions locked" table still carries **four superseded
  contracts un-bannered** (fixed 168 count; `floor(index/24)` day rule; `bestDayIndex`
  kept vs ADR-0004's rejection; UTC-index window encoding vs ADR-0005).
- ADR-0003 still pins the Digest as day-0-strict; ADR-0006 superseded that but ADR-0003's
  text was never annotated.
- The Figma foundations doc's header claims "all §8 acceptance items pass" above six
  unticked §8 checkboxes, and simultaneously says `App Colors` was kept and that the
  spec body's retire/don't-touch lists were overtaken by owner deletions.

The tax shows in git history: a large fraction of all commits are `docs:` reconciliation
commits. Drift control is manual, per-session, and losing.

### D3 — "Ship one provable thing" vs parallel-track accretion

The lean-infrastructure philosophy says feedback first. The backlog practice says
otherwise: pre-launch AQ + Marine adapters (grill Q4), the #7 marine tier, the WeatherKit
provider abstraction, a Figma design-iteration track, and spec 14's full five-surface
rework all accreted **while the actual ship-blockers sat still**: the bundle ID is
unshippable (`com.timeit.app` belongs to another Apple account), live weather is dead
(Meteosource lapsed, #11), and the app has never reached TestFlight. Scope creep entered
precisely through the sections labeled "parallel / open now."

### D4 — The feedback loop was designed, then silently dropped

Grill Q5 **locked** an append-only analytics events table "at launch." It was never
built, never carried into any spec, and is absent from the ROADMAP. The project's
governing objective (start the feedback loop) currently has **no instrument**: no
TestFlight distribution, no analytics, no owner-usable telemetry. The philosophy's most
important commitment is the one with zero implementation.

### D5 — A phantom process-blocker has been reified into architecture

STATUS, OWNER_NOTES, and the ROADMAP all treat "the WeatherKit agent's in-flight pbxproj
track" as a hard serialization point: the push client, the bundle-ID rename, and by
extension shippability are all documented as "double-blocked" on it. The actual working
tree contains ~20 lines of incidental Xcode churn (a `DEVELOPMENT_TEAM` value, a scheme
Debug→Release flip, pbxproj normalization, one blank comment line), no branch, no stash,
and the WeatherKit handoff itself says "exploratory findings … not a locked spec — no
ADR." A note about not clobbering another agent's edits hardened into a structural
dependency that has serialized all iOS work since ~2026-07-30.

---

*Phases 2–3 (INTERFACE_MAP.md, PRIORITY_RESET.md) build on these divergences.*
