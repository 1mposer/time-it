# Implementation spec — Issue #6b: Railway deployment

> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: [Issue #4 (HTTP API)](../completed/implement-spec-issue-4-http-api.md) + the Phase 1/2 rebuild (both merged); the iOS app ([#5a](../completed/implement-spec-issue-5a-ios-core.md)/[#5b](../completed/implement-spec-issue-5b-ios-personalization.md)) must build cleanly.
> Required by: [#5c](implement-spec-issue-5c-location-onboarding.md) (ships against the live URL), [#6c](implement-spec-issue-6c-registration-and-digest.md), [#6d](implement-spec-issue-6d-perfect-window-detector.md).

This spec is self-contained. Recreated 2026-07-16 from the #6 grill; supersedes the deleted `implement-spec-issue-6-deploy-and-notifications.md`.

---

## Context

The stateless rating backend deploys to Railway so the iOS app can connect from a real device. This sub-issue deploys **exactly what exists**: `POST /api/v1/rating` + `GET /health`. No auth (#6a CUT, [ADR-0001](../../adr/0001-no-accounts-guest-first.md)), **no database** — Postgres is provisioned at #6c start ([ADR-0006](../../adr/0006-device-keyed-push-evaluation.md)), not here, so #6b's acceptance stays fully verifiable.

**Decisions made (do not relitigate):**
- **No Procfile, no Docker, no CI.** Railway auto-detects Node and runs `npm start`.
- GitHub push to `main` triggers redeploy.
- **No Postgres in #6b** — an idle DB would be cost + an unverifiable acceptance item.
- **App sleeping OFF** — avoids cold starts for the iOS app now; mandatory once #6c's in-process cron lands.
- iOS gets the URL via a **build-config switch** (Debug → localhost, Release → Railway), never a manual constant swap.

---

## 1. Code changes

`package.json` — bump the engines field:

```json
"engines": {
  "node": ">=20.0.0"
}
```

That is the only code change in this sub-issue.

---

## 2. Manual Railway steps (performed by the developer)

1. Push `main` to GitHub: `git push origin main`
2. [railway.app](https://railway.app) → sign in with GitHub → New Project → Deploy from GitHub repo → `time-it`.
3. In **Variables**, add `API_KEY` (Meteosource key). Wait for redeploy.
4. In **Settings**, disable app sleeping (keep the service always-on).
5. In **Settings → Domains**, note the public URL (e.g. `https://time-it-production.up.railway.app`).

---

## 3. Verify the live deployment

```bash
curl https://YOUR_RAILWAY_URL/health
# Expected: {"status":"ok","timestamp":"..."}

curl -X POST https://YOUR_RAILWAY_URL/api/v1/rating -H 'Content-Type: application/json' \
  -d '{"lat":25.1627,"lon":55.2077,"activities":[{"id":"vb","label":"Volleyball","displayMetrics":["temp"],"thresholds":{"temp":{"min":15,"max":35,"required":true}}}]}'
# Expected: HTTP 200 with forecastStart, timezone, activities[].days[], hours
```

Also verify a validation `400` (send `"lat": 999`) returns the structured `{ errors: [...] }` envelope over HTTPS.

---

## 4. iOS — build-config base URL

**Already built (audited 2026-07-16):** `ios/TimeIt/TimeIt/Networking/APIConfig.swift:4-9` already carries the `#if DEBUG` switch — Debug → `http://localhost:3000`, Release → an HTTPS placeholder. The only change is **replacing the Release placeholder with the real Railway URL** from step 2.

- Debug builds keep working against the local backend; Release builds cannot ship pointing at localhost.
- `NSAllowsLocalNetworking` lives in the single shared `Config/Info.plist` (both configurations). **Keep it as-is** — a Release build never dials localhost by construction, so the exception is inert there; splitting into per-config plists is optional hardening, not required for acceptance.
- Build a Release-configuration run on a real device (mobile data, not the dev Wi-Fi) and confirm activity cards load from the live URL.

---

## 5. Acceptance criteria

> **Deployed 2026-07-20.** Live URL: `https://time-it-production.up.railway.app` (note: `time-it-…`, not the `timeit-…` the old placeholder guessed). "App sleeping" is the **Serverless** toggle in Railway's current UI — confirmed OFF.

- [x] `package.json` `engines` says `>=20.0.0`; `npm test` green (114).
- [x] `curl https://YOUR_RAILWAY_URL/health` → 200 (verified 2026-07-20).
- [x] The POST curl above → 200 with valid day-bucketed JSON (8-bucket `days[]`, global indices, `timezone: Asia/Dubai`); the bad-lat probe → 400 `{ errors: [{ path: "lat", … }] }`.
- [x] Railway app sleeping is off (Serverless toggle disabled).
- [x] Debug simulator build still talks to `localhost:3000` (`#if DEBUG` branch untouched; full iOS suite green same day).
- [ ] Release build on a real device loads cards from the Railway URL. *(Owner's step — the Release configuration compiles against the live URL; simulator-verified 2026-07-20.)*
- [x] No Procfile, no Dockerfile, no DB were added.

---

## Related artifacts

- [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) — why Postgres waits for #6c.
- [Issue #6c](implement-spec-issue-6c-registration-and-digest.md) — provisions Postgres and adds the push layer on this deploy.
- [Issue #4 (HTTP API)](../completed/implement-spec-issue-4-http-api.md) — the server being deployed.
