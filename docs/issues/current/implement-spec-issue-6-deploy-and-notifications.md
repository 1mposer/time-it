# Implementation spec — Issue #6: Railway deployment + push notifications

> Domain glossary: [`CONTEXT.md`](../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) and [Issue #5 (iOS App)](implement-spec-issue-5-ios-swiftui.md) — both must be complete and tested locally before starting this issue
> Required by: nothing — this is the final issue

This spec is self-contained. The implementing agent should not need any other conversation context.

---

## 1. Context

The Express server (Issue #4) runs locally and the iOS app (Issue #5) calls `localhost:3000` in the Simulator. This issue has two parts:

**Part A (deploy now):** Deploy the Node.js backend to Railway so it is reachable from the internet, then update the iOS app to point at the live URL. After this, the app can be tested on a real iPhone over Wi-Fi and eventually submitted to the App Store.

**Part B (document for later — push notifications):** APNs push notifications require an Apple Developer account ($99/year) and a provisioned device. This part documents what to build when that account is available. Do not implement it now — only write the scaffold files with clear `// TODO:` markers.

---

## 2. Decisions already made (do not relitigate)

### 2.1 Railway is the hosting provider

Railway detects Node.js automatically, reads `npm start` from `package.json`, provides a free tier, and supports environment variables via its dashboard. It gives a stable HTTPS URL at no initial cost.

### 2.2 No Docker, no CI pipeline

Railway handles deploys via GitHub integration. Pushing to `main` triggers a redeploy. No `Dockerfile` or GitHub Actions workflow is needed at this stage.

### 2.3 APNs via the `.p8` auth key method

When implementing push notifications, use an APNs auth key (`.p8` file) rather than a certificate. Auth keys do not expire and work across all apps in an Apple Developer account. The `apn` npm package (`npm install apn`) supports this method.

### 2.4 Device tokens stored in a JSON file (initially)

For the first version of push notifications, store device tokens in a `data/devices.json` file on the server. This is not suitable for production scale but is adequate for personal use and avoids adding a database dependency. A note to migrate later is sufficient.

---

## 3. Part A — Deploy to Railway

### 3.1 Prepare the backend for Railway

**Add `Procfile`** at the project root (Railway reads this if present; it is redundant with `npm start` but makes the deploy target explicit):

```
web: node app.js
```

**Add `engines` to `package.json`** to pin the Node.js version. Insert inside the root JSON object (after `"devDependencies"`):

```json
"engines": {
  "node": ">=20.0.0"
}
```

Verify the current Node.js version with `node --version` and set the minimum to the major version in use.

**Verify `app.js` binds to `0.0.0.0`** (this was required in Issue #4):

```js
app.listen(PORT, '0.0.0.0', () => { ... });
```

If `0.0.0.0` is missing, add it — Railway's health check will fail without it.

### 3.2 Deploy steps

These steps are performed manually by the developer (not by a code agent):

1. Push the current `main` branch to GitHub:
   ```
   git push origin main
   ```
2. Go to [railway.app](https://railway.app) and sign up or log in with GitHub.
3. Click **New Project** > **Deploy from GitHub repo** > select `time-it`.
4. Railway will detect Node.js and run `npm start` automatically.
5. Wait for the first deploy to succeed (green checkmark in the Railway dashboard).
6. In the Railway project settings, go to **Variables** and add:
   ```
   API_KEY=your_meteosource_api_key_here
   ```
7. Railway triggers a redeploy after saving variables. Wait for it to complete.
8. In the Railway **Settings > Domains** panel, note the public URL (e.g. `https://time-it-production.up.railway.app`).

### 3.3 Verify the live deployment

```bash
curl https://YOUR_RAILWAY_URL/health
# Expected: {"status":"ok","timestamp":"..."}

curl "https://YOUR_RAILWAY_URL/api/v1/rating?lat=25.1627&lon=55.2077"
# Expected: HTTP 200, JSON with forecastStart, activities, hours
```

### 3.4 Update the iOS app to use the Railway URL

In `Networking/APIConfig.swift`, replace:

```swift
static let baseURL = "https://REPLACE_WITH_RAILWAY_URL"
```

with the actual Railway URL:

```swift
static let baseURL = "https://time-it-production.up.railway.app"
```

(Use the actual URL from step 3.2.8 — the example above is illustrative.)

Also remove the `NSAllowsLocalNetworking` entry from `Info.plist` — it is no longer needed since Railway uses HTTPS.

In `Info.plist` (open as source code in Xcode), delete:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

Build the iOS app again in Xcode and verify it loads data from the live Railway URL in the Simulator.

---

## 4. Part B — Push notifications scaffold (deferred)

**Do not implement this now.** Create the files listed below with `// TODO:` markers. This makes the implementation straightforward when the Apple Developer account is obtained.

### 4.1 What is required to enable push notifications

Before implementing, the developer must have:
- Apple Developer account enrolled at developer.apple.com ($99/year)
- An APNs Auth Key created in the Developer portal (produces a `.p8` file)
- Team ID (10-character string from the Developer portal)
- Key ID (10-character string from the Developer portal)
- Bundle ID matching the Xcode project (`com.timeit.app`)
- The iOS app running on a real device (push cannot be tested in the Simulator)

### 4.2 `src/notifications/apns.js` (new file — scaffold only)

```js
// TODO: implement when Apple Developer account is available
// Required: APNs .p8 auth key, Team ID, Key ID, Bundle ID
// Install: npm install apn
//
// const apn = require('apn');
//
// const provider = new apn.Provider({
//   token: {
//     key:  process.env.APNS_KEY_PATH,   // path to .p8 file
//     keyId: process.env.APNS_KEY_ID,
//     teamId: process.env.APNS_TEAM_ID,
//   },
//   production: process.env.NODE_ENV === 'production',
// });
//
// async function sendActivityAlert(deviceToken, activity) {
//   const notification = new apn.Notification();
//   notification.alert = {
//     title: `${activity.rating === 'perfect' ? 'Perfect' : 'Good'} ${activity.label} Window`,
//     body: `${activity.duration}h window starting in ${activity.startIndex}h`,
//   };
//   notification.sound = 'default';
//   notification.payload = {
//     activityId: activity.activityId,
//     startIndex: activity.startIndex,
//     duration:   activity.duration,
//   };
//   notification.topic = 'com.timeit.app';
//   await provider.send(notification, deviceToken);
// }
//
// module.exports = { sendActivityAlert };
```

### 4.3 `src/routes/devices.js` (new file — scaffold only)

```js
// TODO: implement when Apple Developer account is available
// This endpoint receives device tokens from the iOS app and stores them.
//
// const express = require('express');
// const fs = require('fs');
// const path = require('path');
//
// const router = express.Router();
// const DEVICES_PATH = path.join(__dirname, '../../data/devices.json');
//
// router.post('/devices', (req, res) => {
//   const { token } = req.body;
//   if (!token) return res.status(400).json({ error: 'Missing token' });
//
//   let devices = [];
//   if (fs.existsSync(DEVICES_PATH)) {
//     devices = JSON.parse(fs.readFileSync(DEVICES_PATH, 'utf8'));
//   }
//   if (!devices.includes(token)) {
//     devices.push(token);
//     fs.writeFileSync(DEVICES_PATH, JSON.stringify(devices, null, 2));
//   }
//   res.json({ status: 'registered' });
// });
//
// module.exports = router;
```

### 4.4 `data/` directory

Create an empty `data/.gitkeep` file so the directory is tracked in git but the `devices.json` file (which will contain device tokens) is excluded:

```
data/.gitkeep
```

Add to `.gitignore`:
```
data/devices.json
```

### 4.5 iOS app changes needed (document only — do not implement)

In `App/TimeItApp.swift`, when the Developer account is ready, add:

```swift
// TODO: add when Apple Developer account is available
// import UserNotifications
//
// class AppDelegate: NSObject, UIApplicationDelegate {
//   func application(_ app: UIApplication,
//                    didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
//     UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
//     app.registerForRemoteNotifications()
//     return true
//   }
//
//   func application(_ app: UIApplication,
//                    didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
//     let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
//     Task {
//       // POST tokenString to POST /api/v1/devices
//     }
//   }
// }
```

---

## 5. Acceptance criteria

### Part A

- [ ] `Procfile` exists at the project root with content `web: node app.js`.
- [ ] `package.json` has an `engines` field specifying `"node": ">=20.0.0"` (or the current major version).
- [ ] `curl https://YOUR_RAILWAY_URL/health` returns HTTP 200 `{"status":"ok",...}`.
- [ ] `curl "https://YOUR_RAILWAY_URL/api/v1/rating?lat=25.1627&lon=55.2077"` returns HTTP 200 with a valid `activities` array.
- [ ] The iOS app (built in Xcode) loads data from the Railway URL in the Simulator — activity cards are visible.
- [ ] `NSAllowsLocalNetworking` is no longer present in `Info.plist`.

### Part B

- [ ] `src/notifications/apns.js` exists with the scaffold commented out as shown.
- [ ] `src/routes/devices.js` exists with the scaffold commented out as shown.
- [ ] `data/.gitkeep` exists.
- [ ] `data/devices.json` is in `.gitignore`.
- [ ] `npm test` still passes — no regressions.

---

## 6. Environment variables to add on Railway

| Variable | Description |
|---|---|
| `API_KEY` | Meteosource API key (required now) |
| `APNS_KEY_PATH` | Path to `.p8` file on server (required when implementing notifications) |
| `APNS_KEY_ID` | 10-character APNs Key ID (required when implementing notifications) |
| `APNS_TEAM_ID` | 10-character Apple Team ID (required when implementing notifications) |

Document these in `.env.example` (created in Issue #4) with placeholder values.

---

## 7. Related artifacts

- [`CONTEXT.md`](../CONTEXT.md) — domain glossary.
- [Issue #4 (HTTP API)](implement-spec-issue-4-http-api.md) — the server being deployed here.
- [Issue #5 (iOS App)](implement-spec-issue-5-ios-swiftui.md) — the iOS app being connected to the live URL here.
- [Issue #3 (Backend Internals)](implement-spec-issue-3-backend-internals.md) — foundational fixes that must be in place before this deploy.
