import SwiftUI

/// Gradient dashboard header: the Active location's name (#5c), current
/// wall-clock time, plus the forecast location's current-hour weather
/// (temp / wind / humidity from `hours[0]`). Values fall back to `—` while
/// loading, on error, or when the provider omitted a metric; in the
/// no-location state the weather rows hide entirely (`showsWeather`) — no
/// fabricated conditions. The top-right control is the Settings gear — there
/// is no sign-in (ADR-0001).
struct HeaderView: View {
    /// The Active location's display name (picked city, "Current location",
    /// or the cached name); nil renders "NO LOCATION" (#5c).
    let locationName: String?
    /// The current forecast hour (`forecast.hours.first`); nil while loading
    /// or on error, in which case the placeholders show.
    let currentHour: HourlyWeather?
    /// False in the no-location state: hide temp + conditions rather than
    /// show placeholders for a location that doesn't exist.
    var showsWeather = true
    let onGearTap: () -> Void

    private var tempText: String {
        guard let t = currentHour?.temp else { return "—°C" }
        return "\(Int(t.rounded()))°C"
    }

    private var windText: String {
        guard let w = currentHour?.windSpeed else { return "— km/h" }
        return "\(Int(w.rounded())) km/h"
    }

    private var humidityText: String {
        guard let h = currentHour?.humidity else { return "—%" }
        return "\(Int(h.rounded()))%"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Text((locationName ?? "No location").uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.85))
                    .accessibilityIdentifier("headerLocation")

                TimelineView(.everyMinute) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 60, weight: .bold, design: .default))
                        .tracking(-2.5)
                        .foregroundStyle(.white)
                        .accessibilityIdentifier("headerTime")
                }

                if showsWeather {
                    Text(tempText)
                        .font(.system(size: 28, weight: .light))
                        .tracking(-0.5)
                        .foregroundStyle(.white.opacity(0.92))
                        .accessibilityIdentifier("headerTemp")

                    HStack(spacing: 24) {
                        HStack(spacing: 5) {
                            ActivityIconView(identifier: "wind", size: 12)
                                .accessibilityLabel("Wind")
                            Text(windText)
                        }

                        HStack(spacing: 5) {
                            ActivityIconView(identifier: "humidity.fill", size: 12)
                                .accessibilityLabel("Humidity")
                            Text(humidityText)
                        }
                    }
                    .font(.system(size: 13))
                    .tracking(0.1)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            Button(action: onGearTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .padding(.top, 8)
            .padding(.trailing, 18)
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsGear")
        }
        .fixedSize(horizontal: false, vertical: true)
        // Content stays in the safe area (a control under the status bar is
        // untappable); only the gradient extends behind it.
        .background(Theme.headerGradient.ignoresSafeArea(edges: .top))
    }
}
