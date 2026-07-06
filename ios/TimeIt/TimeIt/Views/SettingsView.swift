import SwiftUI

/// Thin settings stub (grill Q9: ship only live controls). About + a location
/// note only — no subscription/Pro row (#5b), no notifications (#6c), no account (cut).
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
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
                        Text("Time It uses your location to fetch a local forecast. Without access it falls back to Dubai.")
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}
