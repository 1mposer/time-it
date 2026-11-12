import SwiftUI
import UIKit

/// Root surface: pinned header over the band melt → scrollable card list. One
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openingInProgress) private var openingInProgress
    @Environment(\.scenePhase) private var scenePhase
    /// What is on screen — the header toggle switches to its opposite.
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false
    @State private var showAdd = false
    @State private var showingCapAlert = false
    @State private var showCityPicker = false
    /// The open feedback sheet's kind (the ⓘ menu row picked); nil = closed.
    @State private var feedbackKind: FeedbackKind?
    @State private var editing: AuthoredActivity?
    /// The card whose long-press Delete is awaiting confirmation.
    @State private var pendingDelete: AuthoredActivity?
    /// Dev/TestFlight installs get the ⓘ feedback menu (disclaimer line +
    /// both feedback sheets) on every dashboard state; App Store installs
    /// never do (owner ruling 2026-11-11: beta-only, moves to Settings at
    /// release).
    private let isBetaBuild = BetaGate.isActive
    /// Value-based so a push tap can pop to the dashboard.
    @State private var navigationPath: [DetailRoute] = []
    /// The card a tapped Perfect-window alert should bring into view —
    /// consumed by the card list's ScrollViewReader once it renders.
    @State private var pendingFocusId: String?
    /// The card list's live top overscroll (pull-down stagger) and its
    /// viewport height (the rubber band's ceiling).
    @State private var pullOverscroll: CGFloat = 0
    @State private var listViewport: CGFloat = 700
    /// The pinned header's bottom edge in full-screen space — the melt's
    /// anchor (the first list item rests `firstItemInset` below it).
    @State private var headerBottom: CGFloat = 215
    /// The screen's top safe-area inset — eye level is measured below it.
    @State private var safeTop: CGFloat = 0
    /// The push callout's slot height (full card or resting bell) — the
    /// first card sits one slot + gap below it.
    @State private var calloutSlotHeight: CGFloat = 0

    /// The first list item's resting top below the header, per state — the
    /// melt's anchor. The card and dormant lists put the first Activity card
    /// at eye level (`DashboardLayout`); the first-launch hero's top is its
    /// capsule's eye level less the hero's own padding above the capsule.
    private var firstItemInset: CGFloat {
        if !viewModel.hasActivities {
            return Theme.Spacing.lg + firstLaunchHeroTop
        }
        return listTopInset
    }

    /// The card / dormant list's top padding: the first Activity card at eye
    /// level, never closer to the header than `Spacing.listBelowHeader`.
    private var listTopInset: CGFloat {
        DashboardLayout.listTopInset(headerBottom: headerBottom, safeTop: safeTop,
                                     leadingHeight: showsCallout ? calloutSlotHeight + Theme.Spacing.cardGap : 0)
    }

    /// The Add-Activity hero's top padding: its capsule's glass top lands at
    /// eye level — the same line the first card rests on once one exists
    /// (owner, build 10 POLISH item 2). 84 on a default-size 17 Pro, the
    /// approved First Launch frame's value.
    private var firstLaunchHeroTop: CGFloat {
        DashboardLayout.firstLaunchHeroTop(headerBottom: headerBottom, safeTop: safeTop)
    }

    private var showsCallout: Bool {
        !preferences.pushCalloutDismissed && !registration.isEnabled
    }

    /// The appearance on screen right now (the stored choice once applied;
    /// the trait under a UI-test pin).
    private var showingAppearance: AppAppearance {
        colorScheme == .dark ? .dark : .light
    }

    private var showsHeaderWeather: Bool {
        !viewModel.hasNoLocation && viewModel.hasLiveActivities
    }

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
                           showsWeather: showsHeaderWeather,
                           timezoneIdentifier: viewModel.forecast?.timezone,
                           windUnit: preferences.windSpeedUnit,
                           appearance: showingAppearance,
                           onAppearanceTap: { preferences.toggleAppearance(showing: showingAppearance) }) {
                    showSettings = true
                }
                // The forecast's age (lane CACHE, owner rule 4): the
                // dashboard may be drawn from the 3 h cache, so it says when
                // the data was fetched. An overlay, so the header's measured
                // bottom (where the list and melt begin) is unchanged.
                .overlay(alignment: .bottomLeading) {
                    if let updated = viewModel.updatedLabel {
                        // Bottom-left, and a tap refetches (owner, 2026-11-12):
                        // the same full refetch as a pull — a fresh cache is
                        // bypassed and the card list stays mounted.
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            // Reads on the gradient like the location line
                            // (morning page ruling 04, stronger) and shows
                            // its refresh glyph so the tap is discoverable.
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                    .accessibilityHidden(true)
                                Text(updated)
                                    .scaledFont(size: 12, weight: .medium)
                            }
                            .foregroundStyle(Theme.onGradient.opacity(0.85))
                            .padding(.leading, 16)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Stays inside the header's 22pt bottom padding
                        // so it never runs over the meta line (note 36).
                        .dynamicTypeSize(...Self.updatedLabelTypeCap)
                        .accessibilityIdentifier("forecastUpdated")
                        .accessibilityHint("Refreshes the forecast")
                    }
                }
                // Note 36 (tester record): at the accessibility sizes the
                // hero ate ~half the screen. The header is chrome, so its
                // words stop growing at xxxLarge — the cards below keep the
                // full Dynamic Type range (owner, build 10 POLISH item 6).
                .dynamicTypeSize(...Self.headerTypeCap)
                // The header is pinned (outside every ScrollView) — its
                // bottom edge is where each state's list begins.
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: {
                    if $0 != headerBottom { headerBottom = $0 }
                }
                content
                    // Beta only: the ⓘ menu floats bottom-leading in the
                    // safe-area inset, so every list scrolls under it and its
                    // end (the Add Activity capsule) always clears it.
                    .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 0) {
                        if isBetaBuild {
                            feedbackMenu
                                .padding(.leading, Self.feedbackMenuInset)
                                .padding(.bottom, 4)
                        }
                    }
            }
            // The band + melt + glow blob, full-screen behind the header
            // text and the list (Final – Opus v1). A background of the whole
            // dashboard, not of the ScrollView content, so the list scrolls
            // over it and pull-to-refresh / the stagger are untouched. The
            // melt starts at the first list item's resting top
            // (`firstItemInset` below the header — a resting value, never a
            // live frame, so the melt holds still under a pull).
            .background {
                BandMeltView(firstCardTop: headerBottom + firstItemInset,
                             temp: HeaderView.bandTemp(currentHour: viewModel.forecast?.hours.first,
                                                       showsWeather: showsHeaderWeather))
                    .ignoresSafeArea()
            }
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: {
                if $0 != safeTop { safeTop = $0 }
            }
            #if DEBUG
            // XCUI only: the mock's fetch count (the pull-to-refresh test).
            .overlay(alignment: .bottomLeading) {
                if ProcessInfo.processInfo.isUITestMockRun { UITestFetchCountProbe() }
            }
            #endif
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: DetailRoute.self) { route in
                detailDestination(for: route)
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
                                       isFirstActivity: store.activities.isEmpty,
                                       windUnit: preferences.windSpeedUnit,
                                       onSave: { activity in
                                           if !store.add(activity) {
                                               showingCapAlert = true
                                           }
                                       },
                                       reviewPreview: { await viewModel.reviewPreview(for: $0) },
                                       rangeHasPassedToday: { viewModel.rangeHasPassedToday($0) })
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
                                       windUnit: preferences.windSpeedUnit,
                                       onSave: { store.update($0) },
                                       onDelete: { store.delete(id: activity.id) },
                                       reviewPreview: { await viewModel.reviewPreview(for: $0) },
                                       rangeHasPassedToday: { viewModel.rangeHasPassedToday($0) })
                }
            }
            .sheet(item: $feedbackKind) { kind in
                FeedbackView(kind: kind, deviceId: registration.installId)
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
            // Seeds the stored appearance from the system on first launch,
            // then owns the window override (inert under a UI-test pin).
            AppearanceController.shared.attachForCurrentProcess()
            await viewModel.loadForecast()
        }
        // The first-run location prompt waits for the opening sequence to
        // hand over (owner ruling 2026-11-11, Q16) — the system alert must
        // not land on the logo. The fetch above runs underneath it.
        .onChange(of: openingInProgress, initial: true) { _, inProgress in
            if !inProgress { viewModel.requestInitialLocationPermissionIfNeeded() }
        }
        // Re-entering the foreground reloads through the forecast cache
        // (lane CACHE): a forecast under 3 h old for this location is served
        // without a POST, an older one is refetched. Launch is covered by
        // .task; the generation guard makes an overlapping load harmless.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await viewModel.loadForecast() }
        }
        .onReceive(router.$focusActivityId.compactMap { $0 }) { activityId in
            showSettings = false
            feedbackKind = nil
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
    private func detailDestination(for route: DetailRoute) -> some View {
        if let activity = viewModel.rating(forActivityId: route.activityId) {
            ActivityDetailView(activity: activity,
                               viewModel: viewModel,
                               windUnit: preferences.windSpeedUnit,
                               now: viewModel.now,
                               initialDayIndex: route.dayIndex,
                               onActivityDeleted: { navigationPath = [] })
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
    /// the glass Add Activity capsule over its invitation copy, and the
    /// wizard is the only path in.
    private var firstLaunchState: some View {
        ScrollView {
            VStack(spacing: 0) {
                // The glass Add Activity capsule (owner ruling 2026-11-04)
                // replaces the dashed hero card, centred in the space the
                // card's glyph + title used; the invitation copy stays below.
                VStack(spacing: 0) {
                    addActivityCapsule(identifier: "addActivitiesButton")
                    Text("Time It checks weather conditions\nfor any activity you create.\n\nStart with your first one.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 16)
                        .accessibilityIdentifier("firstLaunchMessage")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, DashboardLayout.firstLaunchHeroPadding)
                .padding(.top, firstLaunchHeroTop)
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
            LazyVStack(spacing: Theme.Spacing.cardGap) {
                ForEach(store.activities) { authored in
                    dormantCard(for: authored)
                }
                addCard
                Spacer()
                    .frame(height: 12)
            }
            .padding(.top, listTopInset)
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
                .foregroundStyle(Theme.accentBrand)
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
        .cardLift(cornerRadius: 16, light: .rest)
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
                // One per authored Activity, named (note 13).
                VStack(spacing: 10) {
                    ForEach(viewModel.noLocationPlaceholders) { activity in
                        skeletonCard(for: activity)
                    }
                }
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
                    GlassControl(identifier: "enableLocationButton", action: enableLocation) {
                        Text("Enable Location")
                            .glassCapsule(font: GlassCapsule.primaryFont)
                    }
                    .padding(.top, 8)
                }
                Button {
                    showCityPicker = true
                } label: {
                    Text("Place your own location")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accentBrand)
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

    /// One grayed skeleton card per authored Activity: its icon and name
    /// (so the user sees what was saved — note 13) over the real card's
    /// anatomy as flat shapes, no values. Collapsed to one accessibility
    /// element named for the Activity.
    private func skeletonCard(for activity: AuthoredActivity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ActivityIconView(identifier: activity.iconSymbol)
                Text(activity.label)
                    .scaledFont(size: 17, weight: .semibold)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
            }
            Group {
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
            .opacity(0.55)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground.opacity(0.55)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(activity.label)
        .accessibilityIdentifier("skeletonCard.\(activity.id)")
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
                GlassControl(identifier: "tryAgainButton") {
                    Task { await viewModel.loadForecast() }
                } label: {
                    Text("Try Again")
                        .glassCapsule(font: GlassCapsule.primaryFont)
                }
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
        // Visual order for the pull-down stagger: callout, cards, add card —
        // every child moves, so no child slides over the next.
        let leading = showsCallout ? 1 : 0
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.cardGap) {
                    if showsCallout {
                        // Full callout on first sight; after its ✕ it rests
                        // as the glass bell, and the bell reveals it again,
                        // every time (owner rulings 2026-11-11). Both share
                        // one top-leading slot, so the bell never moves.
                        ZStack(alignment: .topLeading) {
                            if preferences.pushCalloutResting {
                                calloutBellChip
                                    .transition(.opacity)
                            } else {
                                pushCallout
                                    .transition(.wipe(reduceMotion: reduceMotion))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Its resting height sets how far above eye level
                        // the list starts, so the first card stays put.
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            if $0 != calloutSlotHeight { calloutSlotHeight = $0 }
                        }
                        // "Don't show again" (or turning notifications on)
                        // removes the slot itself.
                        .transition(.deReveal(anchor: .topLeading, reduceMotion: reduceMotion))
                        .offset(y: staggerOffset(at: 0))
                            // Above its siblings, so the cards sliding up
                            // pass behind the shrinking callout, not over it.
                            .zIndex(1)
                    }
                    ForEach(Array(store.activities.enumerated()), id: \.element.id) { position, authored in
                        Group {
                            if authored.isDormant {
                                dormantCard(for: authored)
                            } else if let activity = viewModel.rating(forActivityId: authored.id) {
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink(value: DetailRoute(activityId: activity.activityId)) {
                                        // A minute tick (deferral 5, card half —
                                        // the detail hero's twin, `aa3a28e`):
                                        // passed strip hours grey on the minute.
                                        // A re-render trigger only — the card
                                        // reads `viewModel.now()`, never the
                                        // timeline's date (the UI-test clock pin).
                                        TimelineView(.everyMinute) { _ in
                                            card(for: activity, authored: authored)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    // Long-press → the system context menu
                                    // (owner ruling 2026-11-11, superseding
                                    // the 2026-10-06 "no long press"); a
                                    // plain tap still opens the detail.
                                    .cardContextMenu(menuActions(for: authored))
                                    .accessibilityIdentifier("card.\(activity.activityId)")
                                    // Outside the NavigationLink, so it never
                                    // pushes the detail. The card gear is gone
                                    // (owner ruling 2026-10-06 #2): a tap on
                                    // the card opens the detail, whose circles
                                    // are the edit doors. The chevron is a
                                    // plain inline control, not glass chrome.
                                    chevronButton(for: authored)
                                    // Centres the 34pt chevron on the frame's
                                    // glyph (`458:394` Chevron x336–351,
                                    // y13–29 → centre 343.5, 21 on a 365 card).
                                    .padding(.top, 4)
                                    .padding(.trailing, 4.5)
                                }
                            }
                        }
                        .offset(y: staggerOffset(at: leading + position))
                        .id(authored.id)
                    }
                    addCard
                        .offset(y: staggerOffset(at: leading + store.activities.count))
                    Spacer()
                        .frame(height: 12)
                }
                .padding(.top, listTopInset)
                .padding(.horizontal, 14)
                // The top overscroll: the padded content's top in the scroll
                // view's space rests at 0 and goes positive when pulled past
                // the top. Clamped and deduplicated, so normal scrolling never
                // writes state (iOS 17 + 18 — one reader for both).
                .onGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.frame(in: .scrollView).minY)
                } action: { value in
                    if value != pullOverscroll { pullOverscroll = value }
                }
            }
            // Pull-to-refresh over the same overscroll the stagger reads,
            // firing only past `PullRefresh.threshold` (owner report
            // 2026-11-05: the system control fired too early); `refresh()`
            // keeps the list mounted.
            .pullToRefresh(overscroll: pullOverscroll) { await viewModel.refresh() }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listViewport = $0 }
            // The card menu's Delete confirms first, in the editor's words.
            .confirmationDialog(ActivityDeletionCopy.title,
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible,
                                presenting: pendingDelete) { activity in
                Button(ActivityDeletionCopy.confirm, role: .destructive) {
                    withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) {
                        store.delete(id: activity.id)
                    }
                }
                .accessibilityIdentifier("card.confirmDelete")
            }
            .onChange(of: pendingFocusId) { _, activityId in
                scrollToPendingFocus(activityId, proxy: proxy)
            }
            .onAppear {
                scrollToPendingFocus(pendingFocusId, proxy: proxy)
            }
        }
    }

    /// The card menu's actions. Reorder and delete only mutate the store —
    /// the forecast follows through the cache with no POST (lane CACHE's
    /// rule); never `loadForecast()` from here.
    private func menuActions(for authored: AuthoredActivity) -> CardMenuActions {
        let id = authored.id
        let motion = Theme.Motion.reveal(reduceMotion: reduceMotion)
        return CardMenuActions(
            viewDetails: { navigationPath.append(DetailRoute(activityId: id)) },
            moveUp: store.canMove(id: id, by: -1)
                ? { withAnimation(motion) { store.move(id: id, by: -1) } } : nil,
            moveDown: store.canMove(id: id, by: 1)
                ? { withAnimation(motion) { store.move(id: id, by: 1) } } : nil,
            delete: { pendingDelete = authored })
    }

    /// The pull-down stagger's extra offset for the child at visual position
    /// `index` — tracks the overscroll 1:1 (no animation); off under Reduce
    /// Motion. The math lives in `PullStagger`.
    private func staggerOffset(at index: Int) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return PullStagger.offset(overscroll: pullOverscroll, index: index, viewport: listViewport)
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

    /// The ⓘ button's leading inset (the round-2 frames: 16pt).
    static let feedbackMenuInset: CGFloat = 16

    /// The beta disclaimer — the ⓘ menu's header line (owner ruling
    /// 2026-11-11: the banner's words fold into the menu).
    static let betaDisclaimer = "Early test build. Full release to be announced."

    /// The beta ⓘ: a 44pt glass circle opening a system `Menu` — the first
    /// tap only opens it, and a scroll never fires it (the structural guard
    /// against a stray thumb). Each row opens its own feedback sheet.
    private var feedbackMenu: some View {
        GlassGroup(spacing: 0) {
            Menu {
                Section(Self.betaDisclaimer) {
                    ForEach(FeedbackKind.allCases) { kind in
                        Button {
                            feedbackKind = kind
                        } label: {
                            Label(kind.menuTitle, systemImage: kind.symbol)
                        }
                    }
                }
            } label: {
                Image(systemName: "info")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accentBrand)
                    .frame(width: GlassCapsule.height, height: GlassCapsule.height)
                    .glassPieceSurface(in: Circle(), enabled: true, fallback: .material)
                    .contentShape(Circle())
            }
            .accessibilityLabel("Feedback")
            .accessibilityIdentifier("feedbackInfo")
        }
    }

    /// The full push opt-in callout (the approved round-3 card): bell + the
    /// two-line invitation, the whole card opening Settings; ✕ folds it back
    /// into the resting bell. The bell sits in a 44pt top-leading column —
    /// the same spot the resting chip occupies — so it is the fixed origin of
    /// the wipe (ruling Q16a: level with line one). The headline's line break
    /// is hard-coded so "window" doesn't orphan onto the second line.
    private var pushCallout: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                showSettings = true
            } label: {
                HStack(alignment: .top, spacing: 0) {
                    calloutBell
                        .frame(width: Self.bellSlot, height: Self.bellSlot)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Get a morning digest + Perfect window\nalerts")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 272, alignment: .leading)
                            .accessibilityLabel(Self.calloutCopy)
                        Text("Turn on notifications")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accentBrand)
                    }
                    .padding(.vertical, 10)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pushCallout")
            Button {
                // Folds back to the bell on the reveal spring; the list
                // follows on the same spring.
                withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) {
                    preferences.pushCalloutResting = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("pushCallout.dismiss")
        }
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.cardBackground))
    }

    /// The callout's copy, read in full by VoiceOver from the resting bell too.
    private static let calloutCopy = "Get a morning digest + Perfect window alerts"

    /// The bell's slot: the resting chip's diameter and the card's bell column.
    private static let bellSlot: CGFloat = 44

    /// The resting callout: a 44pt Liquid Glass bell. Tap reveals the full
    /// callout, every time; long-press offers "Don't show again" (long-press
    /// only, no swipe — owner ruling 2026-11-11).
    private var calloutBellChip: some View {
        GlassControl(identifier: "pushCallout.bell",
                     accessibilityLabel: Self.calloutCopy,
                     action: {
                         withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) {
                             preferences.pushCalloutResting = false
                         }
                     }) {
            calloutBell
                .frame(width: Self.bellSlot, height: Self.bellSlot)
                .glassPieceSurface(in: Circle(), enabled: true, fallback: .material)
                .contentShape(Circle())
        }
        .accessibilityHint("Shows the notification offer")
        .contextMenu {
            Button {
                dismissCalloutForGood()
            } label: {
                Label("Don't show again", systemImage: "bell.slash")
            }
        }
        .accessibilityAction(named: "Don't show again") { dismissCalloutForGood() }
    }

    private func dismissCalloutForGood() {
        withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) {
            preferences.pushCalloutDismissed = true
        }
    }

    /// A periodic wiggle on iOS 18+ (18-only API); static on iOS 17 and
    /// whenever Reduce Motion is on.
    @ViewBuilder private var calloutBell: some View {
        // System blue, not the accent: the owner kept the bell "blue like
        // before" when the accent moved to sage (ruling 2026-11-11).
        let bell = Image(systemName: "bell.fill")
            .font(.system(size: 17))
            .foregroundStyle(Color.blue)
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

    /// The card chevron (owner ruling 2026-10-02): reveals/hides the
    /// week-dot row — one `chevron.down` that turns −90° while hidden, on
    /// the same reveal spring the row folds on (owner report 2026-11-05);
    /// remembered per card across launches. The toggle runs inside the
    /// transaction so the card AND the list below animate together.
    private func chevronButton(for authored: AuthoredActivity) -> some View {
        let expanded = !preferences.collapsedCardIds.contains(authored.id)
        return Button {
            withAnimation(Theme.Motion.reveal(reduceMotion: reduceMotion)) {
                preferences.toggleCardCollapsed(authored.id)
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
                .rotationEffect(.degrees(expanded ? 0 : -90))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(expanded ? "Hide week" : "Show week")
        .accessibilityIdentifier("cardChevron.\(authored.id)")
    }

    /// The add slot after the card list: the glass Add Activity capsule,
    /// centred in the 64pt the dashed ghost card used (owner ruling
    /// 2026-11-04). Below the soft cap the capsule is a single enlarged "+"
    /// (owner, build 10 POLISH item 3: the "Add Activity" words go, the
    /// glyph takes their room); at the cap it reads the limit, disabled at
    /// half strength, exactly as before.
    @ViewBuilder private var addCard: some View {
        Group {
            if store.isAtCap {
                addActivityCapsule(identifier: "addActivityCard")
            } else {
                addGlyphCapsule
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Self.addSlotHeight)
    }

    /// The header's Dynamic Type ceiling (POLISH item 6) and the forecast
    /// age's, which must fit the header's bottom padding.
    static let headerTypeCap: DynamicTypeSize = .xxxLarge
    static let updatedLabelTypeCap: DynamicTypeSize = .xLarge

    /// The ghost add slot's height (the dashed card's old 64pt).
    private static let addSlotHeight: CGFloat = 64

    /// The "+" capsule's glyph (scales as title2 — HIG: interface icons
    /// scale with Dynamic Type) and its capsule: 4 glyphs wide, the glyph
    /// plus 10 above and below, never under the HIG 44pt target.
    @ScaledMetric(relativeTo: .title2) private var scaledAddGlyph: CGFloat = DashboardLayout.addGlyphSize
    /// Capped so the capsule stays a control, not a banner, at AX sizes.
    private var addGlyphSize: CGFloat { min(scaledAddGlyph, DashboardLayout.addGlyphMax) }

    /// The add slot below the cap: one enlarged "+" on the glass capsule —
    /// still "Add Activity" to VoiceOver, the same press feel and haptic.
    private var addGlyphCapsule: some View {
        GlassControl(presentsSheet: true,
                     identifier: "addActivityCard",
                     accessibilityLabel: "Add Activity",
                     action: { showAdd = true }) {
            Image(systemName: "plus")
                .font(.system(size: addGlyphSize, weight: .semibold))
                .foregroundStyle(Theme.accentBrand)
                .frame(width: addGlyphSize * DashboardLayout.addCapsuleWidthInGlyphs,
                       height: max(GlassCapsule.height, addGlyphSize + 2 * DashboardLayout.addGlyphInset))
                .glassPieceSurface(in: Capsule(), enabled: true, fallback: .material)
                .contentShape(Capsule())
        }
    }

    /// "⊕ Add Activity" — a 40pt glass capsule (plus.circle + 16pt Semibold
    /// in `accentBrand`) inside a 44pt hit target (2pt above and below,
    /// outside the glass) that opens the wizard; the first-launch hero
    /// and the add slot after the list are the same control. At the soft cap
    /// it reads "Activity limit reached (N)", disabled at 50%.
    private func addActivityCapsule(identifier: String) -> some View {
        let atCap = store.isAtCap
        return GlassControl(presentsSheet: true, identifier: identifier) {
            showAdd = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                Text(atCap ? "Activity limit reached (\(ActivityStore.softCap))" : "Add Activity")
            }
            .glassCapsule(font: GlassCapsule.addFont,
                          height: GlassCapsule.addHeight,
                          horizontalPadding: GlassCapsule.addHorizontalPadding,
                          enabled: !atCap)
            .opacity(atCap ? GlassCapsule.disabledOpacity : 1)
            .padding(.vertical, GlassCapsule.addHitPadding)
        }
        .disabled(atCap)
    }

    /// Card v2 — "Score ring" (approved frame `458:394`). Wordless beyond the
    /// name, the numerals and the colour: the sublabel and the metric chips
    /// are not on the v2 frame, so they no longer render
    /// here; the "why" moved to the detail's metric cards.
    private func card(for activity: ActivityRating, authored: AuthoredActivity) -> ScoreRingCardView {
        // Today-only (owner ruling 2026-10-02): always day 0; the week is
        // visible in the card's dot row.
        let dayIndex = viewModel.cardDayIndex(for: authored)
        // The FULL Range, gone hours included (owner ruling 2026-11-04).
        let slots = viewModel.rangeSlots(for: authored, dayIndex: dayIndex)
        return ScoreRingCardView(
            // RAW day: a rating-null day still carries its score (ADR-0011),
            // and the frame draws exactly that (the red 31 ring).
            activity: activity,
            day: viewModel.rawDay(for: activity, dayIndex: dayIndex),
            iconSymbol: authored.iconSymbol,
            rangeChipLabel: authored.window.map(RangeText.chipLabel),
            tiers: viewModel.rangeStripTiers(for: authored, dayIndex: dayIndex),
            stripStartLocalHour: slots.first?.localHour,
            weekDots: viewModel.timeDeriver.map {
                WeekDots.dots(for: activity, deriver: $0,
                              nocturnal: viewModel.isNocturnal(activityId: activity.activityId))
            } ?? [],
            showsWeekDots: !preferences.collapsedCardIds.contains(authored.id),
            // Note 16: a week dot opens the detail on THAT day; the rest of
            // the card still opens today.
            onDotTap: { day in
                navigationPath.append(DetailRoute(activityId: activity.activityId, dayIndex: day))
            }
        )
    }
}

/// A pushed detail: the Activity and the day it opens on (0 = today; a
/// card's week dot pushes its own day — note 16).
struct DetailRoute: Hashable {
    let activityId: String
    var dayIndex: Int = 0
}

// MARK: Eye level (owner, build 10 POLISH item 2)

/// Where the dashboard's first Activity card rests: at eye level — the line
/// the first-launch Add Activity capsule sits on — instead of hugging the
/// header. Pure, so the geometry is pinned by `DashboardLayoutTests`.
enum DashboardLayout {
    /// Eye level, below the top safe-area inset: the first-launch capsule's
    /// glass top on a default-size iPhone 17 Pro as shipped in build 9
    /// (header bottom 127 + 14 + 84 + 52 + 2 = 279 = 62 + 217), then 12
    /// higher after the owner's phone check (2026-11-12): the readings grew
    /// to 22pt and the card came up to meet them.
    static let eyeLevel: CGFloat = 205
    /// The first-launch hero's own vertical padding around capsule + copy.
    static let firstLaunchHeroPadding: CGFloat = 52
    /// The first-launch hero sits in a ScrollView padded by `Spacing.lg`.
    static let firstLaunchListPadding: CGFloat = Theme.Spacing.lg

    /// The add slot's "+" (POLISH item 3): 24pt at the default size, on a
    /// capsule 4 glyphs wide (96) and 44 tall (10 above and below).
    static let addGlyphSize: CGFloat = 24
    static let addGlyphMax: CGFloat = 34
    static let addCapsuleWidthInGlyphs: CGFloat = 4
    static let addGlyphInset: CGFloat = 10

    /// The list's top padding below the header: the first Activity card at
    /// eye level, with `leadingHeight` (the push callout slot + its gap)
    /// sitting above it inside that room. Never under
    /// `Spacing.listBelowHeader` — a tall header (large text) keeps the list
    /// where it always was rather than pushing the cards further down.
    static func listTopInset(headerBottom: CGFloat, safeTop: CGFloat, leadingHeight: CGFloat) -> CGFloat {
        max(Theme.Spacing.listBelowHeader, safeTop + eyeLevel - headerBottom - leadingHeight)
    }

    /// The first-launch hero's top padding so its capsule's glass top lands
    /// at eye level; never negative.
    static func firstLaunchHeroTop(headerBottom: CGFloat, safeTop: CGFloat) -> CGFloat {
        let above = firstLaunchListPadding + firstLaunchHeroPadding + GlassCapsule.addHitPadding
        return max(0, safeTop + eyeLevel - headerBottom - above)
    }
}

#if DEBUG
#Preview("Live cards") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
}

#Preview("Live cards — dark") {
    DashboardView(viewModel: PreviewFixtures.dashboardViewModel(),
                  registration: PreviewFixtures.registration(),
                  router: PushRouter())
        .preferredColorScheme(.dark)
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

// MARK: The callout's wipe (owner ruling 2026-11-11)

/// Uncovers its content from the leading edge (the bell) toward the trailing
/// edge; mirrored in right-to-left layouts.
private struct LeadingWipe: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.mask(alignment: .leading) {
            Rectangle().scaleEffect(x: max(progress, 0.001), y: 1, anchor: .leading)
        }
    }
}

private extension AnyTransition {
    /// The callout's reveal and fold: a leading → trailing wipe both ways, or
    /// a plain cross-fade under Reduce Motion.
    static func wipe(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .modifier(active: LeadingWipe(progress: 0),
                                            identity: LeadingWipe(progress: 1))
    }
}
