import Combine
import CoreLocation
import Foundation
import UIKit
import UserNotifications

// MARK: - Seams

/// Keychain seam (ADR-0001): the install UUID lives in the Keychain so it
/// survives reinstall — string-value generic passwords, nothing else.
protocol KeychainStoring {
    func read(key: String) -> String?
    func write(key: String, value: String)
}

/// Devices-route seam (`PUT`/`DELETE /api/v1/devices/:deviceId`, ADR-0006).
protocol DeviceSnapshotSending {
    func putSnapshot(deviceId: String, body: DeviceSnapshotBody) async throws
    func deleteDevice(deviceId: String) async throws
}

/// UNUserNotificationCenter seam — the permission prompt.
protocol NotificationAuthorizing {
    func requestAuthorization() async -> Bool
}

/// The real prompt. Alerts only — no badges, no sounds beyond the default.
struct SystemNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// Body of the full-snapshot upsert (#6c) — client-authoritative,
/// last-write-wins; re-sent whole on any change.
struct DeviceSnapshotBody: Encodable, Equatable {
    struct Home: Encodable, Equatable {
        let lat: Double
        let lon: Double
    }

    let apnsToken: String
    let home: Home
    let activities: [ActivityInput]
}

// MARK: - Service

/// The push-client registration service (push-client spec §2): mints/reads
/// the Keychain install UUID, projects the persisted ActivityStore to the
/// device snapshot (dormant excluded, exactly as from the rating POST), and
/// keeps the server copy fresh via the spec's re-upsert triggers — all gated
/// on the Settings toggle. Failures retry on the next trigger; no queue.
@MainActor
final class DeviceRegistration: ObservableObject {

    static let shared = DeviceRegistration()

    /// Keychain key for the install UUID (ADR-0001 — survives reinstall).
    static let installIdKey = "deviceInstallId"
    static let enabledKey = "pushNotificationsEnabled"
    static let lastSentTokenKey = "pushLastSentToken"
    static let lastUpsertAtKey = "pushLastUpsertAt"
    static let pendingDeleteKey = "pushPendingDelete"
    /// App-launch-if-stale threshold (spec §2): an unchanged token re-upserts
    /// only when the last successful upsert is older than this.
    static let staleInterval: TimeInterval = 24 * 60 * 60

    /// The Settings toggle's truth: the user's opt-in, persisted. Flips on
    /// only when the permission flow completes; flipping off is immediate.
    @Published private(set) var isEnabled: Bool

    let installId: String

    private let api: DeviceSnapshotSending
    private let keychain: KeychainStoring
    private let store: ActivityStore
    private let preferences: PreferencesStore
    private let locationProvider: LocationProviding
    private let authorizer: NotificationAuthorizing
    private let registerForRemoteNotifications: () -> Void
    private let defaults: UserDefaults
    private let now: () -> Date
    private var cancellables: Set<AnyCancellable> = []

    /// The latest APNs token as delivered to the AppDelegate — hex, in
    /// memory only (it re-arrives on every launch's re-register).
    private var apnsToken: String?
    /// A trigger fired before the first token arrived — upsert on receipt
    /// even when the token itself is unchanged and fresh.
    private var upsertQueuedForToken = false
    /// In-flight sync work, keyed so completed handles clean themselves up;
    /// disable() drains it to serialize the DELETE behind any live PUT.
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]

    init(api: DeviceSnapshotSending? = nil,
         keychain: KeychainStoring? = nil,
         store: ActivityStore? = nil,
         preferences: PreferencesStore? = nil,
         locationProvider: LocationProviding? = nil,
         authorizer: NotificationAuthorizing? = nil,
         registerForRemoteNotifications: (() -> Void)? = nil,
         defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init) {
        // Resolved here, not as default arguments — the shared singletons are
        // main-actor-isolated and default arguments evaluate in the caller's
        // context (same rule as DashboardViewModel's dependencies).
        self.api = api ?? DevicesClient.shared
        self.keychain = keychain ?? KeychainStore()
        self.store = store ?? ActivityStore.shared
        self.preferences = preferences ?? PreferencesStore.shared
        self.locationProvider = locationProvider ?? LocationManager.shared
        self.authorizer = authorizer ?? SystemNotificationAuthorizer()
        self.registerForRemoteNotifications = registerForRemoteNotifications
            ?? { UIApplication.shared.registerForRemoteNotifications() }
        self.defaults = defaults
        self.now = now
        isEnabled = defaults.bool(forKey: Self.enabledKey)

        if let existing = self.keychain.read(key: Self.installIdKey) {
            installId = existing
        } else {
            let minted = UUID().uuidString
            self.keychain.write(key: Self.installIdKey, value: minted)
            installId = minted
        }

        // The re-upsert triggers (spec §2), gated on the toggle inside
        // snapshotDidChange: any ActivityStore mutation, a home change.
        // dropFirst skips the seed/initial publish. A home pick while an
        // opt-in is pending on location completes that opt-in instead.
        self.store.$activities
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] _ in self?.snapshotDidChange() }
            .store(in: &cancellables)
        self.preferences.$homeLocation
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] home in
                guard let self else { return }
                if self.isEnablePending, home != nil {
                    self.continuePendingEnable()
                } else {
                    self.snapshotDidChange()
                }
            }
            .store(in: &cancellables)
        // GPS serves ONLY the pending opt-in — a moving fix is deliberately
        // not a re-upsert trigger (spec §2 names four; drift isn't one).
        self.locationProvider.locationPublisher
            .dropFirst()
            .compactMap { $0 }
            .sink { [weak self] _ in
                guard let self, self.isEnablePending else { return }
                self.continuePendingEnable()
            }
            .store(in: &cancellables)
        // A grant while pending warms a fix (same dedupe rationale as the
        // DashboardViewModel's authorization sink).
        self.locationProvider.authorizationPublisher
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] status in
                guard let self, self.isEnablePending,
                      status == .authorizedWhenInUse || status == .authorizedAlways else { return }
                self.locationProvider.requestLocation()
            }
            .store(in: &cancellables)
    }

    // MARK: token receipt (AppDelegate → here)

    /// The APNs token, hex-encoded by the AppDelegate. Registration happens
    /// on every launch while enabled, so an unchanged fresh token is deduped
    /// — but a stale one re-upserts (the app-launch-if-stale trigger).
    func updateAPNsToken(_ hexToken: String) {
        apnsToken = hexToken
        guard isEnabled else { return }
        let lastSent = defaults.string(forKey: Self.lastSentTokenKey)
        if upsertQueuedForToken || hexToken != lastSent || isStale {
            scheduleUpsert()
        }
    }

    // MARK: re-upsert triggers

    private func snapshotDidChange() {
        guard isEnabled else { return }
        guard apnsToken != nil else {
            // Launch-time edit before the token re-arrived: don't lose it —
            // the receipt upserts even an unchanged fresh token.
            upsertQueuedForToken = true
            return
        }
        scheduleUpsert()
    }

    private var isStale: Bool {
        guard let last = defaults.object(forKey: Self.lastUpsertAtKey) as? Date else { return true }
        return now().timeIntervalSince(last) > Self.staleInterval
    }

    /// Runs an async operation as tracked work (see `pendingTasks`).
    private func track(_ operation: @escaping () async -> Void) {
        let id = UUID()
        pendingTasks[id] = Task {
            await operation()
            self.pendingTasks[id] = nil
        }
    }

    private func scheduleUpsert() {
        track { await self.upsert() }
    }

    /// The full-snapshot PUT — body computed at send time (last-write-wins).
    /// Location: home, else the live GPS fix — NEVER the last-resolved cache
    /// and never a fallback constant (ADR-0006: no fallback-location push);
    /// with neither, skip — the next trigger retries.
    private func upsert() async {
        guard isEnabled, let token = apnsToken, let home = snapshotHome() else { return }
        let body = DeviceSnapshotBody(apnsToken: token,
                                      home: home,
                                      activities: liveActivityInputs())
        do {
            try await api.putSnapshot(deviceId: installId, body: body)
            upsertQueuedForToken = false
            defaults.set(token, forKey: Self.lastSentTokenKey)
            defaults.set(now(), forKey: Self.lastUpsertAtKey)
        } catch {
            // Failures retry on the next trigger (spec §2) — no bespoke queue.
        }
    }

    private func snapshotHome() -> DeviceSnapshotBody.Home? {
        if let home = preferences.homeLocation {
            return DeviceSnapshotBody.Home(lat: home.lat, lon: home.lon)
        }
        if let fix = locationProvider.location {
            return DeviceSnapshotBody.Home(lat: fix.coordinate.latitude,
                                           lon: fix.coordinate.longitude)
        }
        return nil
    }

    /// Spec 14 §1: a dormant Activity is excluded from the snapshot exactly
    /// as it is excluded from the rating POST. Deleting the last live one
    /// legitimately sends [] — a valid dormant registration.
    private func liveActivityInputs() -> [ActivityInput] {
        store.activities.filter { !$0.isDormant }.map(\.activityInput)
    }

    // MARK: opt-out (spec §1)

    /// Toggle OFF: delete the device row, keep the Keychain ID (re-enabling
    /// reuses the same row). A failed DELETE is remembered and retried at
    /// next launch — an opted-out user must not keep receiving pushes.
    func disable() async {
        isEnabled = false
        cancelPendingEnable()
        defaults.set(false, forKey: Self.enabledKey)
        // Serialize behind any in-flight PUT: one landing after the DELETE
        // would silently resurrect the opted-out row (and its success path
        // re-writes the dedupe keys, so clear them only after the drain).
        await awaitPendingOperations()
        defaults.removeObject(forKey: Self.lastSentTokenKey)
        defaults.removeObject(forKey: Self.lastUpsertAtKey)
        do {
            try await api.deleteDevice(deviceId: installId)
            defaults.set(false, forKey: Self.pendingDeleteKey)
        } catch {
            defaults.set(true, forKey: Self.pendingDeleteKey)
        }
    }

    // MARK: opt-in flow (spec §1 — toggle ON)

    enum EnableOutcome {
        case enabled
        case needsLocation
        case authorizationDenied
    }

    /// True between a `.needsLocation` outcome and its resolution: the next
    /// real location (picked home or GPS fix) auto-continues the opt-in.
    private(set) var isEnablePending = false

    /// Toggle ON. Ordering is the spec's: real location FIRST (the #5c
    /// onboarding routes here — no permission prompt without somewhere to
    /// rate), then the notification permission, then APNs registration.
    func requestEnable() async -> EnableOutcome {
        guard snapshotHome() != nil else {
            isEnablePending = true
            return .needsLocation
        }
        isEnablePending = false
        guard await authorizer.requestAuthorization() else {
            return .authorizationDenied
        }
        isEnabled = true
        defaults.set(true, forKey: Self.enabledKey)
        // A successful re-enable cancels a pending opt-out DELETE — retrying
        // it at next launch would destroy the row this flow recreates (and
        // the fresh-token dedupe would hide the outage for ~24h).
        defaults.set(false, forKey: Self.pendingDeleteKey)
        // Force the next token receipt to upsert — a re-enable must recreate
        // the deleted row even when the token is unchanged and fresh.
        defaults.removeObject(forKey: Self.lastSentTokenKey)
        registerForRemoteNotifications()
        if apnsToken != nil {
            scheduleUpsert()
        }
        return .enabled
    }

    /// The view calls this when the user abandons the location step (e.g.
    /// dismisses the city picker without saving) — the opt-in is dropped.
    func cancelPendingEnable() {
        isEnablePending = false
    }

    /// The `.needsLocation` doors, mirrored from the #5c empty state: a
    /// not-yet-asked GPS gets the system prompt (the toggle is the CTA —
    /// prompts stay CTA-gated); anything else routes to the city picker.
    var canPromptForLocationAccess: Bool {
        locationProvider.authorizationStatus == .notDetermined
    }

    func promptForLocationAccess() {
        locationProvider.requestAuthorization()
    }

    /// Authorized but fixless (the third #5c door): warm a fix — when it
    /// lands, the pending opt-in auto-continues. Mirrors the dashboard CTA's
    /// requestLocationAccess; never prompts.
    func warmLocationFixIfAuthorized() {
        let status = locationProvider.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        locationProvider.requestLocation()
    }

    private func continuePendingEnable() {
        isEnablePending = false
        track { _ = await self.requestEnable() }
    }

    // MARK: app launch

    /// Called from the AppDelegate: retry a failed opt-out delete, and while
    /// enabled re-register so a rotated APNs token re-upserts (the receipt
    /// dedupes an unchanged fresh one; staleness forces a daily refresh).
    func appDidLaunch() {
        // The retry belongs to an opted-OUT install only — while enabled, a
        // (stale) pending flag must never outrank the live registration.
        if !isEnabled, defaults.bool(forKey: Self.pendingDeleteKey) {
            track {
                do {
                    try await self.api.deleteDevice(deviceId: self.installId)
                    self.defaults.set(false, forKey: Self.pendingDeleteKey)
                } catch {
                    // Still pending — retried again next launch.
                }
            }
        }
        guard isEnabled else { return }
        registerForRemoteNotifications()
    }

    // MARK: draining

    /// Awaits every in-flight sync task — disable() drains before its DELETE,
    /// and tests drain for determinism. Concurrent PUTs are unordered on the
    /// wire (bodies are computed at send time, so any interleaving converges
    /// on the next trigger — last-write-wins is the route's contract).
    func awaitPendingOperations() async {
        while !pendingTasks.isEmpty {
            let tasks = Array(pendingTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }
}
