# Time It — Design Guidelines

> **Scope note (updated 2026-08-12, [ADR-0009](../../docs/adr/0009-tiered-doc-truth.md)):** this file is the **behavioral + iconography guide** for the shipped v1 light-only UI — card composition rules, chip tiers (pinned by `MetricColorTests`), interaction rules, the SF-Symbols manifest. It carries **no colour/type/spacing values**: shipped values live in code (`Theme.swift`, the views — the shipped truth); design values live in the Figma file (the design truth — addresses in [`docs/design/FIGMA.md`](../../docs/design/FIGMA.md)). The mockup-relic rows were deleted 2026-08-10; the SF-Symbols manifest + card-face rules from the retired `design-decisions-issue-5.md` were absorbed the same day.
> (Originally derived from the Figma Make prototype, deleted 2026-07-19 — recover from git history.)

---

## Colour

Colour values live in `Theme.swift` (shipped truth) and the Figma `Semantic` collection (design truth — [FIGMA.md §3](../../docs/design/FIGMA.md)); this file carries none ([ADR-0009](../../docs/adr/0009-tiered-doc-truth.md)).

### Metric chip colour tiers (behavioral — pinned by `MetricColorTests`)

Three-tier system: green (good) → orange (caution) → red (avoid), plus a neutral "no data" state (renders `—`).

| Metric | Green | Orange | Red |
|---|---|---|---|
| Temperature (°C) | 18–32 | 33–37 | 38+ |
| UV Index | 0–3 | 4–6 | 7+ |
| Wind Speed (km/h) | 0–20 | 21–35 | 36+ |
| Humidity (%) | 0–60 | 61–75 | 76+ |
| Cloud Cover (%) | 0–20 | 21–60 | 61+ |

Chip tier *colours* (bg/text per tier): `Theme.swift` + the Figma `chip/*` variables.

---

## Typography

SF Pro only — SF Pro Display for the header (time, temperature), SF Pro Text everywhere else. Sizes/weights/tracking: shipped truth in the views; the 14 `TimeIt/*` text styles in Figma ([FIGMA.md](../../docs/design/FIGMA.md)).

---

## Layout & spacing

Structure (top to bottom): header → hairline divider → scrollable card list (no tab bar — grill Q8). Geometry values (paddings, radii, gaps, shadows): shipped truth in the SwiftUI views; drawn truth in the Figma component sheets ([FIGMA.md §2](../../docs/design/FIGMA.md)).

Behavioral rules kept here:
- Every interactive element: minimum **44×44pt** touch target (the rule the #5c audit F2 pinned).
- Maximum **3 chips** per card face.

---

## Components

### Activity card

```
┌─────────────────────────────────────────┐
│ [icon] Activity Name           [gear]   │  ← top row
│                                         │
│ ░░░░░░░████████░░░░░░░░░░░░░░░░░░░░░░░ │  ← timeline
│ 6am        12pm        6pm        12am  │  ← axis labels
│                                         │
│ [temp chip]  [wind chip]  [cloud chip]  │  ← metric chips
└─────────────────────────────────────────┘
```

- Icon: SF Symbol, explicit per activity — `AuthoredActivity.iconSymbol` through the single `ActivityIconView` seam
- Gear icon opens the authoring editor (#5b)
- Timeline: the day's **real hour span** as the axis (the sketch's 6am–12am is illustrative, never hardcode it), with the user's **Range** painted as a per-hour **gradient slice** (spec 14 §2, shipped 2026-08-14): one `TierGradient` stop per hour from the `HourQuality` mirror — green = Perfect, orange = Good, red = Bad, with yellow as a blend waypoint at green↔orange hour boundaries only (never a tier — never on chips or solid fills). **No rating word on the card** (decision C — VoiceOver keeps the full spoken summary). A `rating: null` day 0 paints the slice **solid red** ("Nothing in your range"); the gray track alone means **no data** only. The title row carries the Range chip ("6 – 10am")
- The card summarises **day 0 only** with the best-stretch sublabel ("Today · 6–8pm" / "Tonight · 10pm–2am" — the push-copy dialect); a null day 0 is the plain day name, and it never rolls forward (ADR-0004 amendment 2026-07-20). Read each activity's own `days.length`; never assume 7. A **dormant** Activity renders the showcase card ("Set your range →" / ✕ dismiss) instead
- Chips: `displayMetrics` first 3, values from best-window start hour (neutral catalog names on a red day); nullable metrics (`windSpeed`/`rainFall`/`cloudCover`) render `—`
- The optional phrase row (§5) sits between the axis and the chips — visible when Settings → Show phrases is on or Differentiate Without Color forces it; the red day's "Nothing in your range" shows unconditionally

### Header

```
┌─────────────────────────────────────────┐
│                              [gear]     │  ← settings gear
│              9:41 AM                    │  ← 60pt bold
│               —°C                      │  ← 28pt light
│   💨 — km/h             💧 —%          │  ← 13pt
└─────────────────────────────────────────┘
```

Header weather values (temp, wind, humidity) are the forecast location's **current-hour** values from `hours[0]` (`HeaderView(currentHour:)`, wired 2026-07-12); they fall back to `—` while loading, on error, or when the provider omitted a metric. In the **no-location** and **all-dormant** states the weather rows hide entirely — no fabricated conditions and no dangling placeholders when no fetch will happen (the all-dormant case is the spec 14 I2 proposal, pending owner review).

---

## Interaction rules

- App opens directly to the dashboard — no launch gate, no accounts (ADR-0001), no bottom bar (grill Q8).
- Tapping a card body pushes the detail (range once · setup once · range-zoomed week); header gear → Settings sheet; card gear → editor sheet; ghost add-card → activity creation; showcase "Set your range →" → editor with the prefill loaded; detail day row → expands its range hours (one day at a time, collapsed by default).
- All interactive elements have a minimum 44×44pt touch target.
- Cards use `.plain` button style — no system highlight ring on tap.

---

## SF Symbols manifest

*(Absorbed 2026-08-10 from the retired `design-decisions-issue-5.md`.)* The app uses **SF Symbols** for all iconography (`Image(systemName:)` / `Label`). Rules — hallucinated symbol names are the most common failure and render a **blank glyph**:

- **Use ONLY the exact names in the tables below.** Never invent or substitute a plausible-looking name.
- **If a needed glyph is not listed, use `questionmark.circle`** and leave a `// TODO: verify SF Symbol` comment. A visible placeholder is recoverable in review; a blank hallucinated glyph is not.
- **Availability: iOS 17+.** Newer symbols render blank on the deployment target.
- **Accessibility:** pair every symbol with a label (`Label` or `.accessibilityLabel`).
- Rows marked **⚠︎ verify** await the owner's SF-Symbols-app confirmation.

**A. Activity template icons**

| Activity | `id` | SF Symbol | Verify |
|---|---|---|---|
| Cycling | `cycling` | `figure.outdoor.cycle` | |
| Fishing Lite | `fishing-lite` | `figure.fishing` | ⚠︎ verify |
| Running | `running` | `figure.run` | ⚠︎ verify |
| Stargazing (nocturnal) | `stargazing` | `moon.stars.fill` | |

New Templates extend this table — verified names only. The `label.contains("fishing")` heuristic survives only as a legacy fallback.

**B. Metric chip icons (live metrics)**

| Metric | SF Symbol | Verify |
|---|---|---|
| `temp` | `thermometer.medium` | |
| `windSpeed` | `wind` | |
| `rainFall` | `cloud.rain.fill` | |
| `uV` | `sun.max.fill` | |
| `cloudCover` | `cloud.fill` | |
| `humidity` | `humidity.fill` | ⚠︎ verify |
| `visibility` | `eye.fill` | |
| `moon` | `moon.stars.fill` | |
| `dustAlert` | `sun.dust.fill` | ⚠︎ verify |

Coming-soon metrics (`darkness`/`douglasScale`/`swellHeight`/`swellLength`/`tide`/`seaWarning`) are not displayable (the backend rejects them) — no icons until their adapters land.

**C. System / navigation / state**

| Purpose | SF Symbol |
|---|---|
| Settings gear (header) + card authoring gear | `gearshape` |
| Error state (`ContentUnavailableView`) | `wifi.slash` |
| Location permission / no-location | `location.fill` / `location.slash` |
| Ghost add-card / from-scratch / empty state | `plus.circle` |
| Geocode search result row | `mappin.and.ellipse` |
| Metric-picker selection tick | `checkmark` |
| **Unlisted-glyph fallback (the guardrail)** | `questionmark.circle` |

Not symbols: the `NavigationLink` disclosure chevron is system-provided; the loading state is a `ProgressView`.

---

## Dark mode

Deferred. Light mode only at launch. (Full Light/Dark Semantic tokens are pinned in Figma — [`docs/design/FIGMA.md`](../../docs/design/FIGMA.md) — for the post-ship adoption wave.)

---

## Platform target

iOS 17+, SwiftUI. No third-party packages.
