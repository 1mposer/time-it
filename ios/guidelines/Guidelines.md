# Time It — Design Guidelines

> Source of truth for all UI decisions. Every new screen must be consistent with these principles.
> Derived from the Figma Make prototype in `ios/src/app/`.

---

## Colour palette

| Token | Value | Usage |
|---|---|---|
| Header gradient | `#1253a4 → #1a78c2 → #29a8e0 → #3ec6e8` at 160° | Dashboard header background |
| App background | `#f2f2f7` | Screen background (iOS system grouped) |
| Card background | `#ffffff` | Activity card surface |
| Primary text | `#1c1c1e` | Activity names, main content |
| Secondary text | `#8e8e93` | Time labels, inactive icons, gear icon |
| Accent (orange) | `#ff9500` | Active tab, buttons, Good window highlight, PRO badge |
| Perfect green | `#34c759` | Perfect window highlight |
| Header text | `#ffffff` | All text inside the header |
| Header secondary | `rgba(255,255,255,0.8)` | Wind / humidity row in header |
| Header temp | `rgba(255,255,255,0.92)` | Temperature line in header |
| Divider | `rgba(60,60,67,0.18)`, 0.5px | Header–content separator |
| Tab bar bg | `rgba(255,255,255,0.82)` + 20px backdrop blur | Tab bar surface |
| Tab bar border | `rgba(60,60,67,0.2)`, 0.5px | Top edge of tab bar |
| Sign-in button bg | `rgba(255,255,255,0.18)` | Circular button in header top-right |
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
| PRO badge | SF Pro Text | 9pt | Bold (700) | +0.5px |

Use SF Pro Display for the header (time, temperature). Use SF Pro Text everywhere else.

---

## Layout & spacing

### Screen
- Background: `#f2f2f7`
- Structure (top to bottom): header → 0.5px divider → scrollable card list → tab bar

### Header
- Padding: 52pt top (clears status bar), 20pt horizontal, 22pt bottom
- Sign-in button: 34×34pt, `borderRadius: 20pt`, positioned `top: 16`, `right: 18`
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

### Tab bar
- Height: 82pt
- Bottom padding (home indicator clearance): 18pt
- Horizontal padding: 20pt
- Each button minimum touch target: 44×44pt

---

## Components

### Activity card

```
┌─────────────────────────────────────────┐
│ [icon] Activity Name  [PRO]    [gear]   │  ← top row
│                                         │
│ ░░░░░░░████████░░░░░░░░░░░░░░░░░░░░░░░ │  ← timeline
│ 6am        12pm        6pm        12am  │  ← axis labels
│                                         │
│ [temp chip]  [wind chip]  [cloud chip]  │  ← metric chips
└─────────────────────────────────────────┘
```

- Icon: SF Symbol, 18×18pt, primary at 75% opacity
- Activity name: 15pt medium
- PRO badge: only on activities with `-pro` suffix in their ID; orange text + faint orange bg
- Gear icon: 15pt, secondary colour; requires sign-in to act
- Timeline: 6am–12am (18 hours). Green fill = Perfect, orange fill = Good, no fill = No Window
- Chips: `displayMetrics` first 3, values from best-window start hour

### Header

```
┌─────────────────────────────────────────┐
│                              [person]   │  ← sign-in button
│              9:41 AM                    │  ← 60pt bold
│               —°C                      │  ← 28pt light
│   💨 — km/h             💧 —%          │  ← 13pt
└─────────────────────────────────────────┘
```

Header weather values (temp, wind, humidity) are placeholders (`—`) until a live data source is wired in.

### Tab bar

Three tabs: **Activities** (active = orange), **+** (requires sign-in), **Profile**.
No labels — icon only.

---

## Interaction rules

- No sign-in gate on launch. App opens directly to the dashboard.
- Three sign-in entry points: header person icon, card gear icon, + tab.
- Tapping a card body navigates to the activity detail screen.
- All interactive elements have a minimum 44×44pt touch target.
- Cards use `.plain` button style — no system highlight ring on tap.

---

## Dark mode

Deferred. Light mode only at launch.

---

## Platform target

iOS 17+, SwiftUI. No third-party packages.
