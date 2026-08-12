# Time-it

A backend engine that tells outdoor hobbyists whether their chosen hours are worth going outside — a worldwide product, UAE-first in marketing only.

## What it does

time-it checks hourly weather forecasts against the time **range** a user sets for each activity (term of record: [Range](docs/CONTEXT.md)) and rates each day's range Bad, Good, or Perfect. "Tomorrow, 7am-9am: perfect conditions for cycling."

Users author their activities in the iOS app — thresholds (max temperature, max humidity, wind limits, etc.) plus the time range to watch — and the app sends them to the backend; the backend handles the rest: fetching forecasts, evaluating each activity's range against them, and reporting the verdict — on the dashboard, and by push for opted-in devices.

## How it works

1. **Fetch** - pulls hourly forecast data from a weather API
2. **Parse** - normalizes the response into a unified hourly schema (full field list: [CLAUDE.md](CLAUDE.md))
3. **Match** - rates each hour inside the activity's range against its thresholds, then finds the best qualifying window per day
4. **Notify** - returns per-day verdicts to the app; opted-in devices also get the daily digest and an alert when their range first rates Perfect within ~48h (designed in [ADR-0006](docs/adr/0006-device-keyed-push-evaluation.md); build status: [ROADMAP](docs/issues/ROADMAP.md))

The weather layer uses an adapter pattern, allowing additional data sources to be swapped in without touching the core logic.

## Activities

Activities are **caller-supplied**: the iOS client authors each one — an `id`, a label, the metrics to display, a per-metric **threshold** profile, and an optional time-of-day window — and sends them in the `POST /api/v1/rating` body. The backend holds **no** activity list; it evaluates whatever profiles the request carries. Curated starting points ship client-side as **Templates** a user adopts and tweaks (the shipped catalog lives in `ios/TimeIt/TimeIt/Models/SeedTemplates.swift`; Range prefills: spec 14 §6).

**Lite / Pro** is a subscription tier enforced **client-side** as metric-access + quantity gating — which premium metrics you may use (atmospheric transparency, swell height, Douglas scale) and how many activities you may author — not separate per-activity profiles. (Pro is **deferred** — [ROADMAP §Deferred](docs/issues/ROADMAP.md).)

## Stack

- **Runtime**: Node.js + Express
- **Weather**: Meteosource API (adapter layer supports expansion)
- **Notifications**: Apple Push Notification service (APNs) — build status: [ROADMAP](docs/issues/ROADMAP.md)
- **Client**: iOS (App Store)
- **Deployment**: Railway

## Setup

```bash
cp .env.example .env
# Add API_KEY (Meteosource) AND DATABASE_URL (a reachable Postgres) to .env —
# both are required: initDb() runs at boot and the server exits non-zero without them
npm install
npm run dev        # starts server at http://localhost:3000
```

### Endpoints

```
GET    /health                                  → { status: "ok", timestamp: "..." }
POST   /api/v1/rating                           → body { lat, lon, activities[] }; up-to-7-day forecast (provider-determined ≤168 h) + per-day ratings
PUT    /api/v1/devices/:deviceId                → push-path device snapshot upsert (204)
DELETE /api/v1/devices/:deviceId                → push opt-out (204, idempotent)
```

### CLI (manual testing)

```bash
node cli.js | python3 -m json.tool
```

## License

© 2026 Yaas Alfalasi. All rights reserved. This repository is shared publicly for portfolio and review purposes only — see [LICENSE](LICENSE).
