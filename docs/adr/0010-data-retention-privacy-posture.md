# Data retention & privacy posture — store anonymously, never share; device rows are never erased

Status: Accepted (2026-08-19, owner-ruled). Amends the project's data rule from "never store anything from users" to **"store anonymously, never share."** This ADR doubles as the **source sheet** for the App Store Connect App Privacy questionnaire and for the privacy-policy URL required at TestFlight external-beta review ([ROADMAP](../issues/ROADMAP.md) item 9) — fill both from this page, not from memory.

[ADR-0001](0001-no-accounts-guest-first.md) cut accounts: the server only ever identifies a *device* (anonymous Keychain install UUID), never a human. [ADR-0006](0006-device-keyed-push-evaluation.md) then put per-device state on the push path — and treated deletion as the lifecycle end (opt-out `DELETE`s the row; a stale APNs token deletes it too). That conflates two different things: the **push address** (an APNs token, which genuinely expires) and the **user's authored data** (activity profiles, home, history), which the user rebuilt from scratch on every opt-out round-trip. This ADR splits them.

**Decision — the never-erase rule.** A `devices` row, once created, is never deleted by the server. Only the push address lifecycles:

- **Stale token** (APNs `Unregistered`/`BadDeviceToken`, surfaced as `StaleTokenError`): the server **blanks `apns_token` and keeps the row**. Today's code DELETEs the whole row — that behavior is removed; a log line is added so the event is never silent.
- **Opt-out**: the client's existing `DELETE /api/v1/devices/:deviceId` call is reinterpreted server-side as **deactivate** — blank the token, keep the row. Zero client change, deliberately: the installed app cannot be updated over the air until TestFlight (ROADMAP item 9). Still `204`, still idempotent.
- **Re-opt-in** upserts a fresh token into the **same** row; activities/home/history are never lost.
- The hourly push jobs (**#6c digest, #6d detector**) skip any row whose token is blank.

**What is stored, and how it is keyed (the Apple-facing fact sheet).**

- **`devices`** — one row per opted-in install: random client-minted UUID (Keychain install ID), APNs token, home lat/lon (**the picked home city, or a one-time foreground GPS fix at setup when no home is set** (`DeviceRegistration` home-else-GPS) — never background location; stored at full precision today, see the granularity note under the five answers), server-resolved IANA timezone, activity profiles (labels + thresholds + time windows) as JSONB, last-digest date.
- **`notification_state`** — `(device UUID, activity id, date)` dedup keys; pruned after ~2 days.
- **`suggestions`** — free-text beta feedback + app version/build/iOS version, keyed to the same anonymous UUID; deliberately **no FK to `devices`** (feedback must not require push opt-in).
- **Not stored, anywhere:** name, email, account, contacts, photos, advertising ID, or tracking of any kind. The UUID is not linked to identity and is not used to track across apps or sites.

**The five Apple-facing answers** (map directly to the App Privacy questionnaire):

1. **Data collected:** location (home — granularity note below), **identifiers** (Device ID — the Keychain UUID is transmitted and stored; declare it under *Identifiers → Device ID*), app interactions (activity profiles), user content (suggestions).
2. **Linked to identity:** **no** — anonymous device ID only.
3. **Used for tracking:** **no.**
4. **Shared with third parties:** **never** — the amended rule.
5. **Retention:** **indefinite**; user-initiated erasure: **none currently.** A user-facing "delete my data" affordance is **DEFERRED** — promote condition: real users beyond known testers, or an Apple/legal requirement surfacing at review time.

**Location-granularity ruling (owner-decided 2026-08-19): round.** The client sends full-precision coordinates (`DeviceRegistration.swift` home-else-GPS, no rounding), and Apple defines **Precise Location** as ≥3 decimal places — so the server **rounds `home_lat`/`home_lon` to 2 dp (~1.1 km) at write**, making the questionnaire answer **Coarse** honest. Functionally free: the shared weather cache already keys lookups at 2 dp, so ratings are identical. The rounding lands in the same implementation work order as the never-erase rule.

**Consequences.**

- Retained data **freezes at the moment of opt-out** — the client stops upserting, so the row is the last snapshot, aging silently.
- **No erasure path exists** (deferred above with its promote condition). Until it lands, the privacy policy states retention honestly: indefinite, anonymous, never shared.
- [ADR-0006](0006-device-keyed-push-evaluation.md)'s stale-token/opt-out-delete language becomes outdated and gets a **one-line amendment pointing here** — the amendment rides the implementation work order, not this ADR.
- **CLAUDE.md sweep checklist** — every mirror saying the server deletes the device row, to be swept in the same implementation change (per [ADR-0009](0009-tiered-doc-truth.md), a contract fact changed = sweep its mirrors together):
  1. `### DELETE /api/v1/devices/:deviceId` section — "Opt-out. Deletes the row; `204` even when the row doesn't exist (idempotent)."
  2. Daily digest job section — "A `StaleTokenError` from the APNs seam deletes the device row."
  3. Perfect-window detector section — "`StaleTokenError` deletes the device row (state rows cascade)."
  4. Module internals, `devices.js` — "…and idempotent `DELETE`" (semantics become *deactivate*).
  5. Module internals, `apns.js` — "APNs `Unregistered`/`BadDeviceToken` → typed `StaleTokenError` so callers delete the device row."
  6. Tests list, `tests/jobs/dailyDigest.test.js` — "`StaleTokenError` → row deleted."
  7. Tests list, `tests/jobs/perfectWindowDetector.test.js` — "`StaleTokenError` → device row deleted mid-pass" (and the now-vestigial `ON DELETE CASCADE` framing in the Push path intro).
  8. Module internals, `src/db.js` — "`notification_state` (cascades away with its device row)" (same vestigial cascade framing; the schema keeps the CASCADE — harmless — but the prose stops presenting deletion as the lifecycle).

Recorded because this reverses ADR-0006's deletion semantics without any wire change (the same `DELETE` request now means something different server-side — a future reader diffing route behavior against ADR-0006 needs the why), and because the App Privacy form and privacy policy must be written from one page: answers improvised at submission time are the ones that get an app rejected under guideline 5.1.

