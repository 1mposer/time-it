# Time It — Design Guidelines

> **Scope note (updated 2026-08-10):** this file is the visual token truth for the **shipped v1 light-only UI** — `Theme.swift` and `MetricColorTests` pin against it. The **next visual iteration** (temp-encoded header gradients, full Light/Dark semantic tokens, wizard components, the spec 14 gradient card) lives in the Figma file **Main - Time it** — see [`docs/design/FIGMA.md`](../../docs/design/FIGMA.md). The mockup-relic rows (tab bar, sign-in, PRO badge — cut features, never built) were **deleted 2026-08-10**; the SF-Symbols manifest + card-face rules from the retired `design-decisions-issue-5.md` were absorbed here the same day.
> (Originally derived from the Figma Make prototype, deleted 2026-07-19 — recover from git history.)

---

## Colour palette

| Token | Value | Usage |
|---|---|---|
| Header gradient | `#1253a4 → #1a78c2 → #29a8e0 → #3ec6e8` at 160° | Dashboard header background |
| App background | `#f2f2f7` | Screen background (iOS system grouped) |
| Card background | `#ffffff` | Activity card surface |
| Primary text | `#1c1c1e` | Activity names, main content |
| Secondary text | `#8e8e93` | Time labels, inactive icons, gear icon |
| Accent (orange) | `#ff9500` | Buttons, Good window highlight |
| Accent interactive (blue) | `#007aff` | Location CTAs (#5c) — Figma Semantic `accent/interactive`; standalone interactive controls outside the orange rating context |
| Perfect green | `#34c759` | Perfect window highlight |
| Header text | `#ffffff` | All text inside the header |
| Header secondary | `rgba(255,255,255,0.8)` | Wind / humidity row in header |
| Header temp | `rgba(255,255,255,0.92)` | Temperature line in header |
| Divider | `rgba(60,60,67,0.18)`, 0.5px | Header–content separator |
| Timeline track | `#f2f2f7` | Empty part of timeline bar |

### Metric chip colour tiers

Three-tier system: green (good) → orange (caution) → red (avoid).

| Metric | Green | Orange | Red |
|---|---|---|---|
| Temperature (°C) | 18–32 | 33–37 | 38+ |
| UV Index | 0–3 | 4–6 | 7+ |
| Wind Speed (km/h) | 0–20 | 21–35 | 36+ |
| Humidity (%) | 0–60 | 61–75 | 76+ |
| Cloud Cover (%) | 0–20 | 21–60 | 61+ |

Chip colours per tier:
- Green: bg `rgba(52,199,89,0.12)` / text `#1a7a35`
- Orange: bg `rgba(255,149,0,0.12)` / text `#b85c00`
- Red: bg `rgba(255,59,48,0.12)` / text `#c0392b`
- No data: bg `rgba(142,142,147,0.12)` / text `#636366`

---

## Typography

| Role | Font | Size | Weight | Tracking |
|---|---|---|---|---|
| Header time | SF Pro Display | 60pt | Bold (700) | −2.5px |
| Header temp | SF Pro Display | 28pt | Light (300) | −0.5px |
| Header wind/humidity | SF Pro Text | 13pt | Regular (400) | +0.1px |
| Activity name | SF Pro Text | 15pt | Medium (500) | −0.1px |
| Time-axis labels | SF Pro Text | 10pt | Regular | +0.1px |
| Metric chip label | SF Pro Text | 11.5pt | Medium (500) | +0.05px |

Use SF Pro Display for the header (time, temperature). Use SF Pro Text everywhere else.

---

## Layout & spacing

### Screen
- Background: `#f2f2f7`
- Structure (top to bottom): header → 0.5px divider → scrollable card list (no tab bar — grill Q8)

### Header
- Padding: 52pt top (clears status bar), 20pt horizontal, 22pt bottom
- Settings gear button: 34×34pt, positioned `top: 16`, `right: 18` (header top-right)
- Content centred vertically with time → temp → wind/humidity row

### Card list
- Padding: 14pt all sides (top/left/right), 0pt bottom (bottom padding is a 12pt spacer inside the scroll)
- Gap between cards: 10pt

### Activity card
- Background: `#ffffff`
- Corner radius: 16pt
- Padding: 14pt top, 16pt horizontal, 12pt bottom
- Shadow: `0 1px 3px rgba(0,0,0,0.08), 0 0 0 0.5px rgba(0,0,0,0.06)`
- Internal row gaps: top-row → 10pt gap → timeline → 10pt gap → chips

### Timeline bar
- Height: 22pt
- Track corner radius: 6pt
- Window fill corner radius: 5pt
- Window fill opacity: 0.85
- Time-axis labels sit 4pt below the bar with 2pt horizontal inset

### Metric chips
- Corner radius: 20pt (capsule)
- Padding: 8pt horizontal, 3pt vertical
- Gap between chips: 6pt
- Icon size: 12pt (w-3 h-3)
- Maximum 3 chips per card face

### Touch targets
- Every interactive element: minimum 44×44pt (the rule the #5c audit F2 pinned)

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

- Icon: SF Symbol, 18×18pt, primary at 75% opacity (explicit per activity — `AuthoredActivity.iconSymbol` through the single `ActivityIconView` seam)
- Activity name: 15pt medium
- Gear icon: 15pt, secondary colour; opens the authoring editor (#5b)
- Timeline: the day's **real hour span**, positioned from the **global** `startIndex`/`endIndex` rendered in the response `timezone` — the sketch's 6am–12am axis is illustrative, never hardcode it. Green fill = Perfect, orange fill = Good, no fill = No Window
- The card summarises **day 0 only** ("Today" / "Tonight" for nocturnal); a null day 0 renders the none-state copy ("No window today"/"No window tonight") and never rolls forward (ADR-0004 amendment 2026-07-20). Read each activity's own `days.length`; never assume 7
- Chips: `displayMetrics` first 3, values from best-window start hour; nullable metrics (`windSpeed`/`rainFall`/`cloudCover`) render `—`

### Header

```
┌─────────────────────────────────────────┐
│                              [gear]     │  ← settings gear
│              9:41 AM                    │  ← 60pt bold
│               —°C                      │  ← 28pt light
│   💨 — km/h             💧 —%          │  ← 13pt
└─────────────────────────────────────────┘
```

Header weather values (temp, wind, humidity) are the forecast location's **current-hour** values from `hours[0]` (`HeaderView(currentHour:)`, wired 2026-07-12); they fall back to `—` while loading, on error, or when the provider omitted a metric.

---

## Interaction rules

- App opens directly to the dashboard — no launch gate, no accounts (ADR-0001), no bottom bar (grill Q8).
- Tapping a card body pushes the 7-day detail; header gear → Settings sheet; card gear → editor sheet; ghost add-card → activity creation.
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
