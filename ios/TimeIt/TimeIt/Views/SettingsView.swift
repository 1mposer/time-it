import SwiftUI

/// Settings sheet (grill Q9: ship only live controls). Home location (#5b §5,
/// upgraded to the #5c as-you-type city picker) + the spec 14 §5 dashboard
/// phrases toggle + About + a location note — no subscription/Pro row
/// (deferred §8), no account (cut, ADR-0001). The NOTIFICATIONS row on the
/// approved Settings frame ships with the push opt-in client (ROADMAP item 7),
/// not this wave.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ObservedObject private var preferences: PreferencesStore
    private let geocoder: GeocodingProviding?

    @State private var showCityPicker = false

    @MainActor
    init(preferences: PreferencesStore? = nil, geocoder: GeocodingProviding? = nil) {
        _preferences = ObservedObject(wrappedValue: preferences ?? PreferencesStore.shared)
        self.geocoder = geocoder
    }

    var body: some View {
        NavigationStack {
            List {
                homeLocationSection
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
            .sheet(isPresented: $showCityPicker) {
                CityPickerView(preferences: preferences, geocoder: geocoder)
            }
        }
    }

    // MARK: dashboard — the spec 14 §5 phrases toggle

    /// Default OFF: the card carries quality in color alone. When the
    /// system's Differentiate Without Color is on, phrases force-enable and
    /// the row reads on + locked (§5 accessibility force — color is never
    /// the only carrier).
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
