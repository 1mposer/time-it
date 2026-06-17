# No user accounts — guest-first, local-first

Time-it ships with **no sign-in**. Sign in with Apple (planned in the #6a spec) is cut entirely: with no web companion or social features on the roadmap, we only ever need to identify a *device*, never a *human*.

Sign-in's two real jobs are reassigned to better-fit tools:
- **Cross-device sync** (phone↔iPad) → **iCloud** (`NSUbiquitousKeyValueStore`, or CloudKit private DB if the prefs blob outgrows ~1 MB / 1024 keys). Syncs across the user's own Apple devices with no login UI and no backend.
- **Server-pushed notifications (#6c)** → an **anonymous device identity** (install ID in Keychain + APNs token). Push targets a device, not a person.

Pro entitlement rides StoreKit's Apple-ID "Restore Purchases" — no app account needed. Analytics are aggregate, keyed by the anonymous install ID.

**Consequences:** the entire #6a auth stack is deleted — Apple JWKS verification, JWT issuance/storage, the `users` table, and the local→server merge/migration story (there is no account to merge into). `user_preferences` becomes keyed by anonymous device ID; `device_tokens` stays. App Store Guideline 4.8 imposes no obligation because no other login is offered.

Recorded because this reverses a written spec (#6a) and is reversible only at the cost of re-introducing the whole auth stack. The door to a real account (Tier 2) stays closed unless a human-across-devices feature appears.
