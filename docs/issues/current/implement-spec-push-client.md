# Implementation spec — iOS push opt-in client + live acceptance

> Extracted 2026-08-10 from the completed backend specs ([#6c](../completed/implement-spec-issue-6c-registration-and-digest.md) §9 and [#6d](../completed/implement-spec-issue-6d-perfect-window-detector.md) §4) so the living work has one home. Architecture of record: [ADR-0006](../../adr/0006-device-keyed-push-evaluation.md) + [ADR-0001](../../adr/0001-no-accounts-guest-first.md). Both server backends are **built and deployed** (2026-08-03) — this spec is client-side only, plus the end-to-end acceptance pass.
> **Depends on:** the APNs entitlement in Xcode (owner, Signing & Capabilities) and the `PRODUCT_BUNDLE_IDENTIFIER` → `com.timeit.app.dev` rename (ROADMAP ship item 4). *(The Meteosource renewal — [#11](https://github.com/1mposer/time-it/issues/11) — was done 2026-08-11.)*
> **Build order:** preferably after spec 14's minimal cut lands — its dormancy model changes the snapshot projection (§2) — but this is a preference, not an essential dependency.
> **UI gate ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)):** the §1 opt-in surfaces (Settings "Notifications" row + dashboard callout) need owner-approved frames first — they are in the [FIGMA.md §7](../../design/FIGMA.md) backlog; the §2 plumbing is not gated.
> **TDD required.** A real device is required (APNs does not work in the Simulator). The backend selects the sandbox APNs host while Railway `NODE_ENV` is unset — correct for Xcode dev builds (the TestFlight `NODE_ENV=production` step: [ROADMAP](../ROADMAP.md) item 9).
> **Build status:** the client build (§1–§5) landed 2026-08-17 — status of record: [ROADMAP items 7–8](../ROADMAP.md). §6 below is the living acceptance checklist; this spec moves to `completed/` when those boxes tick.

---

## 1. Opt-in surfaces

- **Settings toggle "Notifications"** (the real switch) + a **one-time dismissible dashboard callout** ("Get a morning digest + Perfect-window alerts") that deep-links to it. (Settings' Notifications section was deliberately hidden until now — grill Q9's "no inert switches".)
- Toggle ON: if there is no real Active location (picked home or a GPS grant), route through the #5c onboarding first; then `UNUserNotificationCenter.requestAuthorization` → `registerForRemoteNotifications`.
- Toggle OFF: `DELETE /api/v1/devices/:deviceId` → `204` (keep the Keychain ID).

## 2. `DeviceRegistration` service

- Mints/reads the install UUID from the **Keychain** (survives reinstall — ADR-0001).
- On APNs token receipt (`didRegisterForRemoteNotificationsWithDeviceToken` — hex-encode; the deleted #6 spec's AppDelegate skeleton minus the JWT header is salvageable from git history), `PUT`s the **full snapshot** `{ apnsToken, home: { lat, lon }, activities: [...] }` to `/api/v1/devices/:deviceId` (client-authoritative, last-write-wins).
- **Snapshot contents:** the wire projection of the persisted `ActivityStore` list — the user's authored Activities (`SeedTemplates` is a Template *catalog*, not the shipped list). Authored windows, including nocturnal wraps, go over the wire — the server's digest/detector read them for "tonight" copy. **Dormancy rule (spec 14 §1): a dormant Activity (`window == nil`) is excluded from the snapshot**, exactly as it is excluded from the `/rating` POST body.
- **Snapshot location:** the home location if set, else the current GPS fix; **never** the last-resolved cache and never any fallback constant (ADR-0006 — no fallback-location push).
- **Re-upsert triggers** (only while the toggle is on): any `ActivityStore` mutation, a home-location change, an APNs token refresh, and app-launch-if-stale. Deleting the last live Activity upserts an **empty** snapshot — valid (a dormant registration), keeping the server copy fresh rather than stale. Failures retry on the next trigger — no bespoke queue.

## 3. Push receipt

- Detector payload (#6d): `{ type: 'perfectWindow', activityId, bucketDate }`. Tapping the push opens the app and lands on the dashboard with the named Activity's card visible — its "Today/Tonight · <time>" sublabel is the push's receipt (spec 14 pins the copy match word-for-word). No deeper routing in v1.
- Digest pushes: default open → dashboard.

## 4. #5c facts this build relies on

- `PreferencesStore.homeLocation` + `lastResolvedLocation` are persisted `SavedLocation`s (optional `region` field); registration reads home/GPS only (§2).
- The location permission prompt is CTA-gated (`LocationProviding.requestAuthorization()` — app loads never prompt).
- XCUI location args: `UITEST_LOCATION` / `UITEST_LOCATION_DENIED`; `UITEST_RESET` wipes all persisted keys.

## 5. Tests

- `DeviceRegistration` unit tests: Keychain seam, snapshot body (dormant exclusion + nocturnal window passthrough), re-upsert trigger wiring, empty-snapshot on last-delete, `DELETE` on toggle-off.
- XCUI (mock-seamed): toggle → prompt flow; callout deep-link.
- Full iOS suite stays green; `npm test` untouched.

## 6. Live acceptance (end-to-end; needs a registered real device)

From #6c §11:
- [ ] Real device: toggle on → permission prompt → a row appears in `devices` with a server-resolved IANA timezone.
- [ ] Editing an Activity re-upserts the snapshot (the row's `activities` JSONB changes).
- [ ] Digest: a device whose local hour is in the 6–11 band gets **one** push listing today's windows (+ the week-ahead Perfect line when present); a second pass the same local day sends nothing.
- [ ] Toggle off deletes the row; a stale-token send deletes the row.

From #6d §4:
- [ ] Force a Perfect window (loose thresholds) → exactly one push; the next hourly run re-sends nothing.
- [ ] Tighten thresholds so the bucket is Good-only, then loosen → the upgrade push arrives.
- [ ] A Perfect day 3+ days out never triggers the detector but shows in the next digest's week-ahead line.
- [ ] `notification_state` stays pruned (no unbounded growth).

Spec 14 interaction:
- [ ] A dormant Activity never appears in any request body or snapshot; the owner's post-update all-dormant first launch is **expected behavior**, not a regression (SPEC_14_FEASIBILITY I2).
