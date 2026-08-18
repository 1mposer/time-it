# FIGMA.md — Figma reference of record (access, addresses, workflow)

> Consolidated 2026-08-10 from `figma_foundations_multi-page_implementation.md` (the build spec, implemented 2026-07-18) and `handoff-figma-design-iteration.md` (the working handoff) — both deleted; git history keeps them. This file is the reference of record for Figma **access, addresses (fileKey, page map, node IDs), and workflow rules**. Design *values* live in the Figma file itself (design truth — agent-queryable via the Figma MCP server) and in code (`Theme.swift`, the views — shipped truth); docs never carry the values ([ADR-0009](../adr/0009-tiered-doc-truth.md)).

**File:** "Main - Time it" · **fileKey:** `t3ZRvcYPnSRPKElSLAFqmG`

**History:** design system v1 (foundations, component sheets, Light/Dark screen galleries incl. all 9 wizard frames) built 2026-07-18; #5c location frames built 2026-07-30, approved and shipped 2026-08-01; spec 14 catch-up frames built 2026-08-13, **owner-approved 2026-08-14** (§7); the "mess around" page is the owner's brainstorm scratchpad.

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
| Screens — Light | `92:17` | 22 frames incl. the wizard set + #5c pair |
| Screens — Dark | `92:18` | Dark twins (`explicitVariableModes` Semantic→Dark at frame root — clone from them) |
| Conditions Tier Sequence | `255:1311` | tier-gradient component lab — owner tuning surface; geometry mirrors TierGradient.swift |

Key Screens — Light frames: Dashboard Loaded `111:2` · Loading `111:17` · Empty—Showcase `111:32` (*all-dormant showcase*, not no-location) · Error `111:47` · Activity Detail `111:62` · Settings `111:77` · Activity Editor `111:92` · Wizard Add Sheet `111:372` · Name+Icon `111:387` · Range Same-Day `111:402` · Range Overnight `111:417` · Range Error `111:432` · Metrics Template `111:447` · Metrics Custom `111:462` · Review Day `111:477` · Review Night `111:492` · Dashboard/No-Location `172:492` · City Picker `172:1266` (Dark twins `173:996` / `173:1295`). Added by the 2026-08-13 catch-up pass (Dark twins in parens): Dashboard Empty—True `266:1651` (`266:1764`) · Dashboard Push Callout `266:5` (`266:1562`) · Settings phrases-locked state `265:5` (`265:14`) · Activity Detail — Nocturnal `275:1535` (`275:1635`).

## 3. Token truth (the collection-authority ruling — resolves the old docs' contradiction)

- **`Semantic`** (`VariableCollectionId 91:3`, modes Light `91:1` / Dark `91:2`) — **the layer to bind, nothing else**: `surface/*`, `text/*`, `separator`, `rating/*`, `accent/*`, `timeline/track`, `chip/{green,orange,red,neutral}/{bg,text}`, `gradient/{cool,mid,hot}/{start,end}`. Key IDs (`VariableID:91:NNN`): surface/background=206 · surface/card=207 · text/primary=209 · text/secondary=210 · text/on-gradient=211 · separator=212 · rating/perfect=213 · rating/good=214 · accent/interactive=215 · timeline/track=217 · chip/green/bg=218 · chip/neutral/bg=221 · gradients cool=226/227 · mid=228/229 · hot=230/231 · **rating/bad=`VariableID:254:5`** (added 2026-08-13 — aliases `red/light`/`red/dark`; the HourTier red for gradient slices; gray track = no-data only) · **rating/blend=`VariableID:303:6`** (added 2026-08-14 — aliases primitive `yellow/light` `303:5`; the yellow blend waypoint at green↔orange gradient boundaries only, never a tier; the Dark value is a placeholder for the deferred dark wave).
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

## 7. Spec 14 catch-up pass — frames built 2026-08-13, owner-approved 2026-08-14

The pass ran 2026-08-13 (agent), mirrored on Light `92:17` + Dark `92:18`. Delivered: **card** — rating word dropped, flat highlight → per-hour **gradient slice** (stops bound to `rating/*` incl. the new `rating/bad`), best-stretch sublabel ("Today · 7–10am"), `Rating=None` repurposed as the **all-red day** (solid red slice, plain day name, visible "Nothing in your range" phrase, neutral chips), hidden-by-default Phrase slot on every variant, the I3 **provisional phrase strings** review block on the Activity Card sheet (`92:9`); **detail** — the §7 skeleton (window header + Edit range / setup-once thresholds / 7 aligned range-zoomed day rows / axis once / Today expanded with hourly chips); **Settings** — NOTIFICATIONS row + DASHBOARD "Show phrases" row (both off) + the phrases-locked state frame (Differentiate Without Color); **new frames** — Dashboard Empty—True ("Add activities +" CTA) and Dashboard Push Callout (push-client spec §1). Frame/node ids: §2. *(The ±1h flex toggle stays deferred with spec 14's cut — the Range step is untouched.)* Dormant cards, wizard structure, prefills: already designed — unchanged.

**Post-audit wrap-up (same day):** card-stack overlap fixed on Dashboard Loaded + Push Callout, both pages (the all-red card's phrase row grew it 22px; the cards/ghost below now clear it); component-default hygiene on the card set — Perfect/Good sublabels carry a best-stretch time and `Rating=None` defaults to neutral catalog-name chips, so instancing without overrides ships spec-correct defaults; the Push Callout's stale valued-chip overrides replaced with the Loaded frame's neutral set; **Activity Detail — Nocturnal** added (`275:1535` / dark `275:1635`) — Stargazing, "10pm – 4am nightly" window header, 6 night-bucket rows ("Tonight"/"Tomorrow night"…, evening-keyed, red night mid-week, "Tonight 10pm–2am" agreeing with the Loaded card), axis re-zoomed 10pm/1am/4am — completing the detail skeleton's nocturnal story. Accepted as-is (recorded compromises): hand-drawn switches, static per-variant slice geometry.

**Audit fixes (2026-08-13, second pass):** the card set's Day sublabel turned out to be a *single shared text property* (`Day#103:4`) across all three variants — any per-variant default edit silently overwrote the other two, which is how the best-stretch default leaked onto the red-day variant; `Rating=None`'s Day now rides its own **`Day (red)` property** defaulting to plain "Today", while `Day` keeps "Today · 7–10am" for Perfect/Good (instances keep overriding either normally). The nocturnal detail's five varied bars were re-based from the cloned 4-hour stop layout to the true **6-hour TierGradient layout** (hour midpoints at n/12, pinned edges), so every bar now agrees with its time label and the 10pm/1am/4am axis; the hidden leftover time labels inside the red rows (diurnal Tomorrow + nocturnal Friday, both pages) were deleted.

**The ADR-0008 gate is open for this pass:** the owner approved these frames **2026-08-14** — spec 14 rendering and the push client's opt-in UI may now be mirrored to code against them ([ADR-0008](../adr/0008-figma-first-ui-gate.md) stays the standing rule for *future* frames); status: [ROADMAP items 5–7](../issues/ROADMAP.md). *(The spec 14 rendering was mirrored the same day — ROADMAP item 6 is the record.)*

**Push Callout ✕ un-clipped (2026-08-17, item 7 audit follow-up — W2):** the callout's ✕ dismiss glyph existed in the design all along but sat in-flow past the 365px frame width and was clipped invisible — the approved render showed no dismiss affordance while the shipped code drew one. Fixed by a contained Figma agent: the ✕ (`266:131` light / `266:1575` dark, SF Pro Semibold 13, fill bound to `text/secondary` `VariableID:91:210`) now lives in a 34×34 absolute-positioned trailing "Dismiss" container (`314:5` / `314:6`), matching the shipped geometry; nothing else moved. Note: the two Push Callout copies (`266:125` light, `266:1569` dark) are **independent plain frames, not component instances** — future edits must touch both. Known cosmetic: the 34×34 tap area overlaps the first text line's last ~21px (no ink collision; the shipped layout compresses the text anyway). Owner reviewed 2026-08-18: **rejected** — the ✕ sat uncomfortably close to the headline's trailing edge on all three surfaces; superseded by the respacing pass below (which also removes the tap-area overlap noted here).

**Push Callout ✕ respaced (2026-08-18, round 2):** owner DOD: the ✕ clearly separated from the text, top-trailing corner, HIG spacing. Amended by a contained Figma agent on both independent copies: the Dismiss container (`314:5` / `314:6`) grew 34×34 → **44×44** (HIG tap target) and moved to the **top-trailing corner** (glyph visual insets ~15px trailing / ~14px top); the headline (`266:128` / `266:1572`) went from hug-width to a fixed **190px**, wrapping to exactly two lines ("Get a morning digest +" / "Perfect-window alerts") with ~84px clearance to the container; the card (`266:125` / `266:1569`) grew 55 → **72px** tall, and the content below (two Activity cards + ghost Add card) shifted +17px preserving the 10px gap rhythm (home indicator stays bottom-aligned). Glyph style untouched (SF Pro Semibold 13, `text/secondary` `VariableID:91:210`). A harmless 1×1 FILL-width spacer (`266:130` / `266:1574`) remains inside each row from the original layout. Auditor-verified by screenshot on both frames, light/dark parity confirmed. **Shipped-code implication:** the built `pushCallout` (DashboardView) still draws the pre-respacing layout (trailing-centered 34×34 ✕, single-line headline) — a small layout sweep is owed to mirror these frames ([ADR-0008](../adr/0008-figma-first-ui-gate.md)). **Owner-approved 2026-08-18** (`266:5` / `266:1562`) — the `pushCallout` mirror sweep is unblocked.

**Push Callout owner hand-edit (2026-08-18, round 3 — final):** after approving round 2 the owner re-edited both copies to their exact intent — this paragraph supersedes round 2's geometry as the code-sweep reference. Headline (`266:128` / `266:1572`): 190 → **272px** fixed, wrapping after "window" ("Get a morning digest + Perfect window" / "alerts"); the display copy **intentionally drops the hyphen** — "Perfect window alerts" (owner ruling, UI copy only; the domain term *Perfect-window alert* keeps its hyphen in docs). Dismiss containers unchanged from round 2 (44×44 flush top-trailing; line-1 text ends ~18px short of the tap area — no collision, verified at node level). A parity drift from the hand edit (dark headline 276px inside a fixed-width 271px clipping column) was equalized by a contained agent to light's exact geometry (272 fixed headline, hug column — `266:1571`/`266:1572` only, zero visual change). Auditor-verified via design-context reads + screenshots on both themes. The owed `pushCallout` code sweep now **includes the copy change** alongside the layout mirror. **Sweep shipped 2026-08-18** — `pushCallout` (DashboardView) mirrors these frames: round-3 copy, 44×44 flush top-trailing ✕, 272pt headline with a hard break after "window" (SwiftUI's orphan-avoiding line-break strategy would otherwise wrap one word early; the accessibility label stays one line), natural 72pt growth, plus the owner-approved 2s-periodic bell wiggle (iOS 18+, static under Reduce Motion). Shipped colors ride the shared `Theme` tokens — dark parity lands with the deferred dark-mode adoption (ROADMAP deferred table), not per-view.
