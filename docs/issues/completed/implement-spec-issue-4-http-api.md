# Implementation spec — Issue #4: HTTP API server (Express)

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #3 (Backend Internals)](implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — must be complete first
> Required by: [Issue #5a (iOS Core)](implement-spec-issue-5a-ios-core.md), [Issue #6b (Deploy)](../current/implement-spec-issue-6b-railway-deploy.md)

This spec is self-contained. The implementing agent should not need any other conversation context to complete the task.

---

## 1. Context

The backend is currently a CLI script (`index.js`) that prints JSON to stdout. A native iOS app cannot call a CLI script — it makes HTTP requests. This issue converts the Node.js backend into an Express HTTP server that the iOS app can call.

The API contract defined here is the interface that Issue #5 (iOS app) will build against. Getting the JSON shape right matters more than performance or edge-case hardening at this stage.

The existing `index.js` CLI workflow must still work after this change (it is useful for manual testing). It is renamed to `cli.js` and kept as-is.

---

## 2. Decisions already made (do not relitigate)

### 2.1 Express, not a custom http module

Use Express. It is the Node.js de-facto standard for this use case. The iOS app developer is new to backend servers and needs simple, well-documented patterns.

### 2.2 `server.js` exports the app object, does not call `.listen()`

`src/server.js` creates and configures the Express app and exports it. `app.js` (the new entry point) imports it and calls `app.listen()`. This separation means the server can be imported in future tests without starting on a port.

### 2.3 Single endpoint for the MVP: `GET /api/v1/rating`

Returns the all-activities evaluation for a given lat/lon. No per-activity endpoint at this stage — the iOS dashboard fetches everything in one call on load.

### 2.4 `hours` array is shared at the top level of the response

The iOS detail view needs hourly weather values for the window of a specific activity. Embedding `hours` per-activity would send 24 objects × N activities on every request. One shared array at the top level is standard practice.

### 2.5 The `index` field on each hourly object

Add an `index` field (0–23) to each hourly object in the response. This allows the iOS app to display correct hour numbers even when `hour` (clock hour 0–23) wraps around midnight.

### 2.6 CORS is open during development

The iOS Simulator shares the Mac's network stack and hits `localhost:3000` directly. CORS is not actually needed for simulator → localhost calls, but it must be open for future web dashboard use and for physical device testing on the same Wi-Fi. Set `cors()` with no options (open) for now.

### 2.7 `.listen()` binds to `0.0.0.0`, not `localhost`

Railway (the deployment target from Issue #6) requires the server to bind to `0.0.0.0`. Using `localhost` will cause Railway health checks to fail. Set this from the start.

### 2.8 No database, no authentication

This is a stateless API. Every request fetches live weather from Meteosource and evaluates it. No caching, no auth tokens, no user management at this stage.

---

## 3. Out of scope

- Push notifications — covered in Issue #6.
- iOS app code — covered in Issue #5.
- Railway deployment — covered in Issue #6.
- Per-activity endpoint (`GET /api/v1/rating?activityId=volleyball`) — not needed for the MVP dashboard.
- Request caching — a future optimization.
- Rate limiting — a future hardening step.
- Tests for the HTTP layer — future issue.

---

## 4. API contract

### `GET /health`

Response `200`:
```json
{ "status": "ok", "timestamp": "2026-05-19T15:00:00.000Z" }
```

Railway uses this endpoint for health checks. Must respond in under 1 second with status 200.

---

### `GET /api/v1/rating?lat=&lon=&timezone=`

Query parameters:
| Param | Required | Default | Description |
|---|---|---|---|
| `lat` | yes | — | Latitude (decimal, e.g. `25.1627`) |
| `lon` | yes | — | Longitude (decimal, e.g. `55.2077`) |
| `timezone` | no | `"UTC"` | IANA timezone string passed to Meteosource |

Response `200`:
```json
{
  "forecastStart": "2026-05-19T15:00:00",
  "activities": [
    {
      "activityId": "volleyball",
      "label": "Volleyball",
      "rating": "perfect",
      "startIndex": 3,
      "endIndex": 9,
      "duration": 6,
      "displayMetrics": ["temp", "windSpeed", "humidity", "uV"]
    },
    {
      "activityId": "stargazing-lite",
      "label": "Stargazing Lite",
      "rating": null,
      "displayMetrics": ["temp", "cloudCover"]
    }
  ],
  "hours": [
    {
      "index": 0,
      "hour": 15,
      "temp": 28,
      "humidity": 45,
      "windSpeed": 12,
      "rainFall": 0,
      "cloudCover": 10,
      "visibility": 10,
      "uV": 5,
      "dustAlert": false,
      "darkness": 0,
      "douglasScale": 0,
      "swellHeight": 0,
      "swellLength": 0,
      "tide": 0,
      "seaWarning": false
    }
  ]
}
```

Notes:
- `rating` is `null` (JSON null, not the string `"null"`) when no qualifying window exists.
- `startIndex`, `endIndex`, `duration` are omitted (not present) when `rating` is `null`.
- `hours` always has exactly 24 entries.
- `forecastStart` is an ISO 8601 string without timezone offset (it is in UTC).

Error `400` (missing or invalid params):
```json
{ "error": "Missing required parameter: lat" }
```

Error `502` (upstream Meteosource failure):
```json
{ "error": "Weather data unavailable" }
```

Error `500` (unexpected):
```json
{ "error": "Internal server error" }
```

---

## 5. Changes

### 5.1 Install dependencies

```
npm install express cors
npm install --save-dev nodemon
```

### 5.2 `src/server.js` (new file)

```js
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const ratingRouter = require('./routes/rating');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.use('/api/v1', ratingRouter);

module.exports = app;
```

### 5.3 `src/routes/rating.js` (new file)

```js
const express = require('express');
const { fetchWeather } = require('../weather/fetch');
const { parseWeather } = require('../weather/parse');
const { meteosourceAdapter } = require('../weather/adapters/meteosource');
const { evaluateAll } = require('../decision/evaluateAll');

const router = express.Router();

router.get('/rating', async (req, res) => {
  const { lat, lon, timezone = 'UTC' } = req.query;

  if (!lat) return res.status(400).json({ error: 'Missing required parameter: lat' });
  if (!lon) return res.status(400).json({ error: 'Missing required parameter: lon' });

  try {
    const raw = await fetchWeather({
      lat,
      lon,
      timezone,
      language: 'en',
      sections: 'all',
      units: 'metric',
      key: process.env.API_KEY,
    });

    const { forecastStart, hours } = parseWeather(raw, meteosourceAdapter);

    // Add index field for iOS rendering
    const indexedHours = hours.map((h, i) => ({ index: i, ...h }));

    const activities = evaluateAll(hours);

    res.json({ forecastStart, activities, hours: indexedHours });
  } catch (err) {
    if (err.message?.includes('Meteosource') || err.message?.includes('fetch') || err.message?.includes('Response status')) {
      return res.status(502).json({ error: 'Weather data unavailable' });
    }
    console.error(err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

module.exports = router;
```

### 5.4 `app.js` (new file — project root)

```js
require('dotenv').config();
const app = require('./src/server');

const PORT = process.env.PORT || 3000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`time-it listening on port ${PORT}`);
});
```

### 5.5 Rename `index.js` → `cli.js`

Rename the file. No content changes needed — it still works as a standalone CLI script. The `parseWeather` destructuring update was already done in Issue #3.

### 5.6 `package.json` — update scripts and main

```json
{
  "name": "time-it",
  "version": "0.1.0",
  "description": "Weather-based activity recommender",
  "main": "app.js",
  "scripts": {
    "start": "node app.js",
    "dev":   "nodemon app.js",
    "test":  "node --test",
    "cli":   "node cli.js"
  },
  "dependencies": {
    "cors":   "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.18.2"
  },
  "devDependencies": {
    "nodemon": "^3.0.0"
  }
}
```

The exact version numbers will be set by npm during install — copy the actual installed versions from `package-lock.json` after running `npm install`.

### 5.7 `.env.example` (new file — project root)

```
API_KEY=your_meteosource_api_key_here
PORT=3000
```

This file is committed to git so future developers know what variables are needed. The `.env` file itself must remain in `.gitignore` (it already is).

---

## 6. Acceptance criteria

- [ ] `npm run dev` starts the server and prints `time-it listening on port 3000`.
- [ ] `curl http://localhost:3000/health` returns `{"status":"ok",...}` with HTTP 200.
- [ ] `curl "http://localhost:3000/api/v1/rating?lat=25.1627&lon=55.2077"` returns HTTP 200 with valid JSON containing `forecastStart`, `activities` (array), and `hours` (array of 24 objects).
- [ ] Each object in `activities` has at minimum: `activityId`, `label`, `rating`, `displayMetrics`. Objects with a non-null rating also have `startIndex`, `endIndex`, `duration`.
- [ ] `hours` array has exactly 24 entries; each entry has an `index` field (0–23).
- [ ] `curl "http://localhost:3000/api/v1/rating?lon=55.2077"` returns HTTP 400 with `{"error":"Missing required parameter: lat"}`.
- [ ] `npm test` still passes — existing decision engine tests are unaffected.
- [ ] `node cli.js` still works and prints JSON to stdout.

---

## 7. Related artifacts

- [`CONTEXT.md`](../../CONTEXT.md) — domain glossary.
- [Issue #3 (Backend Internals)](implement-spec-issue-3-backend-internals.md) ([GitHub](https://github.com/1mposer/time-it/issues/3)) — must be completed before this issue; provides `evaluateAll`, corrected activity schemas, and the `{ forecastStart, hours }` parse shape.
- [Issue #5a (iOS Core)](implement-spec-issue-5a-ios-core.md) — the iOS app implements against the JSON contract defined in Section 4 of this issue. Do not change the response shape after Issue #5 begins.
- [Issue #6b (Deploy)](../current/implement-spec-issue-6b-railway-deploy.md) — deploys the server built here to Railway.
