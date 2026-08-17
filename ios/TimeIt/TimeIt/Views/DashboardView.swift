import SwiftUI
import UIKit

/// Root surface: gradient header → 0.5pt divider → scrollable card list.
/// Single NavigationStack, no tab bar, no sign-in gate (ADR-0001, grill Q8).
/// #5b: cards are the user's authored list (ActivityStore); a ghost add-card
/// opens the add flow; each card's gear opens the editor. #5c: with no
/// resolvable location, grayed skeleton cards + the two location CTAs — never
/// fabricated weather. Spec 14: dormant Activities render as showcase cards
/// (an all-dormant dashboard makes no network call — the first-launch state);
/// an all-dismissed empty store renders the true-empty Add CTA. The dashboard
/// always offers a next action — never a dead end (§6).
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @ObservedObject private var store: ActivityStore
    @ObservedObject private var preferences: PreferencesStore
    /// The push opt-in service — drives the callout's visibility and is
    /// handed to the Settings sheet (one instance app-wide, like the store).
    @StateObject private var registration: DeviceRegistration
    @ObservedObject private var router: PushRouter
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showCityPicker = false
    @State private var editing: AuthoredActivity?
    /// Value-based so a push tap can pop to the dashboard (spec §3).
    @State private var navigationPath: [String] = []
    /// The card a tapped Perfect-window alert should bring into view —
    /// consumed by the card list's ScrollViewReader once it renders.
    @State private var pendingFocusId: String?

    @MainActor
    init(viewModel: DashboardViewModel,
         registration: DeviceRegistration? = nil,
         router: PushRouter? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        // Always the view model's store — mutations must hit the same list the
        // POST body is built from (two separately-defaulted stores diverge).
        _store = ObservedObject(wrappedValue: viewModel.store)
        // Same rule for preferences: the phrases toggle must re-render the
        // SAME store the Settings sheet writes to.
        _preferences = ObservedObject(wrappedValue: viewModel.preferences)
        _registration = StateObject(wrappedValue: registration ?? DeviceRegistration.shared)
        _router = ObservedObject(wrappedValue: router ?? PushRouter.shared)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // I2 (all-dormant header state) — PROPOSED, FLAGGED FOR OWNER
                // REVIEW: with nothing live there is no fetch (spec 14 §1), so
                // the weather rows HIDE (like the no-location state) instead of
                // dangling "—" placeholders that imply data is coming. The
                // approved Empty—Showcase frame shows values here — a static-
                // frame compromise code can't honor without a network call.
                HeaderView(locationName: viewModel.activeLocationName,
                           currentHour: viewModel.forecast?.hours.first,
                           showsWeather: !viewModel.hasNoLocation && viewModel.hasLiveActivities) { showSettings = true }
                Theme.divider
                    .frame(height: 0.5)
                content
            }
            .background(Theme.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { activityId in
                detailDestination(for: activityId)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(registration: registration)
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
        // Spec §3: a Perfect-window alert tap lands on the dashboard with the
        // named card visible — dismiss whatever covers it, pop the stack,
        // and queue the scroll for when the card list is on screen.
        .onReceive(router.$focusActivityId.compactMap { $0 }) { activityId in
            showSettings = false
            showAdd = false
            showCityPicker = false
            editing = nil
            navigationPath = []
            pendingFocusId = activityId
            router.focusActivityId = nil
        }
    }

    /// Value-based detail destination — re-resolves from the live forecast,
    /// same as the detail view itself does across refetches. If the rating
    /// vanished under us (activity deleted, forecast dropped), pop home
    /// rather than strand the user on a blank screen.
    @ViewBuilder
    private func detailDestination(for activityId: String) -> some View {
        if let activity = viewModel.rating(forActivityId: activityId) {
            ActivityDetailView(activity: activity,
                               viewModel: viewModel,
                               isNocturnal: viewModel.isNocturnal(activityId: activityId))
        } else {
            Color.clear
                .onAppear { navigationPath = [] }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasActivities {
            trueEmptyState
        } else if !viewModel.hasLiveActivities {
            // All-dormant (first launch, or delete-all re-seed): the showcase.
            // No network call was made, so this outranks every fetch-driven
            // state — including no-location, which becomes relevant only once
            // a confirmed range makes a fetch worth attempting.
            showcaseList
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

    /// Spec 14 §6 true-empty state (Figma 266:1651): every template dismissed
    /// AND the last Activity deleted — the store is genuinely empty, so the
    /// showcase cannot re-seed. The Add CTA is the standing next action.
    private var trueEmptyState: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 96)
                Text("No activities")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 16)
                Text("You've dismissed every starter template. Add your own and Time It will rate the week ahead.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 6)
                    .accessibilityIdentifier("trueEmptyMessage")
                Button {
                    showAdd = true
                } label: {
                    Text("Add activities +")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accentInteractive))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .accessibilityIdentifier("addActivitiesButton")
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    /// The all-dormant showcase (Figma Empty—Showcase 111:32): every stored
    /// Activity as a "Set your range →" card, ghost add-card after.
    private var showcaseList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(store.activities) { authored in
                    showcaseCard(for: authored)
                }
                addCard
                Spacer()
                    .frame(height: 12)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
        }
    }

    private func showcaseCard(for authored: AuthoredActivity) -> some View {
        ShowcaseCardView(activity: authored,
                         onSetRange: { editing = authored },
                         onDismiss: { store.dismissTemplate(id: authored.id) })
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
                if viewModel.locationPermissionRestricted {
                    // Parental controls / MDM: the user cannot flip the
                    // switch, so a prompt or a Settings deep-link is a dead
                    // end (audit F5) — say so instead of pretending.
                    Text("Location access is restricted on this device.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, 16)
                        .accessibilityIdentifier("locationRestrictedMessage")
                } else {
                    Button(action: enableLocation) {
                        Text("Enable Location")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(Theme.accentInteractive))
                            // 44pt touch target (Guidelines.md) without
                            // growing the 33pt visual capsule.
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .accessibilityIdentifier("enableLocationButton")
                }
                Button {
                    showCityPicker = true
                } label: {
                    Text("Place your own location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentInteractive)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 5)
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

    /// Explicit Theme colors, not ContentUnavailableView — the system
    /// component rendered near-white text on the light background on device.
    /// Mirrors the Figma Error frame's empty-state idiom (same anatomy as
    /// noLocationState).
    private func errorView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 96)
                Text("Weather Unavailable")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                    .padding(.top, 16)
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                    .padding(.top, 6)
                // Retrying is the primary recovery for a transient 502 /
                // unreachable server; it stays available for a 500 too.
                Button {
                    Task { await viewModel.loadForecast() }
                } label: {
                    Text("Try Again")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accentInteractive))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    /// The card list iterates the STORE (spec 14 §1: dormant Activities are
    /// stored and visible), in store order = request order: a live Activity
    /// renders its rated card from the echoed response entry; a dormant one
    /// renders its showcase card inline. The one-time push callout (spec §1,
    /// Figma 266:5) tops the list until dismissed or notifications are on.
    private func cardList(_ forecast: ForecastResponse) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !preferences.pushCalloutDismissed && !registration.isEnabled {
                        pushCallout
                    }
                    ForEach(store.activities) { authored in
                        Group {
                            if authored.isDormant {
                                showcaseCard(for: authored)
                            } else if let activity = viewModel.rating(forActivityId: authored.id) {
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink(value: activity.activityId) {
                                        card(for: activity, authored: authored, in: forecast)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("card.\(activity.activityId)")
                                    gearButton(for: activity)
                                }
                            }
                        }
                        .id(authored.id)
                    }
                    addCard
                    Spacer()
                        .frame(height: 12)
                }
                .padding(.top, 14)
                .padding(.horizontal, 14)
            }
            .onChange(of: pendingFocusId) { _, activityId in
                scrollToPendingFocus(activityId, proxy: proxy)
            }
            .onAppear {
                // Cold launch from a push: the focus landed before the list
                // existed — consume it now.
                scrollToPendingFocus(pendingFocusId, proxy: proxy)
            }
        }
    }

    private func scrollToPendingFocus(_ activityId: String?, proxy: ScrollViewProxy) {
        guard let activityId else { return }
        withAnimation {
            proxy.scrollTo(activityId, anchor: .top)
        }
        pendingFocusId = nil
    }

    /// The push opt-in callout (Figma 266:125): bell + two-line invitation
    /// deep-linking to Settings' Notifications row, ✕ dismissing for good.
    private var pushCallout: some View {
        HStack(spacing: 0) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accentInteractive)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get a morning digest + Perfect-window alerts")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.primaryText)
                        Text("Turn on notifications")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accentInteractive)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pushCallout")
            Button {
                preferences.pushCalloutDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("pushCallout.dismiss")
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
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

    /// The ghost add-card (Figma 104:270): dashed separator border, blue
    /// invitation, after the card list. At the soft cap it dims to secondary
    /// with a friendly limit message (§8).
    private var addCard: some View {
        Button {
            showAdd = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                Text(store.isAtCap ? "Activity limit reached (\(ActivityStore.softCap))" : "Add Activity")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(-0.1)
            }
            .foregroundStyle(store.isAtCap ? Theme.secondaryText : Theme.accentInteractive)
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.divider,
                                  style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(store.isAtCap)
        .accessibilityIdentifier("addActivityCard")
    }

    private func card(for activity: ActivityRating, authored: AuthoredActivity, in forecast: ForecastResponse) -> ActivityCardView {
        let day = viewModel.cardDay(for: activity)
        let tiers = viewModel.rangeTiers(for: authored, dayIndex: 0)
        return ActivityCardView(
            activity: activity,
            day: day,
            windowStartHour: day.flatMap { viewModel.windowStartHour(for: $0) },
            deriver: viewModel.timeDeriver,
            hoursCount: forecast.hours.count,
            iconSymbol: authored.iconSymbol,
            isNocturnal: authored.isNocturnal,
            rangeChipLabel: authored.window.map(RangeText.chipLabel),
            sliceRange: viewModel.rangeHourIndices(for: authored, dayIndex: 0),
            tiers: tiers,
            phrase: TrajectoryPhrase.cardPhrase(
                dayRated: day != nil,
                tiers: tiers,
                phrasesEnabled: TrajectoryPhrase.phrasesEnabled(preference: preferences.showPhrases,
                                                                differentiateWithoutColor: differentiateWithoutColor))
        )
    }
}
