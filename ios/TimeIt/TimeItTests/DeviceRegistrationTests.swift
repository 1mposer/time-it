import XCTest
import CoreLocation
@testable import TimeIt

// MARK: - Fakes

final class FakeKeychain: KeychainStoring {
    private(set) var storage: [String: String] = [:]
    private(set) var writeCount = 0

    func read(key: String) -> String? {
        storage[key]
    }

    func write(key: String, value: String) {
        storage[key] = value
        writeCount += 1
    }
}

final class FakeDevicesAPI: DeviceSnapshotSending {
    private(set) var puts: [(deviceId: String, body: DeviceSnapshotBody)] = []
    private(set) var deletes: [String] = []
    /// Arrival order across both routes — pins request serialization.
    private(set) var log: [String] = []
    var putError: Error?
    var deleteError: Error?
    /// Simulates a slow in-flight PUT (the disable-race window).
    var putDelayNanoseconds: UInt64 = 0

    func putSnapshot(deviceId: String, body: DeviceSnapshotBody) async throws {
        if putDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: putDelayNanoseconds)
        }
        if let putError { throw putError }
        puts.append((deviceId, body))
        log.append("put")
    }

    func deleteDevice(deviceId: String) async throws {
        if let deleteError { throw deleteError }
        deletes.append(deviceId)
        log.append("delete")
    }
}

final class FakePushAuthorizer: NotificationAuthorizing {
    var grants = true
    private(set) var requestCount = 0

    func requestAuthorization() async -> Bool {
        requestCount += 1
        return grants
    }
}

// MARK: - Tests

/// The push-client spec §2 service: Keychain install UUID, full-snapshot
/// upsert (dormant exclusion, nocturnal passthrough, home-else-GPS — never
/// the last-resolved cache), re-upsert triggers gated on the toggle, DELETE
/// on opt-out with the Keychain ID retained.
@MainActor
final class DeviceRegistrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!
    private var preferences: PreferencesStore!
    private var store: ActivityStore!
    private var keychain: FakeKeychain!
    private var api: FakeDevicesAPI!
    private var authorizer: FakePushAuthorizer!
    private var location: FakeLocationProvider!
    private var registerCalls = 0
    private var nowDate = Date(timeIntervalSince1970: 1_755_400_000)

    override func setUp() {
        super.setUp()
        suiteName = "DeviceRegistrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        preferences = PreferencesStore(defaults: defaults)
        keychain = FakeKeychain()
        api = FakeDevicesAPI()
        authorizer = FakePushAuthorizer()
        location = FakeLocationProvider()
        registerCalls = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: fixtures — one live, one dormant, one nocturnal (spec 14 §1)

    private func liveCycling() -> AuthoredActivity {
        AuthoredActivity(id: "cycling", label: "Cycling", iconSymbol: "bicycle",
                         templateOrigin: nil, displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(min: 15, max: 35, required: true)],
                         window: WindowSpec(startHour: 6, endHour: 10))
    }

    private func dormantRunning() -> AuthoredActivity {
        AuthoredActivity(id: "running", label: "Running", iconSymbol: "figure.run",
                         templateOrigin: nil, displayMetrics: ["temp"],
                         thresholds: ["temp": Threshold(max: 30, required: true)],
                         window: nil)
    }

    private func nocturnalStargazing() -> AuthoredActivity {
        AuthoredActivity(id: "stargazing", label: "Stargazing", iconSymbol: "sparkles",
                         templateOrigin: nil, displayMetrics: ["temp", "cloudCover"],
                         thresholds: ["cloudCover": Threshold(max: 20, required: true)],
                         window: WindowSpec(startHour: 22, endHour: 4))
    }

    private func seedStore(_ seeds: [AuthoredActivity]? = nil) {
        store = ActivityStore(defaults: defaults,
                              seeds: seeds ?? [liveCycling(), dormantRunning(), nocturnalStargazing()],
                              preferences: preferences)
    }

    private func makeRegistration(enabled: Bool = true) -> DeviceRegistration {
        if store == nil { seedStore() }
        if enabled {
            defaults.set(true, forKey: DeviceRegistration.enabledKey)
        }
        return DeviceRegistration(api: api,
                                  keychain: keychain,
                                  store: store,
                                  preferences: preferences,
                                  locationProvider: location,
                                  authorizer: authorizer,
                                  registerForRemoteNotifications: { [weak self] in self?.registerCalls += 1 },
                                  defaults: defaults,
                                  now: { [nowDate] in nowDate })
    }

    // MARK: Keychain seam (ADR-0001)

    func testMintsInstallIdOnceAndPersistsItToTheKeychain() {
        let registration = makeRegistration()

        XCTAssertFalse(registration.installId.isEmpty)
        XCTAssertEqual(keychain.storage[DeviceRegistration.installIdKey], registration.installId)
        XCTAssertEqual(keychain.writeCount, 1)
    }

    func testSecondInstanceReusesTheKeychainInstallId() {
        let first = makeRegistration()
        let second = makeRegistration()

        XCTAssertEqual(second.installId, first.installId)
        XCTAssertEqual(keychain.writeCount, 1, "the id is minted exactly once")
    }

    // MARK: snapshot body (spec §2)

    func testTokenReceiptUpsertsFullSnapshotExcludingDormantWithNocturnalPassthrough() async {
        preferences.homeLocation = SavedLocation(name: "Dubai Marina", lat: 25.08, lon: 55.14)
        let registration = makeRegistration()

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1)
        let put = api.puts[0]
        XCTAssertEqual(put.deviceId, registration.installId)
        XCTAssertEqual(put.body.apnsToken, "aabbcc00")
        XCTAssertEqual(put.body.home, DeviceSnapshotBody.Home(lat: 25.08, lon: 55.14))
        XCTAssertEqual(put.body.activities.map(\.id), ["cycling", "stargazing"],
                       "the dormant Activity is excluded, exactly as from the rating POST")
        XCTAssertEqual(put.body.activities.last?.window, WindowSpec(startHour: 22, endHour: 4),
                       "the authored nocturnal wrap goes over the wire — the jobs read it for tonight copy")
    }

    func testSnapshotUsesGpsFixWhenNoHomeIsSet() async {
        location.location = CLLocation(latitude: 25.2048, longitude: 55.2708)
        let registration = makeRegistration()

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1)
        XCTAssertEqual(api.puts[0].body.home, DeviceSnapshotBody.Home(lat: 25.2048, lon: 55.2708))
    }

    func testSnapshotNeverFallsBackToTheLastResolvedCache() async {
        preferences.lastResolvedLocation = SavedLocation(name: "Cached", lat: 1, lon: 2)
        let registration = makeRegistration()

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertTrue(api.puts.isEmpty,
                      "ADR-0006: no fallback-location push — without home or GPS there is no upsert")
    }

    func testTokenReceiptWhileDisabledSendsNothing() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: false)

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertTrue(api.puts.isEmpty)
    }

    // MARK: re-upsert triggers (spec §2 — only while the toggle is on)

    func testStoreMutationReUpsertsTheSnapshot() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        var padel = liveCycling()
        padel = AuthoredActivity(id: "padel", label: "Padel", iconSymbol: "tennis.racket",
                                 templateOrigin: nil, displayMetrics: padel.displayMetrics,
                                 thresholds: padel.thresholds, window: padel.window)
        store.add(padel)
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 2)
        XCTAssertEqual(api.puts.last?.body.activities.map(\.id), ["cycling", "stargazing", "padel"])
    }

    func testHomeLocationChangeReUpsertsTheSnapshot() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        preferences.homeLocation = SavedLocation(name: "Abu Dhabi", lat: 24.45, lon: 54.38)
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 2)
        XCTAssertEqual(api.puts.last?.body.home, DeviceSnapshotBody.Home(lat: 24.45, lon: 54.38))
    }

    func testTokenRefreshReUpsertsWithTheNewToken() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        registration.updateAPNsToken("ddeeff11")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 2)
        XCTAssertEqual(api.puts.last?.body.apnsToken, "ddeeff11")
    }

    func testUnchangedTokenReceiptDoesNotReUpsertWhenFresh() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1,
                       "every launch re-registers; an unchanged fresh token must not spam the server")
    }

    func testStoreMutationWhileDisabledSendsNothing() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: false)

        // A token in hand must not change the answer — the toggle alone gates.
        registration.updateAPNsToken("aabbcc00")
        store.add(AuthoredActivity(id: "padel", label: "Padel", iconSymbol: "tennis.racket",
                                   templateOrigin: nil, displayMetrics: ["temp"],
                                   thresholds: [:], window: WindowSpec(startHour: 6, endHour: 9)))
        await registration.awaitPendingOperations()

        XCTAssertTrue(api.puts.isEmpty)
    }

    func testDisableSerializesBehindAnInFlightUpsert() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: true)
        api.putDelayNanoseconds = 100_000_000

        registration.updateAPNsToken("aabbcc00")
        // Let the scheduled upsert pass its guard and reach the (slow) PUT —
        // the race is a request already in flight when the toggle flips off.
        await Task.yield()
        await registration.disable()

        XCTAssertEqual(api.log, ["put", "delete"],
                       "a slow PUT landing after the DELETE would resurrect the opted-out row")
        XCTAssertNil(defaults.string(forKey: DeviceRegistration.lastSentTokenKey),
                     "the in-flight PUT's bookkeeping must not survive the opt-out")
    }

    func testAuthorizedButFixlessEnableWarmsAFixAndCompletesWhenItLands() async {
        location.authorizationStatus = .authorizedWhenInUse
        let registration = makeRegistration(enabled: false)

        let outcome = await registration.requestEnable()
        XCTAssertEqual(outcome, .needsLocation)

        registration.warmLocationFixIfAuthorized()
        XCTAssertTrue(location.requestLocationCalled,
                      "already-authorized-but-fixless warms a fix (the #5c CTA rule)")

        location.location = CLLocation(latitude: 25.2, longitude: 55.3)
        await registration.awaitPendingOperations()
        XCTAssertTrue(registration.isEnabled, "the landed fix completes the pending opt-in")
    }

    func testDeletingTheLastLiveActivityUpsertsAnEmptySnapshot() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        seedStore([liveCycling()])
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        store.delete(id: "cycling")
        await registration.awaitPendingOperations()

        XCTAssertGreaterThan(api.puts.count, 1)
        XCTAssertEqual(api.puts.last?.body.activities.count, 0,
                       "a dormant registration keeps the server copy fresh rather than stale")
    }

    func testFailedUpsertRetriesOnTheNextTrigger() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        api.putError = APIError.providerUnavailable
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()
        XCTAssertTrue(api.puts.isEmpty)

        api.putError = nil
        preferences.homeLocation = SavedLocation(name: "Moved", lat: 24, lon: 54)
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1, "no bespoke queue — the next trigger is the retry")
    }

    // MARK: opt-out (spec §1)

    func testDisableDeletesTheDeviceRowAndKeepsTheKeychainId() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration()
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        await registration.disable()

        XCTAssertEqual(api.deletes, [registration.installId])
        XCTAssertFalse(registration.isEnabled)
        XCTAssertEqual(keychain.storage[DeviceRegistration.installIdKey], registration.installId,
                       "opt-out keeps the Keychain ID — re-enabling reuses the same device row")

        store.add(AuthoredActivity(id: "padel", label: "Padel", iconSymbol: "tennis.racket",
                                   templateOrigin: nil, displayMetrics: ["temp"],
                                   thresholds: [:], window: WindowSpec(startHour: 6, endHour: 9)))
        await registration.awaitPendingOperations()
        XCTAssertEqual(api.puts.count, 1, "no re-upserts after opt-out")
    }

    // MARK: opt-in flow (spec §1 — toggle ON)

    func testRequestEnableWithRealLocationAndGrantRegistersAndEnables() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: false)

        let outcome = await registration.requestEnable()

        XCTAssertEqual(outcome, .enabled)
        XCTAssertEqual(authorizer.requestCount, 1)
        XCTAssertEqual(registerCalls, 1)
        XCTAssertTrue(registration.isEnabled)
        XCTAssertTrue(defaults.bool(forKey: DeviceRegistration.enabledKey),
                      "the opt-in survives relaunch")

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()
        XCTAssertEqual(api.puts.count, 1, "the token receipt completes the registration")
    }

    func testRequestEnableDeniedStaysDisabled() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        authorizer.grants = false
        let registration = makeRegistration(enabled: false)

        let outcome = await registration.requestEnable()

        XCTAssertEqual(outcome, .authorizationDenied)
        XCTAssertEqual(registerCalls, 0)
        XCTAssertFalse(registration.isEnabled)
    }

    func testRequestEnableWithoutRealLocationNeedsLocationAndDoesNotPrompt() async {
        preferences.lastResolvedLocation = SavedLocation(name: "Cached", lat: 1, lon: 2)
        let registration = makeRegistration(enabled: false)

        let outcome = await registration.requestEnable()

        XCTAssertEqual(outcome, .needsLocation)
        XCTAssertEqual(authorizer.requestCount, 0,
                       "the #5c onboarding comes FIRST — no permission prompt without a location")
        XCTAssertFalse(registration.isEnabled)
    }

    func testPendingEnableCompletesWhenAHomeIsPicked() async {
        let registration = makeRegistration(enabled: false)
        _ = await registration.requestEnable()

        preferences.homeLocation = SavedLocation(name: "Picked", lat: 25, lon: 55)
        await registration.awaitPendingOperations()

        XCTAssertTrue(registration.isEnabled,
                      "the city-picker save completes the pending opt-in")
        XCTAssertEqual(registerCalls, 1)
    }

    func testPendingEnableCompletesWhenAGpsFixLands() async {
        let registration = makeRegistration(enabled: false)
        _ = await registration.requestEnable()

        location.location = CLLocation(latitude: 25.2, longitude: 55.3)
        await registration.awaitPendingOperations()

        XCTAssertTrue(registration.isEnabled,
                      "granting location completes the pending opt-in")
    }

    func testCancelPendingEnableStopsTheContinuation() async {
        let registration = makeRegistration(enabled: false)
        _ = await registration.requestEnable()

        registration.cancelPendingEnable()
        preferences.homeLocation = SavedLocation(name: "Picked", lat: 25, lon: 55)
        await registration.awaitPendingOperations()

        XCTAssertFalse(registration.isEnabled,
                       "dismissing the picker without saving abandons the opt-in")
    }

    func testReEnableAfterDisableUpsertsEvenWithUnchangedFreshToken() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: true)
        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()
        await registration.disable()

        _ = await registration.requestEnable()
        // The token is already in hand, so re-enable upserts immediately —
        // recreating the row must not wait on APNs re-delivering the token.
        await registration.awaitPendingOperations()
        XCTAssertEqual(api.puts.count, 2,
                       "re-enabling must recreate the deleted row even when nothing else changed")

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()
        XCTAssertEqual(api.puts.count, 2,
                       "the later unchanged-token receipt dedupes against the re-enable upsert")
    }

    // MARK: app launch (spec §2 — token refresh + launch-if-stale)

    func testAppDidLaunchWhileEnabledReRegistersForRemoteNotifications() {
        let registration = makeRegistration(enabled: true)
        registration.appDidLaunch()
        XCTAssertEqual(registerCalls, 1)
    }

    func testAppDidLaunchWhileDisabledDoesNotRegister() {
        let registration = makeRegistration(enabled: false)
        registration.appDidLaunch()
        XCTAssertEqual(registerCalls, 0)
    }

    func testStaleUnchangedTokenReceiptReUpserts() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        defaults.set("aabbcc00", forKey: DeviceRegistration.lastSentTokenKey)
        defaults.set(nowDate.addingTimeInterval(-25 * 60 * 60),
                     forKey: DeviceRegistration.lastUpsertAtKey)
        let registration = makeRegistration(enabled: true)

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1, "app-launch-if-stale: a day-old snapshot refreshes")
    }

    func testMutationBeforeTokenReceiptUpsertsOnceTheTokenArrives() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        defaults.set("aabbcc00", forKey: DeviceRegistration.lastSentTokenKey)
        defaults.set(nowDate, forKey: DeviceRegistration.lastUpsertAtKey)
        let registration = makeRegistration(enabled: true)

        store.add(AuthoredActivity(id: "padel", label: "Padel", iconSymbol: "tennis.racket",
                                   templateOrigin: nil, displayMetrics: ["temp"],
                                   thresholds: [:], window: WindowSpec(startHour: 6, endHour: 9)))
        await registration.awaitPendingOperations()
        XCTAssertTrue(api.puts.isEmpty, "no token yet — nothing to send")

        registration.updateAPNsToken("aabbcc00")
        await registration.awaitPendingOperations()

        XCTAssertEqual(api.puts.count, 1,
                       "the launch-time edit must not be lost to the fresh-token dedupe")
        XCTAssertEqual(api.puts.last?.body.activities.map(\.id), ["cycling", "stargazing", "padel"])
    }

    func testFailedDeleteRetriesOnNextLaunch() async {
        preferences.homeLocation = SavedLocation(name: "Home", lat: 25, lon: 55)
        let registration = makeRegistration(enabled: true)
        api.deleteError = APIError.providerUnavailable
        await registration.disable()
        XCTAssertTrue(api.deletes.isEmpty)

        api.deleteError = nil
        let relaunched = makeRegistration(enabled: false)
        relaunched.appDidLaunch()
        await relaunched.awaitPendingOperations()

        XCTAssertEqual(api.deletes, [registration.installId],
                       "an opted-out user must not keep receiving pushes")
        XCTAssertFalse(defaults.bool(forKey: DeviceRegistration.pendingDeleteKey))
    }
}
