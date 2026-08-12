# FIGMA.md — Figma reference of record (access, addresses, workflow)

> Consolidated 2026-08-10 from `figma_foundations_multi-page_implementation.md` (the build spec, implemented 2026-07-18) and `handoff-figma-design-iteration.md` (the working handoff) — both deleted; git history keeps them. This file is the reference of record for Figma **access, addresses (fileKey, page map, node IDs), and workflow rules**. Design *values* live in the Figma file itself (design truth — agent-queryable via the Figma MCP server) and in code (`Theme.swift`, the views — shipped truth); docs never carry the values ([ADR-0009](../adr/0009-tiered-doc-truth.md)).

**File:** "Main - Time it" · **fileKey:** `t3ZRvcYPnSRPKElSLAFqmG`

**History:** design system v1 (foundations, component sheets, Light/Dark screen galleries incl. all 9 wizard frames) built 2026-07-18; #5c location frames built 2026-07-30, approved and shipped 2026-08-01; the "mess around" page is the owner's brainstorm scratchpad.

---

## 1. Access & tool gotchas (hard-won — read before any Figma call)

- **`get_metadata` is broken for this file** — it returns only 1 of ~21 pages, every time. Enumerate pages with `use_figma` (load the `figma-use` skill first): `return figma.root.children.map(p => ({ name: p.name, id: p.id }))`.
- Page switch via `figma.setCurrentPageAsync(...)` — **at most once per `use_figma` call**; fan multi-page work out as parallel calls. `figma.currentPage` resets on every call.
- Tokens are file-global: `figma.variables.getLocalVariableCollectionsAsync()` — no page switch needed.
- `figma.createAutoLayout()` frames get a **default white fill** — set `fills = []` on every container meant to be transparent.
- `setBoundVariableForPaint` returns a **new** paint — capture and reassign the fills array.
- Text edits: load the node's current fonts first (`getStyledTextSegments(['fontName'])` → `loadFontAsync`) or writes throw.
- New page-level nodes land at (0,0) — place explicitly (Screens grid: y=200, x steps of 460).
- **Instance paint-opacity quirk:** paint-level `opacity` on a component fill does not propagate to instances — re-stamp the main component's `fills` onto each new instance.
- Icons are **SF Symbol glyphs as SF Pro text nodes**. On macOS use `figma.util.getSfSymbolCharacter(name)` (unknown names throw — surface, don't substitute). On **Linux** (no SF fonts/AppKit) use the verified PUA codepoints below — **never guess a PUA value; ask the owner** to verify new ones on the Mac side:

| Symbol | Codepoint |
|---|---|
| `location.slash` | `U+10062C` |
| `magnifyingglass` | `U+1002AB` |
| `wifi.exclamationmark` | `U+100665` |
| `wifi.slash` | `U+100648` |

- The **Apple iOS 18 kit** is subscribed for generic controls (status bars, buttons, toggles — do not rebuild them); `search_design_system` library key: `lk-df324a089628d1c7c7b0d29e676b621790cdcac1c725b49a3cfbb974a362f8201ac643e1fbccc855970ab22dabd6897ef20e72a7feda01014ddd59daf3f6ed52`.

## 2. Page map (verified 2026-07-31; positions may drift — enumerate, don't assume)

| Page | node-id | Notes |
|---|---|---|
| wizard mind map | `39:4` | range-first wizard concept (owner WIP; `App Colors` arrows bind here) |
| SwiftUI as-built | `74:4` | mirrors the #5a/#5b build — the code-truth reference |
| Cover | `92:2` | |
| **mess around** | `179:5` | the owner's brainstorm scratchpad |
| Color / Typography / Spacing | `92:4` / `92:5` / `92:6` | foundations |
| Metric Chip · Animations · Activity Card · Ghost Add Card · Header · Showcase Card · Template Row · Range Picker Row · Review Row | `92:8` · `127:575` · `92:9` · `92:10` · `92:11` · `92:12` · `92:13` · `92:14` · `92:15` | component sheets |
| Screens — Light | `92:17` | 18 frames incl. the wizard set + #5c pair |
| Screens — Dark | `92:18` | Dark twins (`explicitVariableModes` Semantic→Dark at frame root — clone from them) |

Key Screens — Light frames: Dashboard Loaded `111:2` · Loading `111:17` · Empty—Showcase `111:32` (*no-activities*, not no-location) · Error `111:47` · Activity Detail `111:62` · Settings `111:77` · Activity Editor `111:92` · Wizard Add Sheet `111:372` · Name+Icon `111:387` · Range Same-Day `111:402` · Range Overnight `111:417` · Range Error `111:432` · Metrics Template `111:447` · Metrics Custom `111:462` · Review Day `111:477` · Review Night `111:492` · Dashboard/No-Location `172:492` · City Picker `172:1266` (Dark twins `173:996` / `173:1295`).

## 3. Token truth (the collection-authority ruling — resolves the old docs' contradiction)

- **`Semantic`** (`VariableCollectionId 91:3`, modes Light `91:1` / Dark `91:2`) — **the layer to bind, nothing else**: `surface/*`, `text/*`, `separator`, `rating/*`, `accent/*`, `timeline/track`, `chip/{green,orange,red,neutral}/{bg,text}`, `gradient/{cool,mid,hot}/{start,end}`. Key IDs (`VariableID:91:NNN`): surface/background=206 · surface/card=207 · text/primary=209 · text/secondary=210 · text/on-gradient=211 · separator=212 · rating/perfect=213 · rating/good=214 · accent/interactive=215 · timeline/track=217 · chip/green/bg=218 · chip/neutral/bg=221 · gradients cool=226/227 · mid=228/229 · hot=230/231.
- **`Layout`** (`91:4`) — `space/{xs,sm,md,lg,xl}` = 4·8·10·14·16 · `radius/{sm,md,lg,full}` = 6·10·16·999.
- **`Primitives`** — raw palette; reference via Semantic, never bind directly to screens.
- **`Theme colors`** (`36:4`) — the **frozen as-built mirror of `Theme.swift`**; the as-built page binds to it. Do not modify, do not bind new work. Retire it only when the spec 14 rendering wave replaces `Theme.swift`'s raw hex with adaptive tokens.
- **`App Colors`** (`11:64`) — **legacy**, kept only because the wizard-mind-map arrows bind to it. Never bind new work.

**Redundancy rule (owner's standing instruction):** before creating any token, component, or style, check the foundations — they match the iOS app letter-for-letter. New primitives are a last resort.

## 4. Header temp encoding + band profiles (owner-approved 2026-07-18)

The header gradient is a **temperature encoding for the header only** (cool / mid / hot), never buttons/accents; the exact gradient stops live in the file's `Semantic` `gradient/*` variables (§3 IDs). The as-built ocean-blue gradient survives only on the as-built page (`Theme colors`, §3). Bands are region-profiled by the **forecast location's** country, driven by `hours[0].temp`: Default `<20` / `20–32` / `≥33`; UAE (`AE`) `≤33` / `34–37` / `>37` (table extensible by country code; app-side detection = reverse-geocode → country code).

**Values (palette, chip colours, typography):** read them from the file — the `Semantic` collection (§3 key IDs), the 14 `TimeIt/*` text styles (SF Pro only), the component sheets (§2). Shipped values: `Theme.swift`. Docs carry no values ([ADR-0009](../adr/0009-tiered-doc-truth.md)). **Elevation:** exactly two levels (card, sheet). **Logo:** `Brand/App Icon` vector.

## 5. Design idioms (match, don't reinvent)

Four pinned idioms — **empty/error state**, **grouped list**, **sheet**, **card** — exist as drawn components and frames (§2 page map): measure them in the file, don't work from a doc. Screen frames are drawn at 393×852 (the canvas convention for new frames).

## 6. Workflow rules

- **Approval gate — frames precede code ([ADR-0008](../adr/0008-figma-first-ui-gate.md), the decision of record):** nothing user-visible is mirrored to code until the owner approves the frames. Scratch work lives on "mess around"; polished results graduate to the Screens pages.
- Load the `figma-use` skill before any `use_figma` call; ≤10 ops per call; return node IDs.
- The as-built page (`74:4`) and `Theme colors` stay untouched (frozen reference, §3).

## 7. Pending design pass — spec 14 catch-up (§9 of the spec)

The Screens-page frames predate spec 14; when this pass runs: card drops the rating word + flat bar → **gradient slice** + "Today · 6–8pm" sublabel + all-red state; detail screen → the §7 skeleton (header / setup-once / aligned range-zoomed week / tap-to-expand); Settings gains the phrases row. *(The ±1h flex toggle is deferred with spec 14's cut.)* Dormant cards, wizard structure, prefills: already designed — unchanged. **This pass gates the spec 14 rendering ([ADR-0008](../adr/0008-figma-first-ui-gate.md))** — approved frames precede UI code. Also in this backlog (push-client spec §1, same gate): the Settings "Notifications" row and the one-time dashboard callout.
