# Handoff — Figma design iteration (wizard upgrades + #5c location screens)

**Date:** 2026-07-31
**For:** the agent on the owner's Linux machine.
**Supersedes:** `handoff-5c-location-onboarding.md` (deleted — its design phase is done; its
still-valid content is folded in below).

---

## 1. Your job

The owner is brainstorming **upgrades to the wizard screens and to the new #5c location
screens** on a Figma scratch page. Your job is to **help the owner make that brainstorm a
reality**: iterate on the designs in Figma with them — explore, refine, and produce
approval-ready frames on the Screens pages.

**The brainstorming hub:**
https://www.figma.com/design/t3ZRvcYPnSRPKElSLAFqmG/Main---Time-it?node-id=179-5
— the page is called **"mess around"** (node-id `179:5`). Treat it as a scratchpad: rough
explorations live there; polished results graduate to the Screens — Light / Dark pages.

**Scope limits:**
- **Figma-only.** This machine has no Xcode — the SwiftUI mirror and the iOS test suite run on
  the owner's Mac, by a different session. Do not write Swift.
- **Approval gate:** nothing gets mirrored to code until the owner approves the frames. Your
  deliverable is approved frames, not code.
- **Do not touch** `src/weather/` or the WeatherKit agent's files (see §6).

**Read order for project context:** `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md` → the
#5c spec (`docs/issues/completed/implement-spec-issue-5c-location-onboarding.md` — built 2026-08-01).

---

## 2. What already exists (built 2026-07-30, awaiting owner approval)

Four #5c frames sit on the Screens pages, fully token-bound, zero new tokens/components:

| Frame | Light (page `92:17`) | Dark (page `92:18`) |
|---|---|---|
| Dashboard / No Location | `172:492` | `173:996` |
| City Picker | `172:1266` | `173:1295` |

- **Dashboard / No Location:** Header instance with location line "NO LOCATION", clock kept,
  Temp + Meta children hidden (no fabricated weather). Two grayed skeleton cards (surface/card
  base, timeline/track bars, 55% opacity, text-free). Empty-state block per the Error idiom:
  `location.slash` 44pt gray → "No location yet" (TimeIt/Empty Title) → 2-line secondary copy →
  filled capsule **"Enable Location"** → plain accent-text **"Place your own location"**.
- **City Picker:** Add Sheet idiom (scrim, grabber, "Set Location" title, gray Cancel),
  as-you-type search field (magnifier + query, **no Search button** per spec), grouped results
  list (city `text/primary` left, region `text/secondary` right, 345×1 hairlines), footnote
  "Results update as you type. Choosing a city saves it as your home location."

The Dark twins carry `explicitVariableModes` (Semantic → Dark) at the frame root — clone from
them and new variable-bound children resolve automatically.

---

## 3. Figma access — read this, it saves a lot of tokens

**File:** "Main - Time it" · **fileKey:** `t3ZRvcYPnSRPKElSLAFqmG`

### The one trap
`get_metadata` is **broken for this file** — it returns only 1 of ~21 pages ("wizard mind
map"), every time. Do not trust it to enumerate pages.

### What works
- The Figma MCP reads/writes the **cloud** file by fileKey; the desktop app can be closed.
- Enumerate pages with `use_figma` (load the `figma-use` skill first):
  ```js
  return figma.root.children.map(p => ({ name: p.name, id: p.id, children: p.children.length }));
  ```
- Switch pages via `await figma.setCurrentPageAsync(await figma.getNodeByIdAsync(PAGE_ID))` —
  **at most once per `use_figma` call**; fan multi-page work out as parallel calls in one
  message. `figma.currentPage` resets to the first page on every call.
- Tokens: `figma.variables.getLocalVariableCollectionsAsync()` + `getVariableByIdAsync`
  (file-global, no page switch needed).
- Screenshots: `await node.screenshot({scale: 0.7})` inline, or `get_screenshot`.

### Page map (as of 2026-07-31)

| Page | node-id | Notes |
|---|---|---|
| wizard mind map | `39:4` | concept mind-map of the range-first wizard |
| SwiftUI as-built | `74:4` | mirrors the current #5a/#5b build |
| Cover | `92:2` | |
| **mess around** | `179:5` | **the brainstorming scratchpad — your hub** |
| Color / Typography / Spacing | `92:4` / `92:5` / `92:6` | foundations |
| Metric Chip · Animations · Activity Card · Ghost Add Card · Header · Showcase Card · Template Row · Range Picker Row · Review Row | `92:8` · `127:575` · `92:9` · `92:10` · `92:11` · `92:12` · `92:13` · `92:14` · `92:15` | components (Activity Card has Perfect/Good/None variants) |
| Screens — Light | `92:17` | 18 frames incl. the new #5c pair |
| Screens — Dark | `92:18` | Dark twins |

(Divider pages `92:3`, `92:7`, `92:16` separate the groups. "mess around" position in
`figma.root.children` may differ — enumerate, don't assume.)

Existing Screens — Light frames: Dashboard Loaded `111:2`, Loading `111:17`,
Empty — Showcase `111:32` (that's *no-activities*, NOT no-location), Error `111:47`,
Activity Detail `111:62`, Settings `111:77`, Activity Editor `111:92`, Wizard Add Sheet
`111:372`, Name+Icon `111:387`, Range Same-Day `111:402`, Range Overnight `111:417`,
Range Error `111:432`, Metrics Template `111:447`, Metrics Custom `111:462`,
Review Day `111:477`, Review Night `111:492`, plus the #5c pair (§2).

### Design tokens — bind against these, nothing else
- **Semantic** (VariableCollectionId `91:3`, modes Light `91:1` / Dark `91:2`) — **the layer to
  bind**: `surface/background|card|card-elevated`, `text/primary|secondary|on-gradient`,
  `separator`, `rating/perfect|good`, `accent/interactive|destructive`, `timeline/track`,
  `chip/{green,orange,red,neutral}/{bg,text}`, `gradient/{cool,mid,hot}/{start,end}`.
  Key IDs (`VariableID:91:NNN`): surface/background=206, surface/card=207, text/primary=209,
  text/secondary=210, text/on-gradient=211, separator=212, rating/perfect=213, rating/good=214,
  accent/interactive=215, timeline/track=217, chip/green/bg=218, chip/neutral/bg=221,
  gradient cool=226/227, mid=228/229, hot=230/231.
- **Layout** (`91:4`) — `space/{xs,sm,md,lg,xl}`, `radius/{sm,md,lg,full}`.
- **Primitives** — raw palette; reference via Semantic, don't bind directly to screens.
- **Legacy — do NOT use:** `App Colors`, `Theme colors` (superseded, slated for cleanup).

**Redundancy rule (owner's standing instruction):** before creating any new token, component,
or style, check the foundations — they are precise and nearly complete, and they match the iOS
app letter-for-letter. New primitives are a last resort.

### Hard-won `use_figma` gotchas (all bitten once already)
- `figma.createAutoLayout()` frames get a **default white fill** — set `fills = []` on every
  container meant to be transparent (this silently broke Dark-mode rows once: invisible
  white-on-white in Light, opaque white in Dark).
- `setBoundVariableForPaint` returns a **new** paint — capture and reassign the fills array.
- Text edits: load the node's current fonts first (`getStyledTextSegments(['fontName'])` →
  `loadFontAsync`) or writes throw.
- New page-level nodes land at (0,0) — place them explicitly (Screens grid uses y=200,
  x steps of 460).

### SF Symbol codepoints (SF Pro PUA — cannot be re-derived on Linux)
These were extracted on macOS via bitmap-matching (`NSImage(systemSymbolName:)` vs PUA glyph
renders); Linux has no SF fonts/AppKit, so use these as given, e.g.
`String.fromCodePoint(0x10062C)` in a text node named after the symbol:

| Symbol | Codepoint |
|---|---|
| `location.slash` | `U+10062C` |
| `magnifyingglass` | `U+1002AB` |
| `wifi.exclamationmark` (used on the Error screen) | `U+100665` |
| `wifi.slash` | `U+100648` |

Any *new* symbol you need must be codepoint-verified on the Mac side — ask the owner rather
than guessing a PUA value.

---

## 4. Design idioms already pinned (match these, don't reinvent)

- **Empty/error state:** centered 44pt gray SF symbol → SF Pro Semibold 17 title
  (TimeIt/Empty Title) → Regular 14 `text/secondary` subtitle (~280w) → capsule CTA
  (radius/full, `accent/interactive`, pad 20/9, Semibold 15 white) → optional plain
  accent-text secondary CTA.
- **Grouped list:** radius 10 `surface/card` container, rows 361×44 (pad 16, gap 12), 345×1
  `separator` hairlines right-aligned (`counterAxisAlignItems: 'MAX'`).
- **Sheet:** scrim #000 @40%, grabber 36×5, Semibold 17 title, Regular 15 gray Cancel.
- **Cards:** 365w, radius 16, pad 14/12, gap 8–10. Screen width 393.

---

## 5. Context on what the screens are for (so iteration stays on-spec)

- **#5c location screens** (spec: `docs/issues/completed/implement-spec-issue-5c-location-onboarding.md`, built 2026-08-01): the silent
  Dubai fallback is deleted; the Active-location chain is home → GPS → last-resolved cache →
  none → honest empty state with "Enable location" + "Place your own location". The city picker
  is worldwide, `MKLocalSearch`-backed, debounced as-you-type, no Search button. The picker
  also replaces the #5b Settings free-text+Search row.
- **Wizard screens:** 9 hi-fi frames already exist (`111:372`–`111:492` + Dark twins). The
  ROADMAP still calls the range-first wizard "spec deliberately unwritten" — the owner knows
  about this docs-vs-design drift; the mess-around page is where the wizard's next iteration is
  being explored. Don't act on the ROADMAP drift; follow the owner's direction on the page.

---

## 6. Concurrent work — do not touch

A separate agent is doing the **WeatherKit second-provider** backend work:
- Their doc: `docs/issues/current/handoff-weatherkit-provider-abstraction.md` (untracked —
  leave it).
- Their working-tree edits (leave unstaged, do not commit or revert):
  `ios/TimeIt/TimeIt/Models/AuthoredActivity.swift` and
  `ios/TimeIt/TimeIt.xcodeproj/xcshareddata/xcschemes/TimeIt.xcscheme`.
- Their code area: `src/weather/` — **do not edit anything under it.**
- If you commit docs, stage only your own files — never `git add -A`.
