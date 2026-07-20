# Time-it

A backend engine that tells outdoor hobbyists exactly when to go outside — a worldwide product, UAE-first in marketing only.

## What it does

time-it monitors hourly weather forecasts and sends a push notification when conditions match a user's activity preferences. "Tomorrow, 7am-9am: perfect conditions for cycling."

Users author their activities and thresholds (max temperature, max humidity, wind range, etc.) in the iOS app, which sends them to the backend; the backend handles the rest: fetching forecasts, evaluating conditions against the supplied activities, and delivering the alert.

## How it works

1. **Fetch** - pulls hourly forecast data from a weather API
2. **Parse** - normalizes the response into a unified schema (temp, humidity, wind, rainfall, UV, cloud cover, visibility, dust alerts, moon phase, sea conditions)
3. **Match** - compares each hour against the user's activity thresholds
4. **Notify** - sends a push notification when a qualifying window is found (designed in [ADR-0006](docs/adr/0006-device-keyed-push-evaluation.md); ships in #6c/#6d, not yet built)

The weather layer uses an adapter pattern, allowing additional data sources to be swapped in without touching the core logic.

## Activities

Activities are **caller-supplied**: the iOS client authors each one — an `id`, a label, the metrics to display, a per-metric **threshold** profile, and an optional time-of-day window — and sends them in the `POST /api/v1/rating` body. The backend holds **no** activity list; it evaluates whatever profiles the request carries. Curated starting points ship client-side as **Templates** a user adopts and tweaks.

**Lite / Pro** is a subscription tier enforced **client-side** as metric-access + quantity gating — which premium metrics you may use (atmospheric transparency, swell height, Douglas scale, moon phase) and how many activities you may author — not separate per-activity profiles.

Templates shipped today:

- Cycling
- Fishing Lite
- Running
- Stargazing


## Stack

- **Runtime**: Node.js + Express
- **Weather**: Meteosource API (adapter layer supports expansion)
- **Notifications**: Apple Push Notification service (APNs) — planned, #6c/#6d
- **Client**: iOS (App Store)
- **Deployment**: Railway

## Setup

```bash
cp .env.example .env
# Add your API_KEY to .env
npm install
npm run dev        # starts server at http://localhost:3000
```

### Endpoints

```
GET  /health                                    → { status: "ok", timestamp: "..." }
POST /api/v1/rating                             → body { lat, lon, activities[] }; 7-day forecast + per-day ratings
```

### CLI (manual testing)

```bash
node cli.js | python3 -m json.tool
```

## License

© 2026 Yaas Alfalasi. All rights reserved. This repository is shared publicly for portfolio and review purposes only — see [LICENSE](LICENSE).
