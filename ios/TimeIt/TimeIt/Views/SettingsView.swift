import SwiftUI

/// Settings sheet (grill Q9: ship only live controls). Home location (#5b §5,
/// upgraded to the #5c as-you-type city picker) + About + a location note —
/// no subscription/Pro row (deferred §8), no notifications (#6c), no account
/// (cut, ADR-0001).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
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
