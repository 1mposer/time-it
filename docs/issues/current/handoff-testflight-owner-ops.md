# Handoff — TestFlight distribution walkthrough (ROADMAP item 9, owner-ops guide)

> Created 2026-08-19 (~19:45 Asia/Dubai) by the senior-auditor session. **Fold in by 2026-08-26** — once external testers are live, fold the outcome into [ROADMAP item 9](../ROADMAP.md) and delete this file.
>
> **Your role:** walk the owner (Yaas) through App Store Connect + TestFlight, screen by screen, until friends can install via a public link. You are a **guide, not an implementer**: no code, no commits, **no `git push` to this repo ever** (every push redeploys the Railway server and can eat an in-process hourly cron tick — live push-acceptance and deploy timing belong to the senior-auditor session). You do not edit ROADMAP/STATUS/FIGMA. Read order first: `CLAUDE.md` → `docs/CONTEXT.md` → `docs/STATUS.md`.

## State as of handoff (updated 2026-08-22 — internal testing live, push lane flipped)

- **App record created** in App Store Connect: name **"Time it - Activity Weather"** (listing name only — the home-screen icon still says "Time it"; the name is changeable pre-release), bundle ID `com.timeit.app.dev`, SKU `time-it-001`, iOS only, Full Access.
- **Build 1.0 (1)** uploaded 2026-08-19, processed, export compliance answered → status **Testing** (expires in 88 days).
- **Internal testing live 2026-08-22:** 3 internal invites, including the owner — whose phone now runs the **TestFlight build** (the Xcode dev build was replaced in place).
- **`NODE_ENV=production` flipped on Railway 2026-08-22** (senior-auditor green light given after the ADR-0010 deploy) — pushes run on the production APNs lane and the first Perfect-window push was delivered end-to-end the same day. The original coordination rule below is discharged; TestFlight installs DO receive pushes once the user toggles notifications on in-app.
- No **external** group exists yet. Test Information is unfilled. **No privacy policy URL exists yet** — the blocking gap for external review (see below).

## The remaining path (walk these in order)

1. ~~**Export compliance**~~ — DONE (build reached "Testing" 2026-08-22). (Optional later: an `ITSAppUsesNonExemptEncryption=NO` Info.plist key silences the question permanently for future uploads — that's a code change; flag it to the auditor session, don't do it.)
2. **External Testing group** — create one (e.g. "Friends"). Internal groups are for App Store Connect team members only (that's what went live 2026-08-22); friends = external.
3. **Test Information** (required before Beta App Review): what-to-test description, feedback email, and **privacy policy URL**:
   - Source of truth for the policy content: [`docs/adr/0010-data-retention-privacy-posture.md`](../../adr/0010-data-retention-privacy-posture.md) — written specifically as the source sheet (fact sheet + the five App Privacy answers: anonymous device UUID, 2 dp home location = Coarse, activity profiles, suggestions; linked-to-identity **no**, tracking **no**, sharing **never**, retention indefinite, erasure deferred).
   - **Host it OUTSIDE the time-it repo** (a separate tiny public repo + GitHub Pages) — pushing to time-it redeploys the server.
4. **Add the build to the group → submit for Beta App Review** — first external build only; usually ~1 day; far lighter than App Store review. The **beta disclaimer banner + suggestion pill visible in the build is BY DESIGN** for TestFlight (sandbox-receipt gate, beta-feedback spec §3) — if review questions it, it's a TestFlight-only surface, removed for the App Store release. The gate-off flip is an App-Store-release step — **never** do it for TestFlight.
5. **Enable Public Link** on the group → `testflight.apple.com/join/…` — that URL is the invite. Friends install the TestFlight app from the App Store, tap the link. Ceiling: 10,000 external testers.
6. **App Privacy section** (Distribution tab) — fill from ADR-0010's five answers; declare **Identifiers → Device ID** (the Keychain UUID) and **Coarse Location**.

## Hard coordination rules (do not improvise around these)

- ~~**Push-lane flip**~~ — **DISCHARGED 2026-08-22:** `NODE_ENV=production` is set, the owner is on the TestFlight build, and the production-lane push is proven. TestFlight installs receive pushes as soon as the tester toggles notifications on inside the app. Do not touch `NODE_ENV` again.
- **New uploads** must bump the build number (`CFBundleVersion`) each time; same version 1.0 is fine.
- Item 9 also carries release-only steps that are **out of scope here**: the BetaGate gate-off/relocate and the `appStoreReceiptURL → AppTransaction` migration (beta-feedback spec §3 flag).

## References

[ROADMAP item 9](../ROADMAP.md) · [ADR-0010](../../adr/0010-data-retention-privacy-posture.md) · [beta-feedback spec §3/§5](implement-spec-beta-feedback.md) · [FIGMA.md §8](../../design/FIGMA.md) · APNs seam config: `src/notifications/apns.js` (`buildApnsConfig` — topic `com.timeit.app.dev`, host by `NODE_ENV`).
