# Design decisions — Issue #5 (iOS app)

> Shared reference for both sub-issues #5a and #5b.
> Do not relitigate these decisions. Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md).

---

## Navigation and first screen

- App opens directly to the dashboard — no welcome screen, no launch gate.
- Tab bar at the bottom with three tabs: **Activities** (left, default), **+** (middle), **Profile** (right).
- The **+** tab requires sign-in. Tapping it as a guest triggers the sign-in flow.

## Dashboard

- Header: ocean blue gradient (`#1253a4 → #1a78c2 → #29a8e0 → #3ec6e8`, 160°). Contains: current time (large, centred, SF Pro Display bold, −2.5px tracking), temperature placeholder `—°C` (smaller, SF Pro Display light, −0.5px tracking), wind and humidity placeholders in a row below that. Sign-in icon (`person.crop.circle`) in the top-right corner of the header.
- Thin 0.5px divider below the header.
- Scrollable vertical list of activity cards. The list is the user's personalised activity list — activities can be added/removed via the **+** tab (requires sign-in).
- Background colour: `#f2f2f7` (iOS system grouped background).
- Header weather values (temp, wind, humidity) are `—` placeholders in #5a. Live values from current-hour API data are deferred to a later issue.

## Activity card (face)

Each card contains:
1. **Top row:** SF Symbol activity icon (top left, 18×18pt, 75% opacity) + activity name (SF Pro Text, 15pt medium, −0.1px tracking) + optional **PRO** badge (for activities whose `activityId` ends in `-pro`) + gear icon (`gearshape`, top right — requires sign-in).
2. **Timeline bar:** 6 AM to 12 AM (18 hours). Best window highlighted: green (`#34c759`) for Perfect, orange (`#ff9500`) for Good, no highlight for No Window. Window fill opacity 0.85. Time labels (6am, 12pm, 6pm, 12am) sit 4pt below the bar.
3. **Metric chips row:** activity's `displayMetrics` (first 3). Each chip shows the metric's value at the **best-window start hour** (index = `startIndex` into the `hours` array). Colour tier is applied per the scale in [`Guidelines.md`](../../../ios/guidelines/Guidelines.md).

Card background: `#ffffff`. Corner radius: 16pt. Shadow: `0 1px 3px rgba(0,0,0,0.08), 0 0 0 0.5px rgba(0,0,0,0.06)`.

## Activity set (5 default activities)

The backend returns these 5 activities in this order. Cards appear in backend order on the dashboard.

| `activityId` | Label | SF Symbol | `displayMetrics` |
|---|---|---|---|
| `boat-fishing-pro` | Boat Fishing Pro | `figure.fishing` | `["temp"]` |
| `boat-fishing-lite` | Boat Fishing Lite | `figure.fishing` | `["temp", "windSpeed"]` |
| `shore-fishing` | Shore Fishing | `figure.fishing` | `["temp", "windSpeed"]` |
| `volleyball` | Volleyball | `figure.volleyball` | `["temp", "windSpeed", "humidity", "uV"]` |
| `stargazing-lite` | Stargazing Lite | `moon.stars` | `["temp", "cloudCover"]` |

The PRO badge is shown on any card whose `activityId` ends in `-pro`. Full StoreKit gating is #5b scope.

## Metric chip colour tiers

| Metric | Green | Orange | Red |
|---|---|---|---|
| `temp` (°C) | 18–32 | 33–37 | 38+ |
| `uV` | 0–3 | 4–6 | 7+ |
| `windSpeed` (km/h) | 0–20 | 21–35 | 36+ |
| `humidity` (%) | 0–60 | 61–75 | 76+ |
| `cloudCover` (%) | 0–20 | 21–60 | 61+ |

Chip style per tier (matches `ios/guidelines/Guidelines.md`):
- Green: bg `rgba(52,199,89,0.12)` / text `#1a7a35`
- Orange: bg `rgba(255,149,0,0.12)` / text `#b85c00`
- Red: bg `rgba(255,59,48,0.12)` / text `#c0392b`

## Interactions

- **Tap card body** → navigates to activity detail screen.
- **Tap gear icon** → threshold editing screen (requires sign-in; triggers sign-in flow if guest).
- **Tap sign-in icon (header)** → sign-in flow.
- **Tap + tab** → requires sign-in; triggers sign-in flow if guest.

## Sign-in triggers (three entry points)

1. Sign-in icon in the header.
2. Gear icon on any activity card.
3. **+** tab in the tab bar.

## Typography

- SF Pro Display — headings (time, temperature in header).
- SF Pro Text — all body text (activity names, metric chips, labels).
- Tight letter-spacing on headings (−2.5px on time, −0.5px on temperature). Default on body.

## Colour palette

See `ios/guidelines/Guidelines.md` for the complete token table.

## Dark mode

Deferred. Light mode only at launch.

## Platform

iOS 17+, Swift, SwiftUI, MVVM. No third-party Swift packages.
