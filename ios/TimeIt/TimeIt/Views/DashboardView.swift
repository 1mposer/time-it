import SwiftUI

/// Root surface: gradient header → 0.5pt divider → scrollable card list.
/// Single NavigationStack, no tab bar, no sign-in gate (ADR-0001, grill Q8).
struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    @State private var showSettings = false

    init(viewModel: DashboardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderView(currentHour: viewModel.forecast?.hours.first) { showSettings = true }
                Theme.divider
                    .frame(height: 0.5)
                content
            }
            .background(Theme.appBackground)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .task { await viewModel.loadForecast() }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
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
                // One card per returned activity, in request order.
                ForEach(forecast.activities) { activity in
                    NavigationLink {
                        ActivityDetailView(activity: activity, viewModel: viewModel)
                    } label: {
                        card(for: activity, in: forecast)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("card.\(activity.activityId)")
                }
                Spacer()
                    .frame(height: 12)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)
        }
    }

    private func card(for activity: ActivityRating, in forecast: ForecastResponse) -> ActivityCardView {
        let day = viewModel.cardDay(for: activity)
        return ActivityCardView(
            activity: activity,
            day: day,
            windowStartHour: day.flatMap { viewModel.windowStartHour(for: $0) },
            deriver: viewModel.timeDeriver,
            hoursCount: forecast.hours.count
        )
    }
}
