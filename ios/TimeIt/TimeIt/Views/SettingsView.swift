import SwiftUI

/// Settings sheet: home location (as-you-type city picker), the push opt-in
/// Notifications toggle, the dashboard phrases toggle, About, and a location
/// note. Ships only live controls — no subscription/Pro row, no account
/// (cut, ADR-0001).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ObservedObject private var preferences: PreferencesStore
    @ObservedObject private var registration: DeviceRegistration
    private let geocoder: GeocodingProviding?

    @State private var showCityPicker = false

    @MainActor
    init(preferences: PreferencesStore? = nil,
         geocoder: GeocodingProviding? = nil,
         registration: DeviceRegistration? = nil) {
        _preferences = ObservedObject(wrappedValue: preferences ?? PreferencesStore.shared)
        _registration = ObservedObject(wrappedValue: registration ?? DeviceRegistration.shared)
        self.geocoder = geocoder
    }

    var body: some View {
        NavigationStack {
            List {
                homeLocationSection
                notificationsSection
                dashboardSection
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    Text("Time It rates the next 7 days for your outdoor activities from the local weather forecast.")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Section("Location") {
                    Label {
                        Text("Time It uses your home location when set, otherwise your device location. Without either, it shows the last place it rated — or asks you to pick one.")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "location.fill")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCityPicker, onDismiss: {
                // Backing out without a home abandons the pending opt-in —
                // the toggle must never lie ON.
                if preferences.homeLocation == nil {
                    registration.cancelPendingEnable()
                }
            }) {
                CityPickerView(preferences: preferences, geocoder: geocoder)
            }
            .onDisappear {
                // Leaving Settings mid-detour (prompt ignored, no home yet)
                // drops the pending opt-in; re-flip to retry.
                registration.cancelPendingEnable()
            }
        }
    }

    // MARK: notifications — the push opt-in toggle

    /// The real switch — no inert controls, shipped only with the push
    /// client. ON runs location-first, then the permission prompt, then APNs
    /// registration; the switch lands ON only when that flow completes. OFF
    /// deletes the device row.
    private var notificationsSection: some View {
        Section {
            Toggle(isOn: notificationsBinding) {
                Text("Notifications")
            }
            .accessibilityIdentifier("settings.notifications")
        } header: {
            Text("Notifications")
        } footer: {
            Text("A morning digest plus Perfect-window alerts for your activities.")
        }
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { registration.isEnabled },
            set: { wantsOn in
                if wantsOn {
                    Task { await enableNotifications() }
                } else {
                    Task { await registration.disable() }
                }
            }
        )
    }

    @MainActor
    private func enableNotifications() async {
        switch await registration.requestEnable() {
        case .enabled, .authorizationDenied:
            // Denied: switch stays off, matching iOS Settings convention;
            // re-flipping re-prompts (or no-ops once determined).
            break
        case .needsLocation:
            if registration.canPromptForLocationAccess {
                // Grant → fix → the pending opt-in auto-continues.
                registration.promptForLocationAccess()
            } else {
                // Authorized-but-fixless also warms a fix — whichever
                // resolves first, GPS or a picked city, continues.
                registration.warmLocationFixIfAuthorized()
                showCityPicker = true
            }
        }
    }

    // MARK: dashboard — the phrases toggle

    /// Default OFF — cards carry quality in color alone. When Differentiate
    /// Without Color is on, phrases force-enable and the row reads on +
    /// locked (color is never the only carrier).
    private var dashboardSection: some View {
        Section {
            Toggle(isOn: differentiateWithoutColor ? .constant(true) : $preferences.showPhrases) {
                HStack(spacing: 6) {
                    Text("Show phrases")
                    if differentiateWithoutColor {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Locked on")
                    }
                }
            }
            .disabled(differentiateWithoutColor)
            .accessibilityIdentifier("settings.showPhrases")
        } header: {
            Text("Dashboard")
        } footer: {
            if differentiateWithoutColor {
                Text("On — required while Differentiate Without Color is active.")
            } else {
                Text("Adds a one-line summary under each card — \u{201C}Good, turning perfect.\u{201D} Turns on automatically when Differentiate Without Color is enabled.")
            }
        }
    }

    // MARK: home location

    private var homeLocationSection: some View {
        Section {
            HStack {
                Text("Home")
                Spacer()
                Text(preferences.homeLocation?.name ?? "Using current location")
                    .foregroundStyle(.secondary)
            }
            Button {
                showCityPicker = true
            } label: {
                Label("Set home location", systemImage: "mappin.and.ellipse")
            }
            .accessibilityIdentifier("settings.setHome")
            if preferences.homeLocation != nil {
                Button("Use current location") {
                    preferences.homeLocation = nil
                }
                .accessibilityIdentifier("settings.useCurrentLocation")
            }
        } header: {
            Text("Home location")
        } footer: {
            Text("Forecasts use your home location when set; clear it to follow your device location again.")
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

#if DEBUG
#Preview("Settings") {
    let preferences = PreviewFixtures.preferences()
    SettingsView(preferences: preferences,
                 geocoder: PreviewFixtures.CannedGeocoder(),
                 registration: PreviewFixtures.registration(preferences: preferences))
}
#endif
