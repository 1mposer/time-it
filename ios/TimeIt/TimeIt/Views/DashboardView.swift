import SwiftUI
import UIKit

/// Root surface: gradient header → divider → scrollable card list. One
/// NavigationStack, no tab bar, no sign-in gate (ADR-0001). Cards come from
/// the user's authored store; every dashboard state (first-launch hero,
/// no-location, error, dormant) always offers a next action — never a dead end.
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @ObservedObject private var store: ActivityStore
    @ObservedObject private var preferences: PreferencesStore
    /// The push opt-in service — drives the callout's visibility and is
    /// handed to the Settings sheet (one instance app-wide).
    @StateObject private var registration: DeviceRegistration
    @ObservedObject private var router: PushRouter
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showingCapAlert = false
    @State private var showCityPicker = false
    @State private var showFeedback = false
    @State private var editing: AuthoredActivity?
    /// Dev/TestFlight installs get the disclaimer banner + suggestion entry
    /// point on every dashboard state; App Store installs never do.
    private let isBetaBuild = BetaGate.isActive
    /// Value-based so a push tap can pop to the dashboard.
    @State private var navigationPath: [String] = []
    /// The card a tapped Perfect-window alert should bring into view —
    /// consumed by the card list's ScrollViewReader once it renders.
    @State private var pendingFocusId: String?

    /// Observes the view model's own store/preferences — separately-defaulted
    /// copies would silently diverge from the ones requests are built from.
    @MainActor
    init(viewModel: DashboardViewModel,
         registration: DeviceRegistration? = nil,
         router: PushRouter? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _store = ObservedObject(wrappedValue: viewModel.store)
        _preferences = ObservedObject(wrappedValue: viewModel.preferences)
        _registration = StateObject(wrappedValue: registration ?? DeviceRegistration.shared)
        _router = ObservedObject(wrappedValue: router ?? PushRouter.shared)
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // No live Activity → no fetch, nothing real to show: the
                // weather rows hide (matches the approved First Launch frame).
                HeaderView(locationName: viewModel.activeLocationName,
                           currentHour: viewModel.forecast?.hours.first,
                           showsWeather: !viewModel.hasNoLocation && viewModel.hasLiveActivities,
                           timezoneIdentifier: viewModel.forecast?.timezone) { showSettings = true }
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
            // "+" opens the wizard directly — the template chooser sheet is
            // gone (approved frame: First Launch, PROPOSED row).
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    ActivityEditorView(existing: .blank(),
                                       isNew: true,
                                       onSave: { activity in
                                           if !store.add(activity) {
                                               showingCapAlert = true
                                           }
                                       })
                }
            }
            .alert("Activity limit reached", isPresented: $showingCapAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can keep up to \(ActivityStore.softCap) activities. Delete one to add another.")
            }
            .sheet(isPresented: $showCityPicker) {
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
            .sheet(isPresented: $showFeedback) {
                FeedbackView(deviceId: registration.installId)
            }
            // One-time per chosen home (acknowledgement persists) — the
            // dashboard clock follows the home's zone, so a far-away home is
            // announced rather than silently re-clocking the header.
            .alert("Different time zone",
                   isPresented: Binding(
                       get: { viewModel.timezoneWarning != nil },
                       set: { if !$0 { viewModel.acknowledgeTimezoneWarning() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.timezoneWarning ?? "")
            }
        }
        .task {
            viewModel.requestInitialLocationPermissionIfNeeded()
            await viewModel.loadForecast()
        }
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

    /// Value-based detail destination — re-resolves from the live forecast.
    /// If the rating vanished (activity deleted, forecast dropped), pop home
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

    /// State ladder — a fetch-less state (empty store, all-dormant legacy
    /// store) outranks every fetch-driven state, including no-location.
    @ViewBuilder
    private var content: some View {
        if !viewModel.hasActivities {
            firstLaunchState
        } else if !viewModel.hasLiveActivities {
            dormantList
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

    /// First-launch / emptied-store state: the approved Add-Activity hero —
    /// one dashed card, and the wizard is the only path in.
    private var firstLaunchState: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isBetaBuild {
                    betaBanner
                        .padding(.bottom, 10)
                }
                Button {
                    showAdd = true
                } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 44))
                        Text("Add Activity")
                            .font(.system(size: 17, weight: .semibold))
                            .padding(.top, 14)
                        Text("Time It rates the week ahead for every activity you add.\nStart with your first one.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .accessibilityIdentifier("firstLaunchMessage")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 52)
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(HeroAddButtonStyle())
                .padding(.top, 84)
                .accessibilityIdentifier("addActivitiesButton")
            }
            .padding(14)
            .frame(maxWidth: .infinity)
        }
    }

    /// Legacy edge case (pre-template-removal installs): a stored Activity
    /// with no confirmed Range. Nothing rates and no request is made, so the
    /// list renders "Set your range →" cards with the ghost add-card after —
    /// never a dead end.
    private var dormantList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if isBetaBuild {
                    betaBanner
                }
                ForEach(store.activities) { authored in
                    dormantCard(for: authored)
                }
                addCard
                Spacer()
                    .frame(height: 12)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
        }
    }

    /// A dormant Activity's card: no weather, no timeline — the Range door
    /// (the editor) is the only way out of dormancy.
    private func dormantCard(for authored: AuthoredActivity) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ActivityIconView(identifier: authored.iconSymbol, size: 18)
                    .foregroundStyle(Theme.primaryText.opacity(0.75))
                    .accessibilityHidden(true)
                Text(authored.label)
                    .font(.system(size: 15, weight: .medium))
                    .tracking(-0.1)
                    .foregroundStyle(Theme.primaryText)
                Spacer()
            }
            Button {
                editing = authored
            } label: {
                HStack(spacing: 5) {
                    Text("Set your range")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.accentInteractive)
                .frame(minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("dormant.setRange.\(authored.id)")
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 10, trailing: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        // .contain creates a named CONTAINER — a bare identifier on the
        // stack would clobber the button's own XCUI identifier.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dormant.\(authored.id)")
    }

    /// No-location empty state: grayed skeleton cards above the two CTAs —
    /// "Enable Location" prompts (or deep-links to system Settings after a
    /// denial); "Place your own location" opens the city picker.
    private var noLocationState: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isBetaBuild {
                    betaBanner
                        .padding(.bottom, 10)
                }
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

    /// One grayed skeleton card: the real card's anatomy as flat shapes — no
    /// values. Collapsed to one accessibility element so its identifier is
    /// reachable in UI tests.
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
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("skeletonCard.\(index)")
    }

    /// After a denial the system prompt can't be shown again — deep-link to
    /// the app's page in system Settings instead.
    private func enableLocation() {
        if viewModel.locationPermissionDenied {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } else {
            viewModel.requestLocationAccess()
        }
    }

    /// Explicit Theme colors, not ContentUnavailableView — the system
    /// component rendered near-white text on the light background on device.
    private func errorView(_ message: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if isBetaBuild {
                    betaBanner
                }
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

    /// Iterates the store in store order (= request order): a live Activity
    /// renders its rated card from the echoed response; a dormant one renders
    /// its showcase card inline. The one-time push callout tops the list.
    private func cardList(_ forecast: ForecastResponse) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if !preferences.pushCalloutDismissed && !registration.isEnabled {
                        pushCallout
                    }
                    if isBetaBuild {
                        betaBanner
                    }
                    ForEach(store.activities) { authored in
                        Group {
                            if authored.isDormant {
                                dormantCard(for: authored)
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
                scrollToPendingFocus(pendingFocusId, proxy: proxy)
            }
        }
    }

    /// Scrolls the focused card into view; also runs onAppear for a cold
    /// launch where the push focus landed before the list existed.
    private func scrollToPendingFocus(_ activityId: String?, proxy: ScrollViewProxy) {
        guard let activityId else { return }
        withAnimation {
            proxy.scrollTo(activityId, anchor: .top)
        }
        pendingFocusId = nil
    }

    /// The beta disclaimer card: disclaimer copy plus the suggestion pill.
    /// (The ±9pt vertical padding pair on the pill keeps a 44pt tap target
    /// without growing the card.)
    private var betaBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            disclaimerText
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showFeedback = true
            } label: {
                Text("Send a suggestion")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 165, height: 26)
                    .background(Capsule().fill(Theme.accentInteractive))
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -9)
            .accessibilityIdentifier("betaBanner.suggest")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("betaBanner")
    }

    /// Base weight Light, "Time it" in Regular.
    private var disclaimerText: Text {
        Text("This is an early build for ").fontWeight(.light)
            + Text("Time it").fontWeight(.regular)
            + Text(", full release will be announced. Give me your suggestions").fontWeight(.light)
    }

    /// The push opt-in callout: bell + two-line invitation opening Settings;
    /// ✕ dismisses it for good. The headline's line break is hard-coded so
    /// "window" doesn't orphan onto the second line.
    private var pushCallout: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 10) {
                    calloutBell
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get a morning digest + Perfect window\nalerts")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 272, alignment: .leading)
                            .accessibilityLabel("Get a morning digest + Perfect window alerts")
                        Text("Turn on notifications")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accentInteractive)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("pushCallout.dismiss")
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
    }

    /// A periodic wiggle on iOS 18+ (18-only API); static on iOS 17 and
    /// whenever Reduce Motion is on.
    @ViewBuilder private var calloutBell: some View {
        let bell = Image(systemName: "bell.fill")
            .font(.system(size: 17))
            .foregroundStyle(Theme.accentInteractive)
        if #available(iOS 18.0, *) {
            if reduceMotion {
                bell
            } else {
                bell.symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2.0)))
            }
        } else {
            bell
        }
    }

    /// The card gear — opens the editor for this Activity.
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

    /// The ghost add-card: dashed border, after the card list. At the soft
    /// cap it dims with a limit message.
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

/// The hero card's press feedback (approved frame annotation): the blue
/// eases dark → light (#007AFF → #66B2FF) over ~0.15s while pressed.
private struct HeroAddButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let blue = configuration.isPressed ? Color(hex: 0x66b2ff) : Theme.accentInteractive
        configuration.label
            .foregroundStyle(blue)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(blue, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("Live cards") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
}

#Preview("Weather error") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(mode: .failure),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
}

#Preview("No location") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(home: nil),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
}

#Preview("First launch (empty)") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(activities: []),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
}
#endif
