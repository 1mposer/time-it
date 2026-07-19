# Implementation spec — Figma foundations: multi-page design system

> ✅ **IMPLEMENTED 2026-07-18** — the full system exists in the Figma file; do not re-run this spec. All §8 acceptance items pass.
> Deviations/decisions from the build session (owner-approved live): **scope expanded** to a redesign pass (as-built page is reference ground, not sacred) + all 9 wizard frames in the Screens galleries; **`App Colors` kept, NOT retired** — the wizard-mind-map arrows bind to it (noted on the 🎨 Color page); the spec's `Cards`/`Transition Screens`/`Wizard screens` pages had already been deleted by the owner; chip tint alpha lives **inside** the Semantic tokens (12% light / 20% dark), which sidesteps quirk §6.1 entirely; logo rebuilt as a vector `Brand/App Icon` (1024/180/40). Key node IDs: agent memory `project_figma_ds_v1_built.md`.
>
> For a **fresh agent** with no prior conversation context. Everything needed is in this file.
> Target: the Figma file **Main - Time-it** (`fileKey: t3ZRvcYPnSRPKElSLAFqmG`).
> Produced from the design grill of 2026-07-18; palette owner-approved same day. Companion glossary: [`ios/GLOSSARY.md`](../../ios/GLOSSARY.md).

# Skill References

## Your foundation: `docs/design/figma_foundations_multi-page_implementation.md`
This is authoritative. Follow it exactly.

## Optional guardrails (mention if you hit design questions):
- "Validate this against atomic design principles (ui-design-system)"
- "Check contrast ratios (apple-hig-expert)"
- "Verify component architecture patterns (senior-fullstack)"

These are reference frameworks only — your spec is the source of truth.


---

## Context

The repo's iOS app (SwiftUI, `ios/TimeIt/`) was imported into Figma as an **as-built reference** on the page `SwiftUI as-built` — token-bound components + 8 screens (IDs below). The owner is now designing the app's next visual iteration (wizard redesign, new identity palette) and wants a **proper multi-page design system** in the same file: foundations pages (color, type, spacing), per-component sheets, and a screens gallery — the "huge layouts of assets" studio-style file.

**Skills required before any Figma write:** load `figma-use`, `figma-generate-library`, `figma-generate-design` (Skill tool / MCP resources). Follow their phase discipline (discovery → tokens → components → screens; sequential `use_figma` calls; ≤10 ops per call; return all node IDs; `setCurrentPageAsync` at most once per call; `loadFontAsync` before any text write).

---

## Locked decisions (grill 2026-07-18 — do not relitigate)

1. **The three identity colors are a temperature encoding for the HEADER gradient only.** Cool → blue gradient, Mid → yellow gradient, Hot → salmon gradient. They are *not* general brand/accent colors and must not be used for buttons or card accents. Card rating language stays green=Perfect / orange=Good (unchanged).
2. **Bands are region-profiled, keyed by the FORECAST LOCATION's country** (not device locale — a UAE user viewing a Munich forecast gets default bands):
   | Profile | Cool (blue) | Mid (yellow) | Hot (salmon) |
   |---|---|---|---|
   | Default | temp < 20 | 20–32 | ≥ 33 |
   | UAE (`AE`) | ≤ 33 | 34–37 | > 37 |
   Driven by the current hour's temp (`hours[0].temp` — the value the header already displays). Table is extensible by country code. *(App-side detection = reverse-geocode the active location → country code; Figma only documents this table on the color foundations page.)*
3. **Dark mode: full light + dark, now.** Structure: `Primitives` collection (1 mode) + `Semantic` collection (Light/Dark modes). All dark values are already chosen — the pinned palette in §4.
4. **v1 component scope = as-built four + wizard set.** As-built: Metric Chip, Activity Card, Ghost Add Card, Header (which gains Temp=Cool/Mid/Hot variants). New for the wizard redesign: Showcase Card, Template Row, Range Picker Row, Review Row. Generic iOS controls (buttons, toggles, text fields, nav bars) come from the already-subscribed **iOS 18 and iPadOS 18** library — do not rebuild them.
5. **Typography: SF Pro stays.** The app is native SwiftUI with a no-custom-font reality; the as-built `TimeIt/*` text styles are the base ramp — formalize semantic groupings on a specimen page, don't invent a new scale.
6. **Nothing the owner hand-built in Figma is sacred** (their words: "that was me learning Figma"). The `App Colors` collection specifically may be restructured/retired (see §5). The **as-built page and `Theme colors` collection stay untouched** — they are the code-truth reference and the as-built page binds to them.
7. **Structure: proper multi-page system** (page skeleton in §3).

Wizard-redesign context a fresh agent needs (already decided elsewhere, 2026-07-17/18): every activity gets a mandatory From/To time range in the wizard ("range-first"); first launch shows non-Activity **showcase cards** (template previews with a "Set your range →" CTA); the "find a time for you"/duration mode was **dropped/deferred**. See `ios/GLOSSARY.md` for terms (showcase card, template path, diurnal/nocturnal, etc.).

---

## 3. Deliverable — page skeleton

Create (in this order, after the existing pages):

```
🏠 Cover                         — app icon (from "App Identity" page), name, one-line description, version/date
─── FOUNDATIONS ───
🎨 Color                         — primitives ramp · semantic tokens light+dark columns · the 3 header
                                   gradients with the band-profile table from §2 documented beside them
🔤 Typography                    — TimeIt/* specimen (name, size/weight/tracking, sample line, usage note)
📐 Spacing & Radius & Elevation  — spacing bars, radius samples (radius-card 16, groups 10), shadow vs
                                   dark-mode elevation treatment
─── COMPONENTS ───  (one page per set, variant grid + usage notes)
Metric Chip · Activity Card · Ghost Add Card · Header · Showcase Card · Template Row · Range Picker Row · Review Row
─── SCREENS ───
📱 Screens — Light               — key screens as instances of the system
🌙 Screens — Dark                — same frames, Semantic collection mode flipped to Dark
```

The existing `SwiftUI as-built` page stays as-is (reference), listed after these or left where it is.

## 4. Pinned palette (owner-approved 2026-07-18 — use these exact values)

All dark-mode judgment calls are **already made**. Build with these values; do not re-derive.

### 4.1 Header gradients (~160°, identical in Light and Dark — treated as imagery)

| Variant | Start | End | Note |
|---|---|---|---|
| `Temp=Cool` | `#1774FF` | `#68D7FC` | owner's original, unchanged |
| `Temp=Mid` | `#E39A22` | `#F2C95C` | **deepened** from the owner's `#ECCB5E→#F7EFD4` so white header text stays legible |
| `Temp=Hot` | `#EE6A4D` | `#FA9C86` | **deepened** from the owner's `#FB9887→#F9D3CD`, same reason |

The as-built ocean-blue gradient (`#1253A4→#3EC6E8`) **retires** — it survives only on the as-built reference page.

### 4.2 Semantic tokens (collection `Semantic`, modes Light / Dark)

| Token | Light | Dark |
|---|---|---|
| `surface/background` | `#F2F2F7` | `#000000` |
| `surface/card` | `#FFFFFF` | `#1C1C1E` (elevated: `#2C2C2E`, replaces the shadow) |
| `text/primary` | `#1C1C1E` | `#F2F2F7` |
| `text/secondary` | `#8E8E93` | `#98989F` |
| `separator` | `#3C3C43` @ 18% | `#545458` @ 60% |
| `rating/perfect` | `#34C759` | `#30D158` |
| `rating/good` | `#FF9500` | `#FF9F0A` |
| `accent/interactive` | `#007AFF` | `#0A84FF` |
| `accent/destructive` | `#FF3B30` | `#FF453A` |
| `timeline/track` | `#F2F2F7` | `#2C2C2E` |

These tokenize the as-built raw-paint whitelist (nav blue, destructive red, switch green → `rating/perfect`; white-on-gradient stays raw white).

### 4.3 Metric-chip recipes

- **Light** (as built today): background = tier color @ **12%**, text = deep tier text (`#1A7A35` green / `#B85C00` orange / `#C0392B` red / `#636366` neutral).
- **Dark**: background = dark tier sibling @ **20%**, text = the bright sibling itself (`#30D158` / `#FF9F0A` / `#FF453A` / `#98989F`).

### 4.4 Typography (no new fonts — SF Pro; group the 14 existing `TimeIt/*` styles into semantic roles)

Display (Header Time 60 Bold, Header Temp 28 Light) · Title (Empty Title 17 Semibold, Form Row 17) · Label (Card Title 15 Medium) · Body (Body 14, Footnote 13, Header Meta 13) · Caption (Card Subtitle 12, Hour Label 12, Rating Badge 12 Semibold) · Micro (Chip 11.5, Chip Small 11, Axis 10).

### 4.5 Spacing / radius tokens

`space/xs·sm·md·lg·xl` = 4·8·10·14·16 — `radius/sm·md·lg·full` = 6·10·16·999 (`radius/lg` aliases the existing `radius-card`).

### 4.6 Other pinned asset decisions

- **Icons:** SF Symbols only (manifest-driven); the Venn-circle logo is the only custom vector.
- **Logo:** componentize the App-Identity icon as `Brand/App Icon` with 1024/180/40 size variants, shown on the Cover page.
- **Elevation:** exactly two levels — card (shadow in Light / `#2C2C2E` surface in Dark) and sheet (material blur).
- **Identity yellow/salmon are never accents** — buttons stay `accent/interactive`, destructive stays `accent/destructive` (locked in §2 item 1).

## 5. Variable restructure plan

Current state (verified 2026-07-18):

- **`Theme colors`** (`VariableCollectionId:36:4`, mode `36:0`) — 20 vars mirroring `Theme.swift` + as-built additions; scoped + iOS code syntax set. **Do not modify; do not delete.** The as-built page binds to it.
- **`App Colors`** (`VariableCollectionId:11:64`) — 3 color vars (`Main - Blue`, `Accent - Yellow`, `Accent - Red`) where the two **modes** (`35:0` "Main - Gradiant 1", `35:1` "Main - Graiant 2") are abused as **gradient start/end stops**. Values: blue #1774FF→#68D7FC; yellow ≈#ECCB5E→#F7EFD4; red ≈#FB9887→#F9D3CD.

To build:

- **`Primitives`** (1 mode): the six gradient stops (`gradient/cool/start|end`, `gradient/mid/start|end`, `gradient/hot/start|end`) — use the **pinned §4.1 values**, not the raw App Colors ones (mid/hot were deepened) — plus gray ramp and any raw values the Semantic layer needs. Scopes `[]` (hidden from pickers).
- **`Semantic`** (modes **Light / Dark**): surfaces, text, separators, `accent/interactive`, `accent/destructive`, `rating/perfect`, `rating/good`, chip-tier tokens, header-gradient aliases → primitives. Every var: explicit scopes + iOS code syntax (follow the pattern visible on `Theme colors`).
- **Retire `App Colors`** only after migrating values and confirming zero bindings to it (check with a `boundVariables` scan; the owner's early frames may bind to it — if so, leave it and note where).


## Your tools (Claude Code skills to load)
These three agent skills from `alirezarezvani/claude-skills` will guide rigid, functional design:
1. **ui-design-system** (`product-team/`) — component architecture, token generation, variant patterns
2. **apple-hig-expert** (`product-team/`) — HIG audit, accessibility, Liquid Glass (later cross-check)
3. **senior-fullstack** (`engineering-team/`) — forcing questions, architecture discipline


## 6. Non-obvious Figma facts (hard-won — read before writing)

1. **Instance paint-opacity quirk (this file):** paint-level `opacity` on a component's fill does **not** propagate to instances — fresh Metric Chip instances render solid instead of 12%-tinted. Fix: re-stamp the main component's `fills` array onto each new instance (`inst.fills = variant.fills.map(p => ({...p}))`). Every instance on the as-built page has already been stamped.
2. **Fonts:** `SF Pro` and `SF Pro Rounded` are available (styles: `Regular`, `Medium`, `Semibold` — one word — `Bold`, `Light`, …). All icons are **SF Symbol glyphs as SF Pro text nodes** via `figma.util.getSfSymbolCharacter(name)` — never hand-look-up codepoints; unknown names throw `RangeError` (surface, don't substitute).
3. **Existing as-built IDs** (page `74:4`; sections Components `74:5`, Screens `74:6`):
   - Component sets: Metric Chip `75:39` (prop `Value#75:0`), Ghost Add Card `75:46`, Header `76:4`, Activity Card `77:102` (variants `77:4` Perfect / `77:52` Good / `77:77` None; props Label + Day).
   - Screens: Dashboard Loaded `78:22` / Loading `79:107` / Empty `79:124` / Error `79:169`; Add Sheet `81:142`; Editor `82:142`; Detail `83:142`; Settings `85:174`.
   - Text styles `TimeIt/*` (14) + effect style `TimeIt/Card Shadow` exist — reuse, don't duplicate.
4. **Activity Card's `Day` TEXT property** overrides per-variant subtitle text — variant previews all show the default ("Today"); instances set their own. Expected behavior, not a bug.
5. **Apple iOS 18 kit** is subscribed — scope `search_design_system` with its library key to pull status bars / generic controls:
   `lk-df324a089628d1c7c7b0d29e676b621790cdcac1c725b49a3cfbb974a362f8201ac643e1fbccc855970ab22dabd6897ef20e72a7feda01014ddd59daf3f6ed52`
6. **Other pages** (don't touch without asking): `App Identity` (`0:1` — logo + the three identity swatches), `Cards` (`34:5`), `Transition Screens` (`34:6`), `wizard mind map` (`39:4`), `Wizard screens` (`68:18`) — the owner's WIP.
7. Screen frames are iPhone-16-sized **393 × 852**; cards are 365 wide; grouped-list groups use radius 10, cards radius 16.

## 7. Out of scope (future app work, do NOT build here)

- SwiftUI implementation of the temp-driven header (Theme.headerGradient → 3 gradients + country-profile lookup via reverse geocoding) — needs its own issue.
- SwiftUI dark-mode adoption (Theme.swift hex → adaptive colors).
- The wizard's iOS implementation (separate redesign track).

## 8. Acceptance checklist

- [ ] All pages from §3 exist and are navigable; Cover looks intentional.
- [ ] `Primitives` + `Semantic` (Light/Dark) collections exist; every semantic var scoped + code-syntaxed; no `ALL_SCOPES`.
- [ ] Flipping a Screens-gallery frame between Light/Dark modes restyles it fully — zero stranded raw paints (previous whitelist now tokenized).
- [ ] Header set has Cool/Mid/Hot variants; the band-profile table from §2 is documented on the Color page.
- [ ] All 8 component sheets show every variant with usage notes; chip instances are tint-correct (quirk #1 stamped).
- [ ] `Theme colors`, the as-built page, and the owner's WIP pages are untouched.
