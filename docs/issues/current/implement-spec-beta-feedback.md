# Implementation spec — beta feedback + test-build disclaimer (ROADMAP item 10)

> Living work order, created 2026-08-18. The **server half is built**; the iOS half is Figma-gated ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)). Status home: [ROADMAP item 10](../ROADMAP.md). Contract reference of record for the route: [CLAUDE.md — Beta feedback](../../../CLAUDE.md).

## §1 Goal

A TestFlight tester must be able to send a suggestion **from inside the app** — type, tap Send, done (no mail client, no TestFlight detour) — and must see a **disclaimer** that this is a test build, with the full release at a date to be announced. Post-release, the suggestion entry point moves to Settings as its permanent home; the disclaimer disappears.

## §2 Server — BUILT 2026-08-18

`POST /api/v1/feedback` (`src/routes/feedback.js`, `createFeedbackRouter({ db })`; table + index in `initDb()`; mounted in `server.js`). Contract mirror (owner file: CLAUDE.md):

- Body — all five required, non-empty strings: `deviceId`, `message`, `appVersion`, `build` (`CFBundleVersion` — so every suggestion reads in the context of the exact build that produced it), `iosVersion`.
- Caps: `message` ≤ **1000** chars (trimmed before storage, whitespace-only rejected); the other four ≤ **64** chars.
- `204` no body on success · `400` atomic structured validation · **`429`** over **20 suggestions per device per rolling 24h** · `500` otherwise. No `502` — no weather dependency.
- `suggestions` table has **no FK to `devices`** — feedback must not require push opt-in. Read it with SQL (Railway data browser / `psql`): `SELECT * FROM suggestions ORDER BY created_at DESC;`

## §3 Beta gating (contract)

- The **same archive** serves TestFlight and the App Store, so the gate is a **runtime** check, not a build configuration:
  `Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"` — true on dev + TestFlight installs, false on App Store installs.
- The gate controls **both** the disclaimer banner and the dashboard suggestion entry point.
- **App Review caveat (guideline 2.2 — no beta-presenting apps):** review devices can present sandbox receipts, so the App Store **release-candidate** build must flip the gate off in code (removing the disclaimer and relocating the button to Settings). That is an item-9 release-submission step — not before, or TestFlight loses the feature.

## §4 iOS client — TO BUILD (after owner approves the frames)

- **Figma:** beta dashboard variant frames — light `340:3102`, dark `340:632` (banner + "Send a suggestion" button). Approval + geometry record: [FIGMA.md §7](../../design/FIGMA.md).
- **Sheet:** text editor + Send. POSTs the §2 body. `deviceId` = the **same** Keychain install UUID `DeviceRegistration` uses (service `com.timeit.device`, mint-if-absent — push opt-in NOT required); `appVersion` = `CFBundleShortVersionString`; `build` = `CFBundleVersion`; `iosVersion` = `UIDevice.current.systemVersion`.
- **Failure UX:** any non-204 **keeps the typed text** and offers retry — a typed suggestion is never discarded. `429` surfaces the throttle message.
- **Success:** brief confirmation state, then dismiss.
- Client mirrors the 1000-char cap for its counter; the server stays authoritative ([ADR-0007](../../adr/0007-client-side-mirrors.md) discipline).

## §5 Acceptance

- [ ] Route live on Railway (`initDb()` creates `suggestions` on next deploy)
- [ ] Owner approves the two Figma frames (recorded in FIGMA.md §7)
- [ ] Banner + button render on dev/TestFlight builds only (gate verified both ways)
- [ ] A suggestion sent from a real device lands as a row with correct build metadata
- [ ] Non-204 path keeps the typed text; 429 shows the throttle message
- [ ] The gate-off/relocate step is carried into item 9's release-submission checklist
