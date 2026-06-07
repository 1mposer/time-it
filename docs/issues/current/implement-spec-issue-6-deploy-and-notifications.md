# Implementation spec — Issue #6: Railway deployment + push notifications

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)), [Issue #5a](current/implement-spec-issue-5-ios-swiftui.md), [Issue #5b](current/implement-spec-issue-5-ios-swiftui.md) — iOS app must be complete before starting this issue
> This is the final backend issue.

**This issue is split into three sequential sub-issues.** Implement in order: #6a → #6b → #6c, compacting between each. Each sub-issue is fully self-contained.

---

## Sub-issue #6a — Backend infrastructure + auth

### Context

The Express server is stateless and has no concept of users (Issue #4). This sub-issue adds: a PostgreSQL database, Sign in with Apple verification, a JWT-based auth layer for protected routes, and user preferences storage. The existing `GET /api/v1/rating` and `GET /health` routes are **not modified** — they remain open and unauthenticated.

The iOS app (`AuthManager.syncWithBackend()` and `PreferencesManager.syncToBackend()`) currently has stub methods marked `// TODO: Issue #6a`. After this sub-issue, update those two methods to call the backend. The iOS project is at `~/Desktop/Projects/TimeIt-iOS/` — the implementing agent must edit those two Swift files in addition to the backend work.

**Decisions made (do not relitigate):**
- PostgreSQL via `pg` npm package. Connection via `DATABASE_URL` env var.
- Auth: Sign in with Apple identity token verified against Apple's JWKS. Server issues its own JWT signed with `JWT_SECRET`. iOS stores this JWT in Keychain and sends it as `Authorization: Bearer <token>` on protected routes.
- Client-side StoreKit gating for Pro activities. The backend does not filter activities by subscription — it always returns all 5.
- `user_preferences.timezone` is stored now (defaulting to `Asia/Dubai`) for future per-user notification scheduling, even though #6c uses a fixed schedule.

---

### 1. Install dependencies

```
npm install pg jsonwebtoken
```

No additional packages needed — Node 18+ has built-in `fetch` for Apple JWKS requests.

---

### 2. New files

#### `src/db/schema.sql`

```sql
CREATE TABLE IF NOT EXISTS users (
  id         SERIAL PRIMARY KEY,
  apple_id   TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_tokens (
  id         SERIAL PRIMARY KEY,
  user_id    INTEGER REFERENCES users(id) ON DELETE CASCADE,
  token      TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_preferences (
  user_id               INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  selected_activity_ids TEXT[]   DEFAULT '{}',
  home_lat              DOUBLE PRECISION,
  home_lon              DOUBLE PRECISION,
  timezone              TEXT     DEFAULT 'Asia/Dubai',
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_state (
  user_id            INTEGER REFERENCES users(id) ON DELETE CASCADE,
  activity_id        TEXT    NOT NULL,
  last_window_start  INTEGER,
  last_notified_at   TIMESTAMPTZ,
  PRIMARY KEY (user_id, activity_id)
);
```

#### `src/db/index.js`

```js
const { Pool } = require('pg');

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

async function initDb() {
  const fs = require('fs');
  const path = require('path');
  const schema = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  await pool.query(schema);
}

function query(text, params) {
  return pool.query(text, params);
}

module.exports = { query, initDb };
```

#### `src/middleware/auth.js`

```js
const jwt = require('jsonwebtoken');

function requireAuth(req, res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'Unauthorised' });
  }
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET);
    req.userId = payload.userId;
    next();
  } catch {
    res.status(401).json({ error: 'Unauthorised' });
  }
}

module.exports = { requireAuth };
```

#### `src/services/appleAuth.js`

```js
const jwt = require('jsonwebtoken');
const { createPublicKey } = require('crypto');

const APPLE_KEYS_URL = 'https://appleid.apple.com/auth/keys';
let cachedKeys = null;
let cacheExpiry = 0;

async function getApplePublicKeys() {
  if (cachedKeys && Date.now() < cacheExpiry) return cachedKeys;
  const res = await fetch(APPLE_KEYS_URL);
  const { keys } = await res.json();
  cachedKeys = keys;
  cacheExpiry = Date.now() + 60 * 60 * 1000;
  return keys;
}

async function verifyAppleToken(identityToken) {
  const keys = await getApplePublicKeys();
  const header = JSON.parse(Buffer.from(identityToken.split('.')[0], 'base64').toString());
  const jwk = keys.find(k => k.kid === header.kid);
  if (!jwk) throw new Error('Apple key not found');
  const publicKey = createPublicKey({ key: jwk, format: 'jwk' });
  return jwt.verify(identityToken, publicKey, { algorithms: ['RS256'] });
}

module.exports = { verifyAppleToken };
```

#### `src/routes/auth.js`

```js
const express = require('express');
const jwt = require('jsonwebtoken');
const { verifyAppleToken } = require('../services/appleAuth');
const db = require('../db');

const router = express.Router();

// POST /api/v1/auth/signin
// Body: { identityToken: string, appleUserId: string }
// Returns: { userId: number, jwt: string }
router.post('/auth/signin', async (req, res) => {
  const { identityToken, appleUserId } = req.body;
  if (!identityToken || !appleUserId) {
    return res.status(400).json({ error: 'Missing identityToken or appleUserId' });
  }
  try {
    const payload = await verifyAppleToken(identityToken);
    if (payload.sub !== appleUserId) {
      return res.status(401).json({ error: 'Token mismatch' });
    }

    const result = await db.query(
      `INSERT INTO users (apple_id) VALUES ($1)
       ON CONFLICT (apple_id) DO UPDATE SET apple_id = EXCLUDED.apple_id
       RETURNING id`,
      [appleUserId]
    );
    const userId = result.rows[0].id;

    await db.query(
      `INSERT INTO user_preferences (user_id) VALUES ($1) ON CONFLICT DO NOTHING`,
      [userId]
    );

    const token = jwt.sign({ userId }, process.env.JWT_SECRET, { expiresIn: '90d' });
    res.json({ userId, jwt: token });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: 'Authentication failed' });
  }
});

module.exports = router;
```

#### `src/routes/user.js`

```js
const express = require('express');
const db = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// GET /api/v1/user/preferences
router.get('/user/preferences', requireAuth, async (req, res) => {
  const result = await db.query(
    `SELECT selected_activity_ids, home_lat, home_lon, timezone
     FROM user_preferences WHERE user_id = $1`,
    [req.userId]
  );
  res.json(result.rows[0] ?? {});
});

// PUT /api/v1/user/preferences
// Body: { selectedActivityIds?: string[], homeLat?: number, homeLon?: number, timezone?: string }
router.put('/user/preferences', requireAuth, async (req, res) => {
  const { selectedActivityIds, homeLat, homeLon, timezone } = req.body;
  await db.query(
    `INSERT INTO user_preferences (user_id, selected_activity_ids, home_lat, home_lon, timezone, updated_at)
     VALUES ($1, $2, $3, $4, $5, NOW())
     ON CONFLICT (user_id) DO UPDATE SET
       selected_activity_ids = COALESCE($2, user_preferences.selected_activity_ids),
       home_lat  = COALESCE($3, user_preferences.home_lat),
       home_lon  = COALESCE($4, user_preferences.home_lon),
       timezone  = COALESCE($5, user_preferences.timezone),
       updated_at = NOW()`,
    [req.userId, selectedActivityIds ?? null, homeLat ?? null, homeLon ?? null, timezone ?? null]
  );
  res.json({ status: 'updated' });
});

module.exports = router;
```

#### `src/routes/devices.js`

```js
const express = require('express');
const db = require('../db');
const { requireAuth } = require('../middleware/auth');

const router = express.Router();

// POST /api/v1/devices
// Body: { token: string }
router.post('/devices', requireAuth, async (req, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ error: 'Missing token' });
  await db.query(
    `INSERT INTO device_tokens (user_id, token) VALUES ($1, $2)
     ON CONFLICT (token) DO UPDATE SET user_id = $1`,
    [req.userId, token]
  );
  res.json({ status: 'registered' });
});

module.exports = router;
```

---

### 3. Modified backend files

#### `src/server.js` — mount new routers

Add after the existing `app.use('/api/v1', ratingRouter)` line:

```js
const authRouter    = require('./routes/auth');
const userRouter    = require('./routes/user');
const devicesRouter = require('./routes/devices');

app.use('/api/v1', authRouter);
app.use('/api/v1', userRouter);
app.use('/api/v1', devicesRouter);
```

#### `app.js` — run `initDb()` before listen

```js
require('dotenv').config();
const app = require('./src/server');
const { initDb } = require('./src/db');

const PORT = process.env.PORT || 3000;

initDb()
  .then(() => {
    app.listen(PORT, '0.0.0.0', () => {
      console.log(`time-it listening on port ${PORT}`);
    });
  })
  .catch(err => {
    console.error('Failed to initialise database:', err);
    process.exit(1);
  });
```

#### `.env.example` — add new vars

```
API_KEY=your_meteosource_api_key_here
PORT=3000
DATABASE_URL=postgres://localhost:5432/timeit
JWT_SECRET=change_me_to_a_random_secret
```

---

### 4. iOS integration — update stub methods

The iOS project is at `~/Desktop/Projects/TimeIt-iOS/`. Update two files:

#### `Services/AuthManager.swift` — implement `syncWithBackend()`

The current stub inside `handleSignIn` is `// TODO: Issue #6a`. Replace it:

```swift
// After KeychainHelper.save(key: "appleUserId", value: userId):
if let tokenData = credential.identityToken,
   let identityToken = String(data: tokenData, encoding: .utf8) {
    Task {
        try? await syncWithBackend(appleUserId: userId, identityToken: identityToken)
    }
}

// Add this method to AuthManager:
private func syncWithBackend(appleUserId: String, identityToken: String) async throws {
    guard let url = URL(string: "\(APIConfig.baseURL)/api/v1/auth/signin") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: [
        "identityToken": identityToken,
        "appleUserId":   appleUserId,
    ])
    let (data, _) = try await URLSession.shared.data(for: request)
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let jwt = json["jwt"] as? String {
        KeychainHelper.save(key: "serverJWT", value: jwt)
    }
}
```

#### `Services/PreferencesManager.swift` — implement `syncToBackend()`

Replace the stub:

```swift
func syncToBackend() async throws {
    guard let jwt = KeychainHelper.read(key: "serverJWT"),
          let url = URL(string: "\(APIConfig.baseURL)/api/v1/user/preferences") else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
    var body: [String: Any] = ["selectedActivityIds": Array(selectedActivityIds)]
    if let home = homeLocation {
        body["homeLat"] = home.lat
        body["homeLon"] = home.lon
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    try await URLSession.shared.data(for: request)
}
```

Also call `syncToBackend()` from `completeOnboarding()` in `AuthManager`:

```swift
func completeOnboarding(appleUserId: String) {
    appState = .authenticated(appleUserId: appleUserId)
    Task { try? await PreferencesManager.shared.syncToBackend() }
}
```

---

### 5. Local development setup

Requires a running PostgreSQL instance:

```
createdb timeit
DATABASE_URL=postgres://localhost:5432/timeit npm run dev
```

Tables are created automatically by `initDb()` on server start.

---

### 6. Acceptance criteria

- [ ] `npm run dev` starts the server and prints `time-it listening on port 3000`.
- [ ] `npm test` — all 15 existing tests still pass.
- [ ] `POST /api/v1/auth/signin` with a valid Apple identity token returns `{ userId, jwt }`.
- [ ] `GET /api/v1/user/preferences` with a valid Bearer token returns the user's preferences row.
- [ ] `PUT /api/v1/user/preferences` with `{ selectedActivityIds: ["volleyball"] }` updates the row.
- [ ] `POST /api/v1/devices` with a valid token registers it in `device_tokens`.
- [ ] `GET /api/v1/rating` (no auth) still returns HTTP 200 — existing behaviour unchanged.
- [ ] iOS: After sign-in, `AuthManager` calls `syncWithBackend()` and stores the server JWT in Keychain.
- [ ] iOS: After onboarding, `PreferencesManager.syncToBackend()` is called and preferences appear in the database.

---

## Sub-issue #6b — Railway deployment

### Context

The backend has a database, auth, and user preference routes (Issue #6a). This sub-issue deploys it to Railway so the iOS app can connect from a real device.

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
   - `JWT_SECRET` — a random secret (e.g. `openssl rand -hex 32`)
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
- [Issue #5](current/implement-spec-issue-5-ios-swiftui.md) ([GitHub](https://github.com/1mposer/time-it/issues/5)) — iOS app that integrates with the backend built here.
- [Issue #4 (HTTP API)](completed/implement-spec-issue-4-http-api.md) ([GitHub](https://github.com/1mposer/time-it/issues/4)) — the server being extended and deployed here.
