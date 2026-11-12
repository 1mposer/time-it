import SwiftUI

/// Gradient dashboard header: Active location name, the current-hour
/// temperature as the big numeral, and a meta line of wall-clock time +
/// wind + humidity (from `hours[0]`; FIGMA.md §12 ruling 7). The numeral
/// falls back to `—°` while loading or on error, and a missing wind or
/// humidity drops its segment; in the no-location state the numeral and the
/// weather segments hide entirely (`showsWeather`) — no fabricated
/// conditions — and the meta line keeps only the clock. Top-right control is the
/// Settings gear — no sign-in (ADR-0001); top-left, mirroring it, the
/// light/dark toggle (owner ruling 2026-11-11).
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
    /// Wind-speed display unit (#26); the hour's value is km/h.
    var windUnit: WindSpeedUnit = .kmh
    /// The appearance on screen — the toggle switches to its opposite.
    var appearance: AppAppearance = .light
    /// The light/dark toggle's action; nil hides the toggle.
    var onAppearanceTap: (() -> Void)? = nil
    let onGearTap: () -> Void

    /// The toggle glyph's accumulated turn — 180° per tap, so it always
    /// spins the same way.
    @State private var toggleTurn: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The Settings gear's glass circle — the HIG 44pt target.
    static let gearDiameter: CGFloat = 44
    /// The gear floats on the temperature band, so it takes CLEAR glass —
    /// regular glass over the light band reads as a white disc (owner report
    /// 2026-11-05). Every other glass control stays `.regular`.
    static let gearGlassStyle: GlassStyle = .clear
    /// The gear circle's reach in from the content edge (13 trailing + 44 −
    /// the content's 20 inset) — the location label wraps inside it.
    private static let gearClearance: CGFloat = gearDiameter + 13 - 20

    /// The meta line's three readings (clock, wind, humidity) — grown from
    /// 13 → 17 → 22 to fill the dead space above the first card (owner, build 10
    /// POLISH item 1); scales as body text (Dynamic Type, owner ruling 8).
    static let metaFontSize: CGFloat = 22
    /// The meta glyphs grow with the readings (11 at the old 13pt).
    static let metaGlyphSize: CGFloat = 18

    /// The meta line's glyphs scale with its text (Dynamic Type, owner
    /// ruling 8); the big numeral and the gear stay fixed.
    @ScaledMetric(relativeTo: .body) private var metaGlyph: CGFloat = HeaderView.metaGlyphSize

    /// The clock text at `date` in the given zone (device zone when nil or
    /// unresolvable) — pinned by HeaderClockTests.
    static func clockText(for date: Date, timezoneIdentifier: String?) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        if let timezoneIdentifier, let zone = TimeZone(identifier: timezoneIdentifier) {
            style.timeZone = zone
        }
        return date.formatted(style)
    }

    /// The meta line at `date`: the clock alone in the no-location state,
    /// else clock + whatever weather the hour carries.
    private func metaSegments(at date: Date) -> [HeaderCopy.MetaSegment] {
        let clock = Self.clockText(for: date, timezoneIdentifier: timezoneIdentifier)
        guard showsWeather else { return [.clock(clock)] }
        return HeaderCopy.metaSegments(clock: clock,
                                       windKmh: currentHour?.windSpeed,
                                       humidity: currentHour?.humidity,
                                       windUnit: windUnit)
    }

    @ViewBuilder
    private func metaItem(_ segment: HeaderCopy.MetaSegment) -> some View {
        switch segment {
        case .clock(let text):
            Text(text)
                .accessibilityIdentifier("headerTime")
        case .wind(let text):
            HStack(spacing: 4) {
                ActivityIconView(identifier: "wind", size: metaGlyph)
                    .opacity(0.85)
                    .accessibilityLabel("Wind")
                Text(text)
            }
        case .humidity(let text):
            HStack(spacing: 4) {
                ActivityIconView(identifier: "humidity.fill", size: metaGlyph)
                    .opacity(0.85)
                    .accessibilityLabel("Humidity")
                Text(text)
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Text((locationName ?? "No location").uppercased())
                    .scaledFont(size: 11, weight: .medium)
                    .tracking(1.4)
                    .foregroundStyle(Theme.onGradient.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    // A long or scaled name wraps clear of the gear circle.
                    .padding(.horizontal, Self.gearClearance)
                    .accessibilityIdentifier("headerLocation")

                if showsWeather {
                    // The temperature numeral (rulings 7 / 6b / 8a): light,
                    // with a firmer shadow and a local scrim — a soft dark
                    // pool centred on it — so it reads over the lighter melt.
                    Text(HeaderCopy.numeral(temp: currentHour?.temp))
                        .font(.system(size: 60, weight: .light))
                        .tracking(-2.5)
                        .foregroundStyle(Theme.onGradient)
                        .numeralLegibility()
                        .background {
                            Ellipse()
                                .fill(Theme.shadowInk.opacity(Theme.Fade.scrimOpacity))
                                .frame(width: Theme.Fade.scrimSize.width,
                                       height: Theme.Fade.scrimSize.height)
                                .blur(radius: Theme.Fade.scrimBlur)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        .accessibilityIdentifier("headerTemp")
                        .padding(.top, Theme.Spacing.headerLocationToNumeral)
                }

                // The meta line — clock, wind, humidity (Figma Meta row:
                // 16pt between groups, 4pt icon → value, no separator
                // glyph; 17pt regular since build 10, POLISH item 1). The clock is not weather, so it stays in
                // the no-location state; it ticks in the forecast zone.
                // One line while it fits; at large text sizes the segments
                // stack rather than run off the screen.
                TimelineView(.everyMinute) { context in
                    let segments = metaSegments(at: context.date)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            ForEach(segments, id: \.self) { segment in
                                metaItem(segment)
                            }
                        }
                        VStack(spacing: 4) {
                            ForEach(segments, id: \.self) { segment in
                                metaItem(segment)
                            }
                        }
                    }
                }
                .scaledFont(size: Self.metaFontSize)
                .tracking(0.1)
                .foregroundStyle(Theme.onGradient)
                .padding(.top, showsWeather ? Theme.Spacing.headerNumeralToMeta : 6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 22)

            // A 44pt glass circle floating over the band — the textbook
            // glass case (owner ruling 2026-11-04). Centred where the old
            // 34pt circle was (top 8 + 17, trailing 18 + 17).
            GlassControl(presentsSheet: true,
                         identifier: "settingsGear",
                         accessibilityLabel: "Settings",
                         action: onGearTap) {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.onGradient)
                    .frame(width: Self.gearDiameter, height: Self.gearDiameter)
                    .glassPieceSurface(in: Circle(), enabled: true, fallback: .band,
                                       style: Self.gearGlassStyle)
            }
            .padding(.top, 3)
            .padding(.trailing, 13)
        }
        .overlay(alignment: .topLeading) {
            if let onAppearanceTap {
                appearanceToggle(action: onAppearanceTap)
                    .padding(.top, 3)
                    .padding(.leading, 13)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // No background of its own: the temperature band (cool blue / mid
        // amber / hot salmon) and its melt are the dashboard's backdrop
        // (`BandMeltView`), drawn full-screen behind this text and the card
        // list. Content stays in the safe area (a control under the status
        // bar is untappable).
    }

    /// The light/dark toggle: the gear's twin — 44pt CLEAR glass on the band,
    /// a constant `circle.lefthalf.filled` that turns 180° per tap (no turn
    /// under Reduce Motion); the window crossfades (`AppearanceController`).
    private func appearanceToggle(action: @escaping () -> Void) -> some View {
        GlassControl(identifier: "appearanceToggle",
                     accessibilityLabel: appearance == .light ? "Switch to Dark" : "Switch to Light",
                     action: {
                         if !reduceMotion {
                             withAnimation(Theme.Motion.reveal) { toggleTurn += 180 }
                         }
                         action()
                     }) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.onGradient)
                .rotationEffect(.degrees(toggleTurn))
                .frame(width: Self.gearDiameter, height: Self.gearDiameter)
                .glassPieceSurface(in: Circle(), enabled: true, fallback: .band,
                                   style: Self.gearGlassStyle)
        }
    }

    /// The temperature the band is coloured by — nil (Cool) when the
    /// weather rows are hidden, so no fabricated band either.
    static func bandTemp(currentHour: HourlyWeather?, showsWeather: Bool) -> Double? {
        showsWeather ? currentHour?.temp : nil
    }
}

private extension View {
    /// Figma drop shadow on the temperature numeral (radius 6, y 2, black 30%).
    func numeralLegibility() -> some View {
        shadow(color: Theme.shadowInk.opacity(Theme.Fade.numeralShadowOpacity),
               radius: Theme.Fade.numeralShadowRadius,
               y: Theme.Fade.numeralShadowY)
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
    .background(BandMeltView(firstCardTop: 229, temp: 24).ignoresSafeArea())
}

#Preview("Header — Accessibility XXL") {
    VStack(spacing: 0) {
        HeaderView(locationName: "Dubai",
                   currentHour: PreviewFixtures.forecast.hours.first,
                   timezoneIdentifier: "Asia/Dubai") {}
        Spacer()
    }
    .background(BandMeltView(firstCardTop: 229, temp: 24).ignoresSafeArea())
    .environment(\.dynamicTypeSize, .accessibility4)
}

#Preview("Header — no location") {
    VStack(spacing: 0) {
        HeaderView(locationName: nil,
                   currentHour: nil,
                   showsWeather: false) {}
        Spacer()
    }
    .background(BandMeltView(firstCardTop: 229, temp: nil).ignoresSafeArea())
}
#endif
