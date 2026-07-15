import SwiftUI

/// Settings sheet (grill Q9: ship only live controls). Home location (#5b §5)
/// + About + a location note — no subscription/Pro row (deferred §8), no
/// notifications (#6c), no account (cut, ADR-0001).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences: PreferencesStore
    private let geocoder: GeocodingProviding

    @State private var query = ""
    @State private var results: [SavedLocation] = []
    @State private var isSearching = false
    @State private var searchFailed = false

    @MainActor
    init(preferences: PreferencesStore? = nil, geocoder: GeocodingProviding? = nil) {
        _preferences = ObservedObject(wrappedValue: preferences ?? PreferencesStore.shared)
        self.geocoder = geocoder ?? Self.defaultGeocoder()
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
                        Text("Time It uses your home location when set, otherwise your device location. Without either it falls back to Dubai.")
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
            TextField("Search city or place", text: $query)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings.locationSearch")
                .onSubmit { search() }
            Button("Search") { search() }
                .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                .accessibilityIdentifier("settings.searchButton")
            if searchFailed {
                Text("No places found — try a different search.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(results.enumerated()), id: \.offset) { index, place in
                Button {
                    preferences.homeLocation = place
                    results = []
                    query = ""
                } label: {
                    Label(place.name, systemImage: "mappin.and.ellipse")
                }
                .accessibilityIdentifier("settings.result.\(index)")
            }
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

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isSearching else { return }
        isSearching = true
        searchFailed = false
        Task {
            defer { isSearching = false }
            do {
                let found = try await geocoder.geocode(trimmed)
                results = found
                searchFailed = found.isEmpty
            } catch {
                results = []
                searchFailed = true
            }
        }
    }

    /// UI tests inject a hermetic geocoder via the mock launch args; everyone
    /// else geocodes for real.
    private static func defaultGeocoder() -> GeocodingProviding {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_MOCK_SUCCESS") || arguments.contains("UITEST_MOCK_FAILURE") {
            return MockGeocoderService()
        }
        #endif
        return CLGeocoderService()
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
