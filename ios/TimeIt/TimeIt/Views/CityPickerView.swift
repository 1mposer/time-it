import SwiftUI

/// #5c city-picker sheet: worldwide as-you-type search over the
/// GeocodingProviding seam (MKLocalSearch-backed in production, mock in UI
/// tests). Picking a result saves it as the home location — the same store
/// #5b built and #6c later reads for push registration. Reachable from the
/// dashboard's no-location CTA and from Settings.
struct CityPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var preferences: PreferencesStore
    private let geocoder: GeocodingProviding

    @State private var query = ""
    @State private var results: [SavedLocation] = []
    /// Search ran and genuinely found nothing.
    @State private var searchFailed = false
    /// The geocoder threw (connectivity, throttling) — a different message
    /// than "no results", which would send the user retyping in vain.
    @State private var searchErrored = false

    @MainActor
    init(preferences: PreferencesStore? = nil, geocoder: GeocodingProviding? = nil) {
        _preferences = ObservedObject(wrappedValue: preferences ?? PreferencesStore.shared)
        self.geocoder = geocoder ?? GeocoderFactory.makeDefault()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.secondaryText)
                        TextField("Search for a city", text: $query)
                            .font(.system(size: 15))
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("cityPicker.search")
                    }
                    if searchFailed {
                        Text("No places found — try a different search.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    if searchErrored {
                        Text("Search failed — check your connection and try again.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { index, place in
                        Button {
                            preferences.homeLocation = place
                            dismiss()
                        } label: {
                            HStack {
                                Text(place.name)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.primaryText)
                                Spacer()
                                if let region = place.region {
                                    Text(region)
                                        .font(.system(size: 15))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                        .accessibilityIdentifier("cityPicker.result.\(index)")
                    }
                } footer: {
                    Text("Results update as you type. Choosing a city saves it as your home location.")
                }
            }
            .navigationTitle("Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cityPicker.cancel")
                }
            }
            .task(id: query) { await search() }
        }
    }

    /// Debounced as-you-type: `.task(id: query)` cancels the previous run on
    /// every keystroke, so only a 300 ms pause reaches the geocoder.
    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            searchFailed = false
            searchErrored = false
            return
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        do {
            let found = try await geocoder.geocode(trimmed)
            guard !Task.isCancelled else { return }
            results = found
            searchFailed = found.isEmpty
            searchErrored = false
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            searchFailed = false
            searchErrored = true
        }
    }
}
