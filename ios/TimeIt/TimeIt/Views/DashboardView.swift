import SwiftUI
import UIKit

/// Root surface: gradient header → 0.5pt divider → scrollable card list.
/// Single NavigationStack, no tab bar, no sign-in gate (ADR-0001, grill Q8).
/// #5b: cards are the user's authored list (ActivityStore); a ghost add-card
/// opens the add flow; each card's gear opens the editor. #5c: with no
/// resolvable location, grayed skeleton cards + the two location CTAs — never
/// fabricated weather.
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @ObservedObject private var store: ActivityStore
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showCityPicker = false
    @State private var editing: AuthoredActivity?

    @MainActor
    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
        // Always the view model's store — mutations must hit the same list the
        // POST body is built from (two separately-defaulted stores diverge).
        _store = ObservedObject(wrappedValue: viewModel.store)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderView(locationName: viewModel.activeLocationName,
                           currentHour: viewModel.forecast?.hours.first,
                           showsWeather: !viewModel.hasNoLocation) { showSettings = true }
                Theme.divider
                    .frame(height: 0.5)
                content
            }
            .background(Theme.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAdd) {
                AddActivityView(store: store)
            }
            .sheet(isPresented: $showCityPicker) {
                // The VM's preferences, not .shared — the picker must write to
                // the same store the requests resolve from.
                CityPickerView(preferences: viewModel.preferences)
            }
            .sheet(item: $editing) { activity in
                NavigationStack {
                    ActivityEditorView(existing: activity,
                                       isNew: false,
                                       onSave: { store.update($0) },
                                       onDelete: { store.delete(id: activity.id) })
                }
            }
        }
        .task { await viewModel.loadForecast() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasActivities {
            emptyState
        } else if viewModel.hasNoLocation {
            noLocationState
        } else if viewModel.isLoading {
            ProgressView("Checking conditions…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = viewModel.errorMessage {
            errorView(message)
        } else if let forecast = viewModel.forecast {
            cardList(forecast)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// No activities → no POST (ADR-0005 requires a non-empty activities[]);
    /// the add-card stays as the way back in.
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 48)
                Text("No activities yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("Add an activity to get started")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityIdentifier("emptyStateMessage")
                addCard
                    .padding(.top, 12)
            }
            .padding(14)
        }
    }

    /// #5c no-location empty state: grayed skeleton cards (unrendered data —
    /// deliberately text-free so they can't be mistaken for weather) above the
    /// two CTAs. "Enable Location" prompts (or deep-links to system Settings
    /// after a denial); "Place your own location" opens the city picker.
    private var noLocationState: some View {
        ScrollView {
            VStack(spacing: 0) {
                skeletonCard(0)
                    .padding(.bottom, 10)
                skeletonCard(1)
                Image(systemName: "location.slash")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 32)
                Text("No location yet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 16)
                Text("Time It needs a location to rate your activities. Enable access or pick a city.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 6)
                    .accessibilityIdentifier("noLocationMessage")
                Button(action: enableLocation) {
                    Text("Enable Location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accentInteractive))
                }
                .buttonStyle(.plain)
                .padding(.top, 16)
                .accessibilityIdentifier("enableLocationButton")
                Button {
                    showCityPicker = true
                } label: {
                    Text("Place your own location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentInteractive)
                }
                .buttonStyle(.plain)
                .padding(.top, 18)
                .accessibilityIdentifier("placeLocationButton")
            }
            .padding(14)
        }
    }

    /// One grayed skeleton card: the real card's anatomy (title, day, track,
    /// chips) as flat shapes — no values, no false Perfect.
    private func skeletonCard(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 999)
                .fill(Theme.timelineTrack)
                .frame(width: 120, height: 14)
            RoundedRectangle(cornerRadius: 999)
                .fill(Theme.timelineTrack)
                .frame(width: 60, height: 10)
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.timelineTrack)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 999)
                        .fill(Theme.timelineTrack)
                        .frame(width: 48, height: 20)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
        .opacity(0.55)
        // Bare shapes aren't accessibility elements — collapse to one so the
        // identifier reaches the XCUI hierarchy.
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("skeletonCard.\(index)")
    }

    private func enableLocation() {
        if viewModel.locationPermissionDenied {
            // The prompt can only be shown once — after a denial the only
            // path is the app's page in system Settings.
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            viewModel.requestLocationAccess()
        }
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Weather Unavailable", systemImage: "wifi.slash")
        } description: {
            Text(message)
        } actions: {
            // Retrying is the primary recovery for a transient 502 / unreachable
            // server; it stays available (but not prominent) for a 500.
            Button("Try Again") {
                Task { await viewModel.loadForecast() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cardList(_ forecast: ForecastResponse) -> some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                // One card per returned activity, in request order (= store order).
                ForEach(forecast.activities) { activity in
                    ZStack(alignment: .topTrailing) {
                        NavigationLink {
                            ActivityDetailView(activity: activity,
                                               viewModel: viewModel,
                                               isNocturnal: viewModel.isNocturnal(activityId: activity.activityId))
                        } label: {
                            card(for: activity, in: forecast)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("card.\(activity.activityId)")
                        gearButton(for: activity)
                    }
                }
                addCard
                Spacer()
                    .frame(height: 12)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
        }
    }

    /// The card gear — opens the editor for this Activity (#5b §1).
    private func gearButton(for activity: ActivityRating) -> some View {
        Button {
            editing = viewModel.authoredActivity(forActivityId: activity.activityId)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Edit \(activity.label)")
        .accessibilityIdentifier("gear.\(activity.activityId)")
        .padding(.top, 6)
        .padding(.trailing, 8)
    }

    /// The ghost add-card (design-decisions §Interactions), after the card
    /// list. At the soft cap it flips to a friendly limit message (§8).
    private var addCard: some View {
        Button {
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                Text(store.isAtCap ? "Activity limit reached (\(ActivityStore.softCap))" : "Add Activity")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.1)
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.secondaryText.opacity(0.4),
                                  style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(store.isAtCap)
        .accessibilityIdentifier("addActivityCard")
    }

    private func card(for activity: ActivityRating, in forecast: ForecastResponse) -> ActivityCardView {
        let day = viewModel.cardDay(for: activity)
        return ActivityCardView(
            activity: activity,
            day: day,
            windowStartHour: day.flatMap { viewModel.windowStartHour(for: $0) },
            deriver: viewModel.timeDeriver,
            hoursCount: forecast.hours.count,
            iconSymbol: viewModel.iconSymbol(forActivityId: activity.activityId),
            isNocturnal: viewModel.isNocturnal(activityId: activity.activityId)
        )
    }
}
