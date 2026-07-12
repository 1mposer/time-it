# Implementation spec — Issue #6: Railway deployment + push notifications

> ⚠️ **STALE — predates the Phase 1/2 rebuild AND the no-accounts decision. Needs reconciliation before implementing (like #5b got).** Two independent invalidations: (1) the route is **`POST /api/v1/rating`** (body `{ lat, lon, activities[] }`, caller-supplied activities), not the old `GET`; the engine is `evaluateAll(hours, activities)`. (2) **Sub-issue #6a (accounts/auth) is CUT** by [ADR-0001](../../adr/0001-no-accounts-guest-first.md) — no Sign in with Apple, no JWT, no users table, no server-side user-preferences API; preferences are **client-side** ([#5b](implement-spec-issue-5b-ios-personalization.md): `ActivityStore`/`PreferencesStore` in UserDefaults, no cloud sync). Only **#6b (Railway deploy)** and **#6c (push — re-scoped device-keyed, not user-keyed)** survive. Reconcile #6b/#6c against [ADR-0001](../../adr/0001-no-accounts-guest-first.md) + [ADR-0005](../../adr/0005-custom-activity-request-schema.md) + [STATUS.md](../../STATUS.md) §5 before implementing.

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)), [Issue #5a](current/implement-spec-issue-5a-ios-core.md), [Issue #5b](current/implement-spec-issue-5b-ios-personalization.md) — iOS app must be complete before starting this issue
> This is the final backend issue.

**This issue is split into three sequential sub-issues.** Implement in order: #6a → #6b → #6c, compacting between each. Each sub-issue is fully self-contained.

---

## Sub-issue #6a — ~~Backend infrastructure + auth~~ · **CUT (ADR-0001)**

> **This sub-issue is CUT — [ADR-0001](../../adr/0001-no-accounts-guest-first.md) (no accounts, guest-first).** The original #6a (PostgreSQL `users` / `user_preferences` tables, Sign in with Apple + Apple-JWKS verification, JWT auth middleware, the `POST /auth/signin` + `GET`/`PUT /user/preferences` routes, and the iOS `AuthManager.syncWithBackend()` / `PreferencesManager.syncToBackend()` stubs) is dead: there are no user accounts and no server-side user state. Preferences live **client-side** ([Issue #5b](implement-spec-issue-5b-ios-personalization.md): `ActivityStore` + `PreferencesStore` in `UserDefaults`, no cloud sync). Any launch-time backend storage (e.g. a push-token store) is **device-keyed** via an anonymous device ID — scope it with #6c, not here. **Nothing in this sub-issue survives; start #6 at #6b.**

---

## Sub-issue #6b — Railway deployment

### Context

The stateless rating backend (Issue #4 + the Phase 1/2 rebuild) deploys to Railway so the iOS app can connect from a real device. There is no auth or user database (#6a is CUT — ADR-0001); this deploys the open `POST /api/v1/rating` + `GET /health` only. A PostgreSQL add-on is needed **only if** #6c ships a device-keyed push-token store.

**Decisions made (do not relitigate):**
- Railway detects Node.js automatically and runs `npm start`.
- GitHub push to `main` triggers redeploy.
- No Docker, no CI pipeline.
- Railway PostgreSQL add-on provides `DATABASE_URL` automatically.

---

### 1. Code changes

#### Add `Procfile` (project root)

```
web: node app.js
```

#### Update `package.json` — add `engines`

Run `node --version` and use the current major version. Add inside the root JSON object:

```json
"engines": {
  "node": ">=20.0.0"
}
```

---

### 2. Manual Railway deployment steps

These steps are performed by the developer, not by code:

1. Push `main` to GitHub: `git push origin main`
2. Go to [railway.app](https://railway.app), sign in with GitHub.
3. New Project > Deploy from GitHub repo > select `time-it`.
4. Wait for first deploy (Railway runs `npm start` → `initDb()` runs, tables are created).
5. In the Railway project: click **+ New** > **Database** > **Add PostgreSQL**. Railway automatically sets `DATABASE_URL` in the project environment.
6. In **Variables**, add:
   - `API_KEY` — Meteosource key
7. Wait for redeploy after saving variables.
8. In **Settings > Domains**, note the public URL (e.g. `https://time-it-production.up.railway.app`).

---

### 3. Verify the live deployment

```bash
curl https://YOUR_RAILWAY_URL/health
# Expected: {"status":"ok","timestamp":"..."}

curl "https://YOUR_RAILWAY_URL/api/v1/rating?lat=25.1627&lon=55.2077"
# Expected: HTTP 200 with forecastStart, activities, hours
```

---

### 4. Update the iOS app

In `~/Desktop/Projects/TimeIt-iOS/TimeIt/Networking/APIConfig.swift`, replace:

```swift
static let baseURL = "https://REPLACE_WITH_RAILWAY_URL"
```

with the actual Railway URL.

Also remove `NSAllowsLocalNetworking` from `Info.plist` — it is no longer needed since Railway uses HTTPS.

Build and run on a real device to confirm it loads data from the live URL.

---

### 5. Acceptance criteria

- [ ] `Procfile` exists at the project root.
- [ ] `package.json` has an `engines` field.
- [ ] `curl https://YOUR_RAILWAY_URL/health` returns HTTP 200.
- [ ] `curl "https://YOUR_RAILWAY_URL/api/v1/rating?lat=25.1627&lon=55.2077"` returns HTTP 200 with valid JSON.
- [ ] iOS app (built in Xcode with the updated Railway URL) loads activity cards in the Simulator.
- [ ] iOS app on a real device (same Wi-Fi or mobile data) loads activity cards.
- [ ] `NSAllowsLocalNetworking` is gone from `Info.plist`.

---

## Sub-issue #6c — Push notifications

### Context

The backend is deployed on Railway with PostgreSQL (Issue #6b). This sub-issue adds two scheduled jobs and the APNs notification layer.

**Prerequisites (must be in place before starting):**
- Apple Developer account ($99/year) enrolled at developer.apple.com
- APNs Auth Key (`.p8` file) created in the Developer portal — download and keep it safe
- Team ID (10-character string from Developer portal)
- Key ID (10-character string from Developer portal)
- iOS app running on a real physical device (APNs cannot be tested in the Simulator)
- App registered in App Store Connect with bundle ID `com.timeit.app`

**Decisions made (do not relitigate):**
- Daily digest cron: `0 2 * * *` (2am UTC = 6am UAE time, UTC+4). Fixed schedule — `timezone` is stored per user for future per-user scheduling without a schema change.
- Hourly Perfect window detector: `0 * * * *`. Sends only when a new Perfect window appears for a user's activity — de-duplicates via `notification_state` table.
- Meteosource weather cache: in-memory, keyed by `"lat,lon"`, 30-minute TTL. Mandatory — without it, hourly polling for N users causes N × 24 Meteosource API calls per day.
- Notifications sent only when at least one qualifying window exists. No "no windows today" notification.
- Both jobs filter to each user's `selected_activity_ids`.

---

### 1. Install dependencies

```
npm install node-cron apn
```

---

### 2. New files

#### `src/services/weatherCache.js`

```js
const { getWeather } = require('../weather');

const cache = new Map();
const TTL_MS = 30 * 60 * 1000;

async function getCachedWeather(lat, lon, timezone = 'UTC') {
  const key = `${lat},${lon}`;
  const entry = cache.get(key);
  if (entry && Date.now() - entry.timestamp < TTL_MS) return entry.data;
  const data = await getWeather(lat, lon, timezone);
  cache.set(key, { data, timestamp: Date.now() });
  return data;
}

module.exports = { getCachedWeather };
```

#### `src/notifications/apns.js`

```js
const apn = require('apn');

const provider = new apn.Provider({
  token: {
    key:    process.env.APNS_KEY_PATH,
    keyId:  process.env.APNS_KEY_ID,
    teamId: process.env.APNS_TEAM_ID,
  },
  production: process.env.NODE_ENV === 'production',
});

async function sendActivityAlert(deviceToken, { label, rating, duration, startIndex }) {
  const note = new apn.Notification();
  note.alert = {
    title: `${rating === 'perfect' ? 'Perfect' : 'Good'} ${label} window`,
    body:  `${duration}h window starting in ${startIndex}h`,
  };
  note.sound   = 'default';
  note.topic   = 'com.timeit.app';
  note.payload = { label, rating, duration, startIndex };
  await provider.send(note, deviceToken);
}

module.exports = { sendActivityAlert };
```

#### `src/jobs/dailyDigest.js`

```js
const db                    = require('../db');
const { getCachedWeather }  = require('../services/weatherCache');
const { evaluateAll }       = require('../decision');
const { sendActivityAlert } = require('../notifications/apns');

async function runDailyDigest() {
  console.log('[dailyDigest] running');
  const { rows: users } = await db.query(`
    SELECT u.id, dt.token, up.selected_activity_ids, up.home_lat, up.home_lon
    FROM users u
    JOIN device_tokens dt ON dt.user_id = u.id
    JOIN user_preferences up ON up.user_id = u.id
    WHERE up.home_lat IS NOT NULL AND array_length(up.selected_activity_ids, 1) > 0
  `);

  for (const user of users) {
    try {
      const { hours } = await getCachedWeather(user.home_lat, user.home_lon);
      const results = evaluateAll(hours).filter(r =>
        user.selected_activity_ids.includes(r.activityId) && r.rating !== null
      );
      for (const activity of results) {
        await sendActivityAlert(user.token, activity);
      }
    } catch (err) {
      console.error(`[dailyDigest] failed for user ${user.id}:`, err.message);
    }
  }
}

module.exports = { runDailyDigest };
```

#### `src/jobs/perfectWindowDetector.js`

```js
const db                    = require('../db');
const { getCachedWeather }  = require('../services/weatherCache');
const { evaluateAll }       = require('../decision');
const { sendActivityAlert } = require('../notifications/apns');

async function runPerfectWindowDetector() {
  console.log('[perfectWindowDetector] running');
  const { rows: users } = await db.query(`
    SELECT u.id, dt.token, up.selected_activity_ids, up.home_lat, up.home_lon
    FROM users u
    JOIN device_tokens dt ON dt.user_id = u.id
    JOIN user_preferences up ON up.user_id = u.id
    WHERE up.home_lat IS NOT NULL AND array_length(up.selected_activity_ids, 1) > 0
  `);

  for (const user of users) {
    try {
      const { hours } = await getCachedWeather(user.home_lat, user.home_lon);
      const results = evaluateAll(hours).filter(r =>
        user.selected_activity_ids.includes(r.activityId) && r.rating === 'perfect'
      );

      for (const activity of results) {
        const { rows } = await db.query(
          `SELECT last_window_start FROM notification_state
           WHERE user_id = $1 AND activity_id = $2`,
          [user.id, activity.activityId]
        );
        const lastStart = rows[0]?.last_window_start;

        if (lastStart !== activity.startIndex) {
          await sendActivityAlert(user.token, activity);
          await db.query(
            `INSERT INTO notification_state (user_id, activity_id, last_window_start, last_notified_at)
             VALUES ($1, $2, $3, NOW())
             ON CONFLICT (user_id, activity_id) DO UPDATE SET
               last_window_start = $3, last_notified_at = NOW()`,
            [user.id, activity.activityId, activity.startIndex]
          );
        }
      }
    } catch (err) {
      console.error(`[perfectWindowDetector] failed for user ${user.id}:`, err.message);
    }
  }
}

module.exports = { runPerfectWindowDetector };
```

#### `src/jobs/index.js`

```js
const cron = require('node-cron');
const { runDailyDigest }           = require('./dailyDigest');
const { runPerfectWindowDetector } = require('./perfectWindowDetector');

function startJobs() {
  cron.schedule('0 2 * * *', runDailyDigest);
  cron.schedule('0 * * * *', runPerfectWindowDetector);
  console.log('Cron jobs started');
}

module.exports = { startJobs };
```

---

### 3. Modified files

#### `src/routes/rating.js` — use weather cache

Replace `require('../weather')` import and the `getWeather` call:

```js
const { getCachedWeather } = require('../services/weatherCache');

// Inside the route handler, replace:
//   const { forecastStart, hours } = await getWeather(lat, lon, timezone);
// with:
const { forecastStart, hours } = await getCachedWeather(lat, lon, timezone);
```

Remove the `require('../weather')` import since it is now consumed by `weatherCache`.

#### `app.js` — start cron jobs after listen

```js
require('dotenv').config();
const app = require('./src/server');
const { initDb } = require('./src/db');
const { startJobs } = require('./src/jobs');

const PORT = process.env.PORT || 3000;

initDb()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`time-it listening on port ${PORT}`);
      startJobs();
    });
  })
  .catch(err => {
    console.error('Failed to initialise database:', err);
    process.exit(1);
  });
```

#### `.env.example` — add APNs vars

```
API_KEY=your_meteosource_api_key_here
PORT=3000
DATABASE_URL=postgres://localhost:5432/timeit
JWT_SECRET=change_me_to_a_random_secret
APNS_KEY_PATH=/path/to/AuthKey_XXXXXXXXXX.p8
APNS_KEY_ID=XXXXXXXXXX
APNS_TEAM_ID=XXXXXXXXXX
```

---

### 4. Railway env vars to add

In the Railway project Variables panel, add:
- `APNS_KEY_PATH` — upload the `.p8` file and set the path
- `APNS_KEY_ID` — 10-character key ID from Apple Developer portal
- `APNS_TEAM_ID` — 10-character team ID from Apple Developer portal

---

### 5. iOS integration — register device token

In `App/TimeItApp.swift`, add push notification registration after sign-in:

```swift
import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ app: UIApplication,
                     didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        return true
    }

    func application(_ app: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        Task {
            guard let jwt = KeychainHelper.read(key: "serverJWT"),
                  let url = URL(string: "\(APIConfig.baseURL)/api/v1/devices") else { return }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["token": tokenString])
            try? await URLSession.shared.data(for: request)
        }
    }
}

// In TimeItApp.swift, add inside the struct:
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

Call `UIApplication.shared.registerForRemoteNotifications()` after successful sign-in (inside `AuthManager.handleSignIn`, after setting `appState`).

---

### 6. Acceptance criteria

- [ ] `npm test` — all 15 existing tests still pass.
- [ ] `npm run dev` starts the server and logs `Cron jobs started`.
- [ ] `GET /api/v1/rating` uses the weather cache — the second identical request within 30 minutes does not trigger a Meteosource API call (verify via Meteosource dashboard request count).
- [ ] A user with a device token and preferences in the database receives a daily digest notification at 6am UAE time (verify manually or by temporarily running `runDailyDigest()` directly).
- [ ] A user with a Perfect window receives a push notification from `runPerfectWindowDetector()`.
- [ ] A second run of `runPerfectWindowDetector()` for the same open window does not re-send the notification.
- [ ] The iOS app running on a real device registers its APNs token in `device_tokens` after sign-in.

---

## Related artifacts

- [`CONTEXT.md`](../../CONTEXT.md) — domain glossary.
- [Issue #5a](current/implement-spec-issue-5a-ios-core.md) / [#5b](current/implement-spec-issue-5b-ios-personalization.md) ([GitHub](https://github.com/1mposer/time-it/issues/5)) — iOS app that integrates with the backend built here.
- [Issue #4 (HTTP API)](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — the server being extended and deployed here.
