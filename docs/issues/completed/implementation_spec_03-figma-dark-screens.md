# Implementation spec 03 — Dark screens in Figma (Screens — Dark catch-up: ring card + Activity Detail v3)

> **Status 2026-10-01: built, auditor-verified, adversarially reviewed** — record in [FIGMA.md §11](../../design/FIGMA.md). Half B ran as written (ring card `487:400`; parity sweep clean, glyph-opacity drift fixed on seven nodes). Half A's clone+delete call hit the session permission gate; the auditor built the four twins itself (`491:711` / `491:773` / `491:835` / `491:897`) and the two old dark frames are **parked, not deleted**, pending the owner's confirmation. Correction found live: the nav `Back`/title text in `121:261` and the v3 frames binds **Semantic** (`accent/interactive` / `text/primary`), not the kit's `Labels/Primary` as the token-mapping section below guessed — the mode flip alone handles it. Open owner decisions: the decisions page linked from §11.

> Work order for two implementing agents (Figma-only — the deliverable is **frames**, not code). Written 2026-10-01 by the auditing agent from a **live** enumerate of the file (file key `t3ZRvcYPnSRPKElSLAFqmG`); an audit agent re-enumerates after completion — report exact node IDs, never claim what you did not verify. Read first: [FIGMA.md §1](../../design/FIGMA.md) (tool gotchas — hard-won, every one of them bites), §3 (token truth), §11 (the frames being twinned). Dark mode is a **deferred wave in the app** ([ROADMAP §Deferred](../ROADMAP.md)) — this is design-ahead work so the dark twins exist when that wave opens; nothing here changes code or the ADR-0008 gate state of the light frames.

## Why (the live diff, 2026-10-01)

| Row | Screens — Light `92:17` | Screens — Dark `92:18` | Gap |
|---|---|---|---|
| ACTIVITY CARDS | `424:485` rated · `424:512` null · **`458:394` Card v2 — B · Score ring** (+ archive A/C/D, notes) | `430:1025` rated · `430:1046` null | **no ring-card twin** |
| ACTIVITY DETAIL | after the light pass of 2026-10-01: `456:358` v3 6am · `464:2348` v3 7am · v3 Out of range · v3 Nocturnal (old `111:62` / `275:1535` deleted) | `121:261` Activity Detail · `275:1635` Nocturnal — both the **old §7 skeleton** (week rows + hourly chips, superseded by v3 in code) | **dark row is stale; no v3 twins** |
| every other row | 1:1 twins (dashboard states ×6 + pressed hero, wizard ×8, settings ×2, city picker) | same | none |

The shipped iOS app draws the score-ring card and Activity Detail v3 (spec 02, merged `f0f4571`); the dark page still shows the pre-v3 detail and no ring card. The two old dark detail frames are deleted and the dark row rebuilt as **clones of the light v3 frames under the Dark mode**, the same way every existing dark frame was made (§2: "Dark twins — `explicitVariableModes` Semantic→Dark at frame root — clone from them").

## Token mapping — what the mode flip does, and what it does not

The `Semantic` collection (`VariableCollectionId:91:3`, Light `91:1` / Dark `91:2`) is the only layer bound in the v3/ring-card frames; the auditor's node-level audit found **every fill bound** — the only unbound paints are the card hairline strokes and drop shadows (below). Setting `frame.explicitVariableModes = { 'VariableCollectionId:91:3': '91:2' }` on the cloned frame root flips all of these (Dark values read live from the file, listed here only so an agent can eyeball a screenshot — the file is the truth, not this table):

| Semantic variable | ID | Light → Dark | Used by (v3 / ring card) |
|---|---|---|---|
| `surface/background` | `91:206` | #f2f2f7 → #000000 | frame root, stepper button circles |
| `surface/card` | `91:207` | #ffffff → #1c1c1e | hero, metric cards, edit list, card |
| `text/primary` | `91:209` | #1c1c1e → #f2f2f7 | stepper hour, activity name, glyphs |
| `text/secondary` | `91:210` | #8e8e93 → #98989f | metric names, bound numerals, chevrons, "Score", strip labels |
| `text/on-gradient` | `91:211` | #ffffff → #ffffff | pill numerals |
| `separator` | `91:212` | #3c3c43 18% → #545458 60% | edit-list divider |
| `rating/perfect` · `rating/good` · `rating/bad` | `91:213` · `91:214` · `254:5` | #34c759→#30d158 · #ff9500→#ff9f0a · #ff3b30→#ff453a | ring arc + numeral, rating word, pills, dots, band tint |
| `accent/interactive` | `91:215` | #007aff → #0a84ff | − / +, Edit rows, Range chip text |
| `timeline/track` | `91:217` | #f2f2f7 → #2c2c2e | gauge track, out-of-range pills |
| `chip/green/text` · `chip/orange/text` | `91:222` · `91:223` | deep → the raw tier colour | metric value text by verdict |

**Not flipped by the mode — handle explicitly, matching the file's existing dark convention (verified on `121:261` and `430:1025`):**
- **Card hairline stroke** `#000000` 6%, 0.5 and **drop shadow** `#000000` 8%, r=3: the existing dark frames keep them **unchanged** (`430:1027` carries the same stroke + shadow). Keep them. Do not invent a dark stroke.
- **Status bar + home indicator** (Apple iOS 18 kit instances, `Status Bar - iPhone` / `Home Indicator`): their glyphs are hardcoded white in the dark frames. Before deleting `121:261`, **clone its two instances** (`121:262`, `121:263`) and use those on every new dark frame in place of the light clone's instances (same position). Equally the nav-bar `Back`/title text binds to the kit variable `Labels/Primary` (`VariableID:690043185feb027275f6d6e9d55eb75a2a3238d5/3083:331`) — copy whatever `121:261`'s nav text does (read its bindings first) so the title reads light-on-dark.
- **12%-tint paints** (the Range chip background, band tint): `setBoundVariableForPaint` drops opacity (§1) — a clone keeps them, but if you re-bind anything, reassign the opacity afterwards.

## Frames to build (both agents; disjoint)

**Half A — ACTIVITY DETAIL row (one agent).** On `92:18`:
1. Harvest `121:262` + `121:263` (status bar, home indicator) from `121:261` and the nav text bindings. Then **delete** `121:261` and `275:1635`.
2. Clone each light v3 frame to the dark page at the same x as its light sibling, y = the dark row's y (2267): `456:358` → "Activity Detail v3 / 6am", `464:2348` → "Activity Detail v3 / 7am", plus the two frames the light pass added ("Activity Detail v3 / Out of range (5am)", "Activity Detail v3 / Nocturnal (10pm)" — IDs from the auditor's dispatch). Set `explicitVariableModes` Semantic→Dark on each root; swap in the harvested status bar/home indicator; clone each light frame's behaviour note (the TEXT node under it) too.
3. Re-create the prototype links between the dark twins (6am + → 7am, 7am − → 6am, 6am − → Out of range, Out of range + → 6am, Out of range strip tap → 6am), smart animate like the light ones — reactions cloned with a frame still point at the **light** destinations; retarget them.

**Half B — ACTIVITY CARDS row + parity read (one agent).** On `92:18`:
1. Clone `458:394` "Card v2 — B · Score ring" to x=980, y=1471 (the row's next 460-grid slot), mode→Dark, name unchanged. Both states inside it (Rated 86 / Nothing in range) come along; the owner-queued null-frame question (score `31` on a `rating`-null card) is **not** touched on either page — it is an open owner decision (ADR-0011 amendment vs the queued correction), surfaced separately.
2. Read-only parity sweep of the eleven existing twin pairs that stay (dashboard ×7, wizard ×8, settings ×2, city picker): for each pair compare every TEXT node's `characters` and report mismatches (copy drift between light and dark is a known failure mode — §10 found two). Report only; fix nothing.

## Per-frame acceptance criteria (the auditor checks each)
- Frame root: 393×852 (card: 393×228), `explicitVariableModes` = `{ 'VariableCollectionId:91:3': '91:2' }`, fill bound to `surface/background`.
- Screenshot reads as the light frame's exact layout in dark: no light-grey card on black, no dark text on dark card, status-bar/home-indicator glyphs white, nav title light.
- Zero NEW unbound solid paints versus the light source (the audit script counts them: the only unbound paints are the hairline strokes and the kit's white glyphs).
- Node count and child names equal to the light source (plus/minus the swapped kit instances).
- Prototype links present and pointing at dark frames only.
- Nothing else on the page moved: the untouched frames' `x`/`y` equal the auditor's pre-pass enumerate.

## Non-goals (explicit)
- No code; no `Theme.swift` adaptive tokens — the dark wave in the app stays deferred.
- No dark twins for the CARD v2 archive (A/C/D) or the notes text — archive is light-only by design.
- No dashboard-state redraws with the ring card (both pages still show the main-look card in Dashboard / Loaded, Push Callout, First Launch — an owner-queue finding, not this pass).
- No day-jump control, no nocturnal/out-of-range invention beyond cloning the light frames.
- No new variables, styles, or components; `Theme colors` and `App Colors` collections untouched (§3).

## Done means
Both halves reported with node IDs + an end-of-pass enumerate of the touched rows; auditor-verified by independent enumerate + screenshots; adversarial review findings routed; FIGMA.md §2/§11 addresses swept in the same doc commit as the ROADMAP/STATUS lines.
