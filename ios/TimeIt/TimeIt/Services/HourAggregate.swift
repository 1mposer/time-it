import Foundation

/// The detail metric cards' reading of the carousel's chosen hours (owner
/// ruling 2026-11-01: "cards average the chosen hours"). Pure, so a later
/// Calculate button only has to decide WHEN `aggregate(_:)` runs — the view
/// reads its `displayedHours` through here.
///
/// The result is synthesised as an `HourlyWeather`, so `MetricCardView`'s
/// value formatting, gauge dot and `HourQuality.metricTier` verdict read it
/// unchanged:
/// - numeric metrics: the mean of the hours' NON-nil values (unrounded — the
///   card's formatter rounds); all nil → nil ("—").
/// - flags (`dustAlert`, `seaWarning`): true if ANY chosen hour is true.
/// - label (`moon`) and the coming-soon placeholders: the first hour's value.
/// - `index`: the first chosen hour's index.
enum HourAggregate {
    /// The chosen SLOTS folded into one reading: only slots with data count
    /// (a gone hour before the forecast has none — owner ruling 2026-11-04);
    /// nil when no chosen slot has data, so the cards show "—".
    static func aggregate(slots: [HourSlot], hours: [HourlyWeather]) -> HourlyWeather? {
        aggregate(slots.compactMap(\.index).filter(hours.indices.contains).map { hours[$0] })
    }

    static func aggregate(_ hours: [HourlyWeather]) -> HourlyWeather? {
        guard let first = hours.first else { return nil }
        guard hours.count > 1 else { return first }
        func mean(_ value: (HourlyWeather) -> Double?) -> Double? {
            let values = hours.compactMap(value)
            guard !values.isEmpty else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        return HourlyWeather(index: first.index,
                             temp: mean(\.temp),
                             humidity: mean(\.humidity),
                             visibility: mean(\.visibility),
                             uV: mean(\.uV),
                             windSpeed: mean(\.windSpeed),
                             rainFall: mean(\.rainFall),
                             cloudCover: mean(\.cloudCover),
                             moon: first.moon,
                             dustAlert: hours.contains(where: \.dustAlert),
                             seaWarning: hours.contains(where: \.seaWarning),
                             darkness: first.darkness,
                             douglasScale: first.douglasScale,
                             swellHeight: first.swellHeight,
                             swellLength: first.swellLength,
                             tide: first.tide)
    }
}
