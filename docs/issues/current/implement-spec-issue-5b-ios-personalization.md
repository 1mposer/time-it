# Implementation spec — Issue #5b: Personalization layer

> ⚠️ **STALE — predates the Phase 1/2 rebuild; do not build from this verbatim.** It assumes the backend returns a fixed server-side activity list ("the backend always returns all activities"). The shipped backend is **activity-agnostic**: activities are **caller-supplied** in the `POST /api/v1/rating` body and authored client-side (from Templates), so client-side filtering operates over the locally-authored set, not a server list. Reconcile against [ADR-0002](../../adr/0002-activity-agnostic-engine.md) + [ADR-0005](../../adr/0005-custom-activity-request-schema.md) and [STATUS.md](../../STATUS.md) §5 before implementing.

> Design decisions: [`design-decisions-issue-5.md`](design-decisions-issue-5.md) — read before starting.
> Visual spec: [`ios/guidelines/Guidelines.md`](../../../ios/guidelines/Guidelines.md)
> Domain glossary: [`CONTEXT.md`](../../CONTEXT.md)
> Depends on: Issue #5a — `time-it/ios/TimeIt/` must exist and build cleanly before starting this.
> Required by: Issue #6.

**TDD required.** Write all tests before any implementation. Run red first, implement until green.

---

## Context

Adds onboarding, activity filtering, home location, StoreKit 2 Pro gating, and a Settings screen on top of the core app built in #5a. The backend always returns all activities; all filtering is client-side.

---

## Architecture additions

**`AppState`** gets a third case: `.onboarding(appleUserId: String)`. `AuthManager` transitions there after sign-in when `hasCompletedOnboarding` is false.

**`PreferencesManager`** — `@MainActor`, `ObservableObject`, shared singleton. Owns `selectedActivityIds: Set<String>`, `homeLocation: SavedLocation?`, `isPro: Bool`. Persists via `UserDefaults`. `hasCompletedOnboarding` is true when `selectedActivityIds` is non-empty. `checkProEntitlement() async` queries StoreKit 2 `Transaction.currentEntitlements` for product ID `com.timeit.app.pro_monthly`. `syncToBackend()` is a documented stub (Issue #6a).

**`DashboardViewModel`** gains `visibleActivities` — returns all activities when `selectedActivityIds` is empty (guest), otherwise filters to the selected set. `loadForecast()` uses `homeLocation` coords when set, GPS otherwise.

---

## 1. Updated `AppState`

Add `.onboarding(appleUserId: String)` to the existing enum. `AuthManager.handleSignIn` must now transition to `.onboarding` when `!PreferencesManager.shared.hasCompletedOnboarding`, and to `.authenticated` otherwise.

---

## 2. New service: `PreferencesManager`

Persists user preferences to `UserDefaults`:
- `selectedActivityIds: Set<String>` — keyed as a string array
- `homeLocation: SavedLocation?` — encoded as JSON data. `SavedLocation` is a small `Codable` struct with `lat` and `lon` doubles.
- `isPro: Bool` — derived from StoreKit, not persisted directly

`save()` writes both values to `UserDefaults`. `load()` (called on init) restores them. `checkProEntitlement()` sets `isPro` after querying StoreKit.

---

## 3. New views

### `OnboardingView`

Shown immediately after first sign-in (when `appState == .onboarding`). Two sequential steps:

1. **Activity selection** — display all 5 activities as selectable rows (icon + name). User must select at least one before proceeding. "Next" is disabled until a selection is made.
2. **Location picker** — option to set a home location (city name → geocoded lat/lon via `CLGeocoder`) or skip (uses GPS). "Done" completes onboarding.

On completion: call `PreferencesManager.shared.save()`, then `AuthManager.shared.completeOnboarding()` which transitions `appState` to `.authenticated(appleUserId:)`.

### `SettingsView`

Accessible via a gear icon (to be added to the dashboard for authenticated users — placement your discretion, consistent with the guidelines doc). Contains:
- Activity selection (reuses the same selection UI from onboarding, pre-populated with current `selectedActivityIds`)
- Home location (reuses the location picker from onboarding)
- Sign out button

### `ProPaywallView`

Shown when a non-Pro user taps a Pro-gated card. Fetches the StoreKit product `com.timeit.app.pro_monthly` and displays its localised name, price, and a purchase button. On successful purchase, `PreferencesManager.isPro` becomes true and the view dismisses.

---

## 4. Modified views

### `ActivityCardView`

Add a lock overlay on cards where `activity.isPro && !PreferencesManager.shared.isPro`. Tapping such a card (from `DashboardView`) opens `ProPaywallView` instead of `ActivityDetailView`.

### `DashboardView`

Replace `forecast.activities` with `vm.visibleActivities` in the card list. Add the Settings entry point for authenticated users.

### `TimeItApp`

Root view switches on `authManager.appState`: `.onboarding` → `OnboardingView`, `.guest` / `.authenticated` → `DashboardView`.

---

## 5. `AuthManager` additions

- `completeOnboarding()` — transitions from `.onboarding(appleUserId:)` to `.authenticated(appleUserId:)`.
- `handleSignIn` now checks `PreferencesManager.shared.hasCompletedOnboarding` to decide between `.onboarding` and `.authenticated`.

---

## 6. Tests

### Unit tests (`TimeItTests/`)

**`PreferencesManagerTests`**
- `hasCompletedOnboarding` is false when `selectedActivityIds` is empty
- `hasCompletedOnboarding` is true after adding at least one activity ID
- `save()` persists `selectedActivityIds` and `load()` restores it via `UserDefaults`
- `homeLocation` persists and restores correctly

**`AuthManagerOnboardingTests`**
- After sign-in with no completed onboarding, `appState` is `.onboarding`
- After sign-in with completed onboarding, `appState` is `.authenticated`
- `completeOnboarding()` transitions from `.onboarding` to `.authenticated`

**`DashboardViewModelFilterTests`**
- `visibleActivities` returns all activities when `selectedActivityIds` is empty
- `visibleActivities` returns only selected activities when `selectedActivityIds` is non-empty
- `loadForecast()` uses `homeLocation` coords when set, GPS otherwise

### Acceptance tests (`TimeItUITests/`)

- After first sign-in, `OnboardingView` is shown
- Completing activity selection and location picker transitions to `DashboardView`
- Dashboard shows only selected activities
- Re-launching with existing Keychain entry skips onboarding
- Settings accessible from the dashboard; activity selection and location picker navigable from it
- `boat-fishing-pro` card shows a lock overlay for non-Pro users
- Sign out resets to `.guest` and shows all 5 default activities

---

## 7. Acceptance criteria

- [ ] Zero build errors
- [ ] After sign-in, `OnboardingView` shown for a new user; skipped for returning user
- [ ] After completing onboarding, dashboard shows only selected activities
- [ ] Dashboard uses home location (if set) over GPS
- [ ] Settings screen accessible; selection and location changes persist
- [ ] `boat-fishing-pro` shows lock overlay for non-Pro; tapping opens `ProPaywallView`
- [ ] `ProPaywallView` fetches StoreKit product and shows purchase button
- [ ] After successful purchase, `isPro` is true and lock overlay is gone
- [ ] Sign out → `.guest` state → all 5 activities visible, sign-in icon shown
