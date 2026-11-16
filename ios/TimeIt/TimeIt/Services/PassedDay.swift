import SwiftUI

// MARK: - The verdict line (owner rulings 2026-11-15)

/// "7 – 10am · Perfect" — the Window and its verdict, in the verdict's tint;
/// "No good time" in red on a day without one (ruling 07 a). The card, the
/// Report hero, the hours-over row and the Coming days list all read it.
/// Independent of the score (ADR-0011): the ring is coloured by its band,
/// this line by the verdict.
struct VerdictLine: Equatable {
    /// "7 – 10am"; nil on a day without a qualifying Window.
    let window: String?
    /// `.perfect` / `.good`; nil for a null OR unknown verdict (never
    /// favourable on a verdict this build doesn't know — 2026-08-29).
    let rating: Rating?

    static let noGoodTime = "No good time"

    init(window: String?, rating: Rating?) {
        let qualifies = rating?.isQualifying == true && window != nil
        self.window = qualifies ? window : nil
        self.rating = qualifies ? rating : nil
    }

    /// The day's Window as location-local clock hours (`endIndex` exclusive).
    init(day: Day?, deriver: TimeDeriver?) {
        guard let day, day.hasWindow, let start = day.startIndex, let end = day.endIndex,
              let deriver else {
            self.init(window: nil, rating: nil)
            return
        }
        self.init(window: RangeText.spanLabel(startHour: deriver.localHour(at: start),
                                              endHour: deriver.localHour(at: end)),
                  rating: day.rating)
    }

    /// "Perfect" / "Good"; nil without a Window.
    var verdict: String? {
        switch rating {
        case .perfect: return "Perfect"
        case .good: return "Good"
        default: return nil
        }
    }

    var text: String {
        guard let window, let verdict else { return Self.noGoodTime }
        return "\(window) · \(verdict)"
    }

    var tint: Color { Theme.ratingTint(rating) }
}

// MARK: - Passed day (owner ruling 05 a)

/// After today's chosen hours are over the card moves to TOMORROW: ring
/// caption "Tomorrow", today's week dot greyed, a glass overlay on the card;
/// the detail opens on tomorrow under the hours-over row.
enum PassedDay {
    /// True once today's Range has ended in the location's clock. For a
    /// windowed Activity a nil `days[0].score` (zero window hours left) is
    /// the server's own signal; the clock check covers a cached forecast that
    /// still holds the last Range hour. A wrapped Range never passes (tonight
    /// is always ahead of or inside the forecast), no Range never passes, and
    /// without a `days[1]` there is nothing to move to.
    static func hasPassed(window: WindowSpec?, days: [Day], deriver: TimeDeriver?, now: Date) -> Bool {
        guard let window, !window.isWrapped, let deriver,
              let today = days.first(where: { $0.dayIndex == 0 }),
              days.contains(where: { $0.dayIndex == 1 }) else { return false }
        if today.score == nil { return true }
        guard let positions = deriver.rangePositions(window: window, dayIndex: 0) else { return false }
        return deriver.rangeHasPassed(positions, now: now)
    }

    /// What the card shows.
    struct CardDay: Equatable {
        let passed: Bool

        var dayIndex: Int { passed ? 1 : 0 }
        /// The ring's caption: "Average" (the day score's name — ruling
        /// 03 a), "Tomorrow" on a ring showing tomorrow (02 b).
        var caption: String { passed ? "Tomorrow" : "Average" }
        /// Today's dot greys once its hours are over.
        var dimmedDayIndex: Int? { passed ? 0 : nil }
    }
}

// MARK: - The retained morning result + dismissals

/// The last rated day-0 result seen before the hours passed — "Best was
/// 7 – 10am · Perfect". Local, never sent.
struct MorningResult: Codable, Equatable {
    enum Verdict: String, Codable { case perfect, good }

    let verdict: Verdict
    let window: String

    init(verdict: Verdict, window: String) {
        self.verdict = verdict
        self.window = window
    }

    /// Only a qualifying verdict is ever retained.
    init?(_ line: VerdictLine) {
        guard let window = line.window else { return nil }
        switch line.rating {
        case .perfect: self.init(verdict: .perfect, window: window)
        case .good: self.init(verdict: .good, window: window)
        default: return nil
        }
    }

    init(rating: Rating, window: String) {
        self.init(verdict: rating == .good ? .good : .perfect, window: window)
    }

    var rating: Rating { verdict == .perfect ? .perfect : .good }
}

/// Per Activity per local date: the retained morning result, the card
/// overlay's dismissal and the hours-over row's dismissal. Keys carry the
/// date (the location's calendar day of `days[0]`), so everything rolls over
/// at local midnight; a write on a new date prunes the old ones.
@MainActor
final class PassedDayStore: ObservableObject {
    static let shared: PassedDayStore = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_RESET") {
            UserDefaults.standard.removeObject(forKey: storageKey)
        }
        #endif
        return PassedDayStore()
    }()

    static let storageKey = "passedDays"

    struct Entry: Codable, Equatable {
        var morning: MorningResult?
        var overlayDismissed = false
        var rowDismissed = false
    }

    private struct Key: Codable, Hashable {
        let date: String
        let activityId: String
    }

    @Published private var entries: [String: [String: Entry]] // date → activityId → entry
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: [String: Entry]].self, from: $0) } ?? [:]
    }

    var storedDates: [String] { entries.keys.sorted() }

    func entry(activityId: String, date: String) -> Entry {
        entries[date]?[activityId] ?? Entry()
    }

    func recordMorning(_ result: MorningResult, activityId: String, date: String) {
        guard entry(activityId: activityId, date: date).morning != result else { return }
        mutate(activityId: activityId, date: date) { $0.morning = result }
    }

    func dismissOverlay(activityId: String, date: String) {
        mutate(activityId: activityId, date: date) { $0.overlayDismissed = true }
    }

    func dismissRow(activityId: String, date: String) {
        mutate(activityId: activityId, date: date) { $0.rowDismissed = true }
    }

    func reset() {
        entries = [:]
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func mutate(activityId: String, date: String, _ change: (inout Entry) -> Void) {
        var day = entries[date] ?? [:]
        var entry = day[activityId] ?? Entry()
        change(&entry)
        day[activityId] = entry
        // One day only: a write on a new date drops every other date.
        entries = [date: day]
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

// MARK: - Copy (owner rulings 2026-11-15/16, verbatim)

enum HoursOverCopy {
    static let title = "Today\u{2019}s hours are over"
    static let overlayHint = "Tap to dismiss"

    static func overlay(rangeLabel: String) -> String {
        "Your chosen hours of \(rangeLabel) have passed, you are seeing tomorrow\u{2019}s score."
    }

    /// "Best was 7 – 10am · " + "Perfect" in its tint; nil → the title alone.
    struct BestWas: Equatable {
        let lead: String
        let verdict: String
        let rating: Rating
    }

    static func bestWas(_ morning: MorningResult?) -> BestWas? {
        guard let morning else { return nil }
        let line = VerdictLine(window: morning.window, rating: morning.rating)
        guard let verdict = line.verdict else { return nil }
        return BestWas(lead: "Best was \(morning.window) · ", verdict: verdict, rating: morning.rating)
    }
}
