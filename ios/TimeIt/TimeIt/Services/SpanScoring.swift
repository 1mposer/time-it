import Foundation

/// The server's score for the hours the detail carousel shows — the detail's
/// "Score 4 – 8pm" result (owner rulings 2026-11-04). Detail-only state:
/// never written to the forecast, the dashboard card, or any store.
struct SpanScore: Equatable {
    /// The bucket's ADR-0011 `score` as the wire sent it (nil = empty bucket).
    let score: Int?
    /// The bucket's verdict for the span.
    let rating: Rating?
    /// The span as the request's `window` — the row-2 labels read it.
    let window: WindowSpec
}

/// The pure parts of span scoring (owner rulings 2026-11-04). The SOURCE is
/// the server: the authored Activity is re-sent unchanged except `window` =
/// the carousel span, and the reply's bucket for the span's day carries the
/// score. There is NO client-side score formula here, and there must never be
/// one (the deleted ADR-0007 score mirror stays deleted).
enum SpanScoring {

    // MARK: Visibility

    /// The button shows only away from the Range, on a span with at least one
    /// data hour — on the Range the ring already shows its score, and an
    /// all-gone span has nothing to score (it keeps its "Time passed" wording).
    static func showsButton(isAtRange: Bool, slots: [HourSlot]) -> Bool {
        !isAtRange && slots.contains { $0.index != nil }
    }

    // MARK: The request

    /// A request window, or nil for one the server would reject (`400`):
    /// hours outside 0...23, or `startHour == endHour`. Wrapped is legal —
    /// the server treats `startHour > endHour` as nocturnal.
    static func window(startHour: Int, endHour: Int) -> WindowSpec? {
        guard (0...23).contains(startHour), (0...23).contains(endHour),
              startHour != endHour else { return nil }
        return WindowSpec(startHour: startHour, endHour: endHour)
    }

    /// The span as location-local hours, exclusive end — the same shape as
    /// the authored Range. Nil for an empty span or one that maps to equal
    /// hours (a 24h span; the carousel produces 1…23).
    static func window(for span: Range<Int>, deriver: TimeDeriver) -> WindowSpec? {
        guard !span.isEmpty else { return nil }
        return window(startHour: deriver.localHour(at: span.lowerBound),
                      endHour: deriver.localHour(at: span.upperBound))
    }

    /// The authored input with only its `window` swapped for the span.
    static func request(from input: ActivityInput, window: WindowSpec) -> ActivityInput {
        ActivityInput(id: input.id,
                      label: input.label,
                      displayMetrics: input.displayMetrics,
                      thresholds: input.thresholds,
                      window: window)
    }

    // MARK: Reading the reply

    /// The reply bucket to read: the forecast day of the span's FIRST
    /// position. For a wrapped span that is the evening's day — exactly how
    /// the server buckets a nocturnal window. Nil before day 0.
    static func bucketIndex(for span: Range<Int>, deriver: TimeDeriver) -> Int? {
        guard !span.isEmpty else { return nil }
        let day = deriver.dayOrdinal(at: span.lowerBound)
        return day >= 0 ? day : nil
    }

    /// True when the reply's day 0 is the same local day as the forecast on
    /// screen — a reply fetched past local midnight shifts every `dayIndex`,
    /// so its bucket would be the wrong day (treated as a failed call).
    static func replyDayZeroMatches(current: TimeDeriver, replyStart: String) -> Bool {
        guard let replyDate = ISO8601DateFormatter().date(from: replyStart) else { return false }
        let offset = Int((replyDate.timeIntervalSince(current.date(at: 0)) / 3600).rounded())
        return current.dayOrdinal(at: offset) == 0
    }

    /// The span's score and verdict from the reply's one activity; nil when
    /// the bucket is absent (a failed call).
    static func result(from response: ForecastResponse, bucketIndex: Int, window: WindowSpec) -> SpanScore? {
        guard let days = response.activities.first?.days,
              let day = days.first(where: { $0.dayIndex == bucketIndex }) else { return nil }
        return SpanScore(score: day.score, rating: day.rating, window: window)
    }

    // MARK: Copy

    /// "4 – 8pm" — the span as row 2 names it; `RangeText.chipLabel`'s am/pm
    /// rules, like the Range line.
    static func spanText(_ window: WindowSpec) -> String {
        RangeText.chipLabel(window)
    }

    /// "4 to 8pm" — the spoken form.
    static func spoken(_ window: WindowSpec) -> String {
        spanText(window).replacingOccurrences(of: " – ", with: " to ")
    }

    /// "Score 4 – 8pm" — the capsule names the span, not the verb alone.
    static func buttonLabel(_ window: WindowSpec) -> String {
        "Score \(spanText(window))"
    }

    /// "Scored 4 – 8pm" — the quiet text the capsule becomes once the shown
    /// span has a result; the one place the scored span is named.
    static func scoredLabel(_ window: WindowSpec) -> String {
        "Scored \(spanText(window))"
    }

    static func buttonAccessibilityLabel(_ window: WindowSpec) -> String {
        "Score \(spoken(window))"
    }

    /// The hero's `detail.score` label: "Perfect, score 86 out of 100", plus
    /// " for 4 to 8pm" while the ring shows a scored span.
    static func scoreAccessibilityLabel(verdict: String, score: Int?, span: WindowSpec?) -> String {
        let base = score.map { "\(verdict), score \($0) out of 100" } ?? "\(verdict), no score"
        guard let span else { return base }
        return "\(base) for \(spoken(span))"
    }
}
