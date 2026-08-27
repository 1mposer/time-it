import SwiftUI

/// Gradient dashboard header: Active location name, wall-clock time, and the
/// forecast location's current-hour weather (temp/wind/humidity from
/// `hours[0]`). Falls back to `—` while loading, on error, or when a metric
/// is missing; in the no-location state the weather rows hide entirely
/// (`showsWeather`) — no fabricated conditions. Top-right control is the
/// Settings gear — no sign-in (ADR-0001).
struct HeaderView: View {
    /// Active location's display name (picked city, "Current location", or
    /// the cached name); nil renders "NO LOCATION".
    let locationName: String?
    /// Current forecast hour (`forecast.hours.first`); nil while loading or
    /// on error — placeholders show.
    let currentHour: HourlyWeather?
    /// False in the no-location state — hides temp/conditions rather than
    /// show placeholders for a nonexistent location.
    var showsWeather = true
    /// The forecast location's IANA zone — the clock ticks in it, so a
    /// Bangkok home shows Bangkok time from anywhere. nil (no forecast yet)
    /// falls back to the device clock.
    var timezoneIdentifier: String? = nil
    let onGearTap: () -> Void

    /// The clock text at `date` in the given zone (device zone when nil or
    /// unresolvable) — pinned by HeaderClockTests.
    static func clockText(for date: Date, timezoneIdentifier: String?) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        if let timezoneIdentifier, let zone = TimeZone(identifier: timezoneIdentifier) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }

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
                    Text(Self.clockText(for: context.date, timezoneIdentifier: timezoneIdentifier))
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
        // untappable) — only the gradient bleeds behind it.
        .background(Theme.headerGradient.ignoresSafeArea(edges: .top))
    }
}

#if DEBUG
#Preview("Header") {
    VStack(spacing: 0) {
        HeaderView(locationName: "Dubai",
                   currentHour: PreviewFixtures.forecast.hours.first,
                   timezoneIdentifier: "Asia/Dubai") {}
        Spacer()
    }
    .background(Theme.appBackground)
}

#Preview("Header — no location") {
    VStack(spacing: 0) {
        HeaderView(locationName: nil,
                   currentHour: nil,
                   showsWeather: false) {}
        Spacer()
    }
    .background(Theme.appBackground)
}
#endif
