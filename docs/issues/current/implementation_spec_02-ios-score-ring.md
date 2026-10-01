# Implementation spec 02 — iOS score ring card + Activity Detail v3 (ROADMAP item 16, client half)

> Work order for an implementing agent. Self-contained: read this file, then [ADR-0011](../../adr/0011-day-score.md) (accepted contract), [ADR-0007](../../adr/0007-client-side-mirrors.md) (mirror rules), [ADR-0008](../../adr/0008-figma-first-ui-gate.md) (frames precede code — **satisfied**: the frames below were owner-approved 2026-09-30), and [FIGMA.md](../../design/FIGMA.md) §1 (tool gotchas) + §11. The iOS app lives under `ios/TimeIt/`; its conventions are in `ios/` docs and the existing views. Written 2026-10-01; an audit agent cross-checks after completion — leave checkboxes honest.
>
> **Design truth is the Figma frames, not this file.** Read them live via the Figma MCP tools (file key `t3ZRvcYPnSRPKElSLAFqmG`): Card v2 "Score ring" `458:394`, Detail v3 `456:358` (6am) and `464:2348` (7am). Pull geometry, spacing, type styles, and token bindings from the nodes; this file carries only behavior and contracts.

## Depends on

Spec 01 (server `score` field) merged, including `tests/fixtures/day-score-examples.json`. If building before that merge, decode against local fixtures — the decoder rule below makes the order safe.

## Hard constraints

- **Decoder**: `days[]` gains optional `score` (Int). Absent, `null`, or non-integer → `nil` (the 2026-07-12 hardening posture: nothing about this field can ever fail the decode). Existing `Rating`/`.unknown` hardening untouched.
- **Server untouched.** No changes outside `ios/`.
- Dark mode: **deferred wave** — light only, colors through the shared `Theme` tokens so dark lands later for free.
- Reduce Motion: every animation in this spec goes static under it. HIG tap targets ≥44pt (visual size may be smaller — the `contentShape` pattern used by the beta pill).
- The plain-language rule for *onboarding* does not apply here, but the v2 card's chip is **hours-only** (`6 – 10am`, no `Range ·` prefix) — that is the approved frame, and on the v2 card it supersedes the shipped chip copy. Do not change the chip on any surface the frames don't cover.

## Card v2 — "Score ring" (replaces the card layout on the dashboard)

- [x] 48pt ring whose arc length = `score`/100; the numeral inside; "Score" caption — geometry/type from frame `458:394`. Numeral (and ring tint) color follows the day's rating tier.
- [x] `score == nil` → ring empty (no arc, no numeral fabrication) — match the frame's null state.
- [x] Hour strip **scoped to the Range** (one segment per Range hour, green/orange/red by that hour's tier), boundary hour numerals in the frame's label style — replaces the 6am–12am day-axis bar on this card.
- [x] Per-hour tiers come from the existing client threshold-evaluation mirror (ADR-0007); per-hour *scores* are not on the wire and are not needed for the card.
- [x] Rated + null states both per frame; existing card behaviors that the frame keeps (chips with live values, tap → detail) survive.

## Activity Detail v3 (today-only rebuild)

- [x] Hero: ring + rating word + hour stepper (`− 6am +`), per frames `456:358`/`464:2348`. Strip: selected hour at 100% opacity, rest at 35%.
- [x] **Stepper ruling (owner, 2026-09-30):** the stepper MAY step past either end of the Range. Outside the Range: the colored hour pills are **not shown** (values still shown per the frames' metric cards, uncolored). Returning to the Range = **tap the pill itself**, with a click-feedback animation on the tap. `−` dims at the absolute lower bound (frame behavior at the Range start now applies at the walkable lower edge).
- [x] Three metric cards (two per row, square): glyph, name, the selected hour's value colored by that hour's verdict, threshold gauge (track = metric domain, tinted band = user's band, dot = hour value, band min/max numerals) — all geometry from the frames.
- [x] Selected-hour values read straight from the decoded `hours[]` (no new backend — ADR-0011 client rule).
- [x] Week rows and the hour-grid are **removed** (today-only ruling); the Edit range / Edit metrics list stays.
- [x] Hour stepping animates in the smart-animate spirit of the 6am↔7am prototype link; static under Reduce Motion.

## Tests

- [x] Decoder tests: `score` present / absent / null / wrong-type → the documented outcomes.
- [x] Per-hour tier/score mirror pinned against `tests/fixtures/day-score-examples.json` (the shared table from spec 01 — one file binds both sides, the `clock-labels.json` mold).
- [x] Stepper logic unit tests: bounds, out-of-range pill hiding, snap-back target (first/nearest Range hour — match the frames; if ambiguous, nearest Range end).
- [x] Existing test suite green in Xcode.

## Done means

App builds and runs; all boxes ticked truthfully; no server diffs; dark mode untouched. Commit message prefix: `feat(ios):`. Do not push; the audit pass runs on your branch/worktree state.
