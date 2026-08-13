# Implementation spec — Issue #14: Dashboard rework — range-first showcase

**Date:** 2026-08-09 (grill session, owner + agent — all decisions below are owner-confirmed)
**Status:** locked spec, unbuilt. **In SHIP scope as the *minimal cut* (gate decision 2026-08-10):**
§4 (±1h flexibility) and the full-wizard reading of §6 (screens 2–5 of the **5-screen wizard**) are **DEFERRED** to the post-ship design
wave — §6's prefills land via the existing `AddActivityView` → `ActivityEditorView` flow (prefill
loaded, confirmation = saving); **§9 amended 2026-08-11 ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)):
the catch-up frames gate the rendering** — approved frames precede UI code; the non-visual
layer is not gated. Full cut + ambiguity resolutions
(I1–I7, incl. the all-dormant header state and the owner-device first-launch note):
[`../../audit/AI_audit/SPEC_14_FEASIBILITY.md`](../../audit/AI_audit/SPEC_14_FEASIBILITY.md).
**Scope:** iOS client ONLY. The server contract, engine, wire shape, ADR-0004/0005, and the
push backends are **untouched** — this is a hard constraint, not a preference. Everything
here is client policy layered over the existing `getWeather → evaluateAll` contract.

---

## Context

The whole-day scan is the app's serendipity feature and its cognitive-load problem: a card
saying "Perfect 3–9am" for an activity the user does at sunset is technically true and
practically noise. The owner's principle for this rework: **serendipity matters, but a
dashboard the user can trust at a glance matters more.**

The refactor: every Activity must carry a time-of-day range (the engine's existing `window`),
and the dashboard answers the closed question *"during MY hours, is it bad / good / perfect?"*
— rendered as a truthful per-hour color gradient instead of a flat verdict block. Discovery
survives *inside* the range (the best sub-window, the gradient's shape, the ±1h shoulders),
not across hours the user excluded on purpose.

Predecessor design: the Figma Screens page (`92:17`, file `t3ZRvcYPnSRPKElSLAFqmG`) already
designed the 5-screen wizard, the mandatory Range step, and the dormant "Set your range →"
first-launch cards. **This spec supersedes that page where they conflict** (§9) — the page
shows a rating word top-right and flat-color bars; both are replaced below.

Vocabulary used throughout:
- **Core range** — the hours the user picked (`window`, half-open `[startHour, endHour)`).
- **Flex hours** — the one shoulder hour each side watched when ±1h is on (§4).
- **Dormant** — an authored Activity with `window == nil`: stored, visible, never evaluated (§1).
- **Tier colors** — red / orange / green = bad / good / perfect. Ordered red < orange < green.

---

## 1. Mandatory ranges + the dormancy model

`AuthoredActivity.window` **stays `Optional`**. `nil` no longer means "whole day" — it means
**dormant**. Mandatory-ness is a gate, not a type change:

- A dormant Activity renders as the designed "Set your range →" card (Figma `92:17`), is
  **excluded from the `/rating` POST body**, and is **excluded from the device snapshot**
  (when the §9-of-#6c registration client is built). It can never rate, never push, never
  reach the server window-less. The wizard's Range step is the only door out of dormancy.
- An **all-dormant dashboard makes no network call.** First launch seeds **all four**
  template cards dormant *(amended 2026-08-13, owner ruling: the Figma Empty — Showcase
  frame is authoritative over this spec's earlier "two" — the full catalog shows)*;
  nothing POSTs until the first range is confirmed. "Checking conditions…"
  appears only once ≥1 Activity is live.
- **Whole-day Activities no longer exist.** Delete the editor's "Only at certain hours"
  toggle (`ActivityEditorView.windowSection`, `ActivityDraft.windowEnabled`) and the
  "turn the window off for whole-day" validation copy in `AuthoredActivity.validationIssues`
  (the 0–23 bounds and `startHour == endHour` rejections stay; the copy just stops offering
  whole-day as the fix).
- No migration machinery: the app is not live. Any window-less Activity found in the store
  (dev installs) simply renders dormant.

## 2. The card (`ActivityCardView` / `TimelineBarView`)

- **Bar = the day axis, exactly as today** (the day's real hour span; nocturnal widening
  unchanged). Owner-chosen for cross-card comparability: every card on a response shares the
  axis, so ten activities tell one story.
- **The range renders as a gradient slice** inside the axis: a `LinearGradient` with **one
  color stop per hour boundary** (truthful — a green-orange-green afternoon renders as
  exactly that), soft blends between stops. Flat-color fill (`fillColor(for:)`) is deleted.
- **No rating word on the card** (owner decision "C"). Color carries quality; words are
  opt-in via the phrases toggle (§5). VoiceOver keeps the full spoken summary (rating word +
  times) regardless — the C decision is visual only.
- **Sublabel gains the best-stretch time:** "Today · 6–8pm" (from the server day's
  `startIndex`/`endIndex` via `TimeDeriver`), matching push copy word-for-word so a tapped
  push lands on its own receipt. Nocturnal: "Tonight · 11pm–2am".
- **All-bad range** (server `rating: null` ⇒ every hour in range is Bad): the slice renders
  **solid red**, sublabel plain "Today"/"Tonight" (no time — there is no stretch), phrase
  slot (§5) reads "Nothing in your range". The gray empty track is hereby reserved for
  **no data** (loading/error) only — bad weather is always painted, never absent.
- **Everything else on the card is unchanged:** icon + label, first-3 metric chips (valued
  at the best stretch's start hour; neutral catalog names on a red day), overlaid gear.

## 3. Per-hour quality — the on-device evaluator

New pure service (suggested: `Services/HourQuality.swift`) mirroring the server's
`evaluateHour` rule over `hours[]` + the Activity's own thresholds:

- any **required** threshold fails → red; only **optional** thresholds fail → orange; all
  pass → green;
- a `null`/missing metric value **fails** its threshold (the server's B2 rule — absent data
  is never silently fine);
- flag thresholds (`forbidTrue`) fail on `true`, per the server.

**Pinned invariant: the server's day rating is truth.** The greenest run of the client
gradient must coincide with the server's returned window for that day; any disagreement is
a client bug. A fixture test against `RealBackendResponseFixture` enforces this (§10).

## 4. ±1h flexibility

- Per-activity toggle, **strict (off) by default**. Stored on `AuthoredActivity`
  (e.g. `flexible: Bool`) — client-only field, never serialized to the wire shape itself.
- **Flexibility widens the real window**: a flexible 4–7pm Activity *sends* 3–8pm — in the
  `/rating` projection (`activityInput`) and in the device snapshot. The rating, digest,
  and Perfect-window push all see the widened window; a Perfect that exists only in a flex
  hour rates the day and fires the push, because the user declared they'd take it.
- **Clamp, never wrap (diurnal):** `startHour-1` floors at 0, `endHour+1` caps at 23. A
  naive 9am–11pm → 8am–`0` would flip `startHour > endHour` and silently reclassify the
  Activity as nocturnal night-stitch, changing its `days[]` shape. Nocturnal (already
  wrapped) ranges widen freely across midnight (10pm–4am → 9pm–5am).
- **Rendering:** the slice spans the widened window; the flex shoulder hours render
  **visually softer** (reduced opacity / faded edge) so the core range still reads as the
  user's own. Review step and detail header state it as "6–10am · flexible".
- **Wizard placement:** in the Range step (and Edit range), directly under the pickers.
  Copy: **"Flexible by an hour"** — caption *"We'll also watch the hour before and after
  your window."* ("Watch", not "widen" — the user's mental model keeps their window.)

## 5. The phrases toggle (Settings)

- **Exactly one new Settings row** (copy TBD in the design pass): default **off** — the
  card shows no words (§2). On: the card shows a trajectory phrase ("Good, turning
  perfect").
- **Reduction rule (pinned):** phrase keyed on (first hour tier, last hour tier) → 9 cases;
  if any interior hour falls **outside the closed tier span** between first and last (e.g.
  green→green with an orange dip), override to the single **"Mixed conditions"** phrase.
  Ten strings, one rule — the phrase can never contradict the gradient.
- **Accessibility force:** when the system's **Differentiate Without Color** setting is on,
  phrases force-enable (Settings row shows on/locked). Color is never the only carrier.

## 6. Templates, wizard, first launch

Per the designed 5-screen wizard (Add sheet → Name/Icon — scratch only → **Range** → Metrics → Review):
templates carry **Range-step prefills, never active defaults**. The user must see and
confirm a range before the Activity exists (or leaves dormancy). Prefills:

| Template | Prefill | Note |
|---|---|---|
| Cycling | 6–10am | as designed on `92:17` |
| Fishing Lite | 3–7pm | as designed |
| Running | 6–9am | owner-picked this session |
| Stargazing | 10pm–4am | already authored (nocturnal) |
| From scratch | 6–10am | the design's "Morning Ride" example |

`SeedTemplates` gains the prefill values (as prefill metadata or as the `window` value the
wizard preloads-but-requires-confirmation-of — implementation's choice, but **first-launch
seeds must land dormant**, i.e. `window: nil` in the store until confirmed).

**Delete-all re-seeds (owner rulings 2026-08-12):** deleting the last Activity re-seeds the
**non-dismissed** template cards dormant (Figma Empty—Showcase `111:32`). Dismissed templates
stay dismissed (preferences) — a dismissal survives the re-seed. If **every** template is
dismissed, the dashboard renders the **true-empty state** instead: an "Add activities +" CTA
opening the Add flow (the shipped Add sheet; the wizard when it lands). Standing invariant:
the dashboard always offers a next action — showcase or Add CTA — never a dead end.

## 7. Detail page redesign (`ActivityDetailView`)

The per-hour metric rows are deleted ("too many numbers, too many things to infer" — owner).
New skeleton, top to bottom:

1. **Header:** name/icon + the range stated once ("Your window: 4–7pm daily" /
   "10pm–4am nightly", "· flexible" when on) + **Edit range**.
2. **Setup summary, stated once:** metrics + thresholds as one compact block ("Temp 15–32°
   required · Wind ≤25 optional · …") + **Edit metrics / Edit thresholds**. Thresholds
   don't vary by hour; repeating them 24× was noise.
3. **The week: 7 day rows (6 for nocturnal)** — each just *day name · best-stretch time ·
   full-width **range-zoomed** gradient bar*. The bar's axis is the range itself (the Q1
   option rejected for the dashboard finds its correct surface here): since the range is
   identical every day, all rows share the axis and stack with perfect vertical alignment —
   comparing days is one vertical scan of where the green sits. Axis labels once under the
   stack, not per row. Same slice component, same language rules as the card (time sublabel
   always; phrases + Differentiate Without Color behavior identical — one dialect, not two).
4. **Tap a day row to expand it** — progressive disclosure: the tapped day reveals its
   hourly chips (range hours only, one day at a time). This is the only surviving home of
   per-hour numbers, and the answer to "why is 5pm orange?". Collapsed by default.

## 8. Nocturnal parity — no special rules

Owner-confirmed: **no special treatment at all.** The night-stitch machinery already carries
everything: card axis widening past midnight (existing), continuous gradient across
midnight, "Tonight · …" phrasing, night rows ("Tonight", "Tomorrow night", possibly 6 not
7), range-zoomed detail bars reading 10pm → 4am left-to-right, free ±1h widening (§4),
"Nothing in your range tonight" on an all-bad night.

## 9. Figma supersession (prerequisite/parallel — owner + Figma agent)

This spec evolves page `92:17` (see [`docs/design/FIGMA.md`](../../design/FIGMA.md) for the Figma
workflow and approval gate). The designed frames need a catch-up pass:

- **Card:** drop the rating word top-right; flat bar → gradient slice; sublabel "Today ·
  6–8pm"; add the all-red state.
- **Detail:** replace the per-hour rows screen with the §7 skeleton (header / setup-once /
  aligned range-zoomed week / tap-to-expand).
- **Range step:** add the "Flexible by an hour" toggle + caption.
- **Settings:** add the phrases row.
- Dormant cards, wizard structure, prefills: already designed — unchanged.

**Amended 2026-08-11 ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)): this pass is a
prerequisite, not a parallel track.** Card/detail/Settings rendering lands only after the
owner approves these frames; the non-visual layer (§1 store semantics, §3 `HourQuality`,
projections, tests) is not gated.

## 10. Tests (all iOS; `npm test` is untouched — nothing server-side changes)

- **HourQualityTests** — the `evaluateHour` mirror: required/optional/flag semantics, null
  fails, and the §3 invariant against `RealBackendResponseFixture` (greenest run ==
  server window).
- **Gradient mapping** — hour tiers → ordered color stops; zigzag preserved; all-bad →
  solid red; flex shoulders marked distinct from core hours.
- **Phrase reduction** — all 9 (first, last) cases; interior-escape → "Mixed conditions";
  flat cases; all-bad copy.
- **Dormancy** — window-less Activity excluded from the POST projection and (when built)
  the snapshot; all-dormant → no request issued; dormant card state chosen; delete-all
  re-seeds the non-dismissed showcase (dismissals survive — §6); all-dismissed + delete-all
  → the true-empty Add-CTA state.
- **±1h** — widened projection (rating body); diurnal clamp at 0/23 (incl. the 9am–11pm
  no-flip case); nocturnal free wrap; strict default.
- **Prefills** — `SeedTemplateTests` updated: prefill table above; first-launch seeds land
  dormant.
- **Card** — sublabel time formatting (diurnal/nocturnal/red-day), rating word absent by
  default, phrase present when toggled, chips unchanged.
- **Detail** — 7-vs-6 rows, aligned range axis, collapsed-by-default expansion.
- **Settings** — phrases row default off; Differentiate Without Color force-enables.

## Acceptance criteria

1. No Activity can be created or edited into existence without confirming a range; dormant
   Activities render the "Set your range →" card and never appear in any request body.
2. Every live card shows the day-axis bar with a truthful per-hour gradient slice, no
   rating word (default), and the "Today/Tonight · <time>" sublabel matching push copy.
3. An all-bad day is a solid red slice — visibly bad, never absent.
4. A flexible Activity demonstrably sends the widened window, and a diurnal range touching
   0/23 clamps without flipping nocturnal.
5. The detail page is: range once, setup once, aligned range-zoomed week, hourly numbers
   only behind a tap.
6. The phrases toggle works, and phrases force on under Differentiate Without Color.
7. Nocturnal Activities pass every one of the above with zero special-case code beyond the
   existing night-stitch conventions.
8. Server, wire contract, and push backends: zero diffs.

## Related artifacts

- Figma: page `92:17` (predecessor design; §9 supersession) · [`docs/design/FIGMA.md`](../../design/FIGMA.md)
- ADR-0004 (card reads `days[0]`; unchanged) · ADR-0005 (`window` optional on the wire; unchanged —
  mandatory-ness is client policy)
- `implement-spec-issue-6c-registration-and-digest.md` §9 (the future registration client
  inherits the dormancy exclusion, §1)
- Issue #14 (GitHub) — to be created from this spec
