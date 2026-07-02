const { evaluate } = require('./decision_engine');

// Per-day bucketing layer (ADR-0003). A "bucket" is { offset, hours }: a contiguous
// slice of the global hours[] plus its GLOBAL start offset. The engine searches a
// bucket's slice with slice-relative indices; the offset converts the result back to
// global indices before it reaches the wire (ADR-0004 pin 1). Buckets are always
// dense and ordered, so a bucket's position in the array IS its dayIndex.
//
// SEAM (ADR-0003): bucketing silently depends on `hours` being pre-tagged with
// `localDay`/`localHour` by the time-boundary module. Untagged hours collapse to ONE
// bucket with no error — callers MUST pass tagged hours (the route does; raw provider
// hours would yield one-day output and break every window/night activity).

// Diurnal / no-window: one bucket per contiguous local-calendar-day run.
function bucketByLocalDay(hours) {
  const buckets = [];
  for (let i = 0; i < hours.length; i++) {
    const last = buckets[buckets.length - 1];
    if (last && last.localDay === hours[i].localDay) last.hours.push(hours[i]);
    else buckets.push({ localDay: hours[i].localDay, offset: i, hours: [hours[i]] });
  }
  return buckets;
}

// Same-day window [startHour, endHour) (startHour < endHour): keep the calendar-day
// buckets but filter each to hours whose localHour falls in the half-open window. The
// kept hours are contiguous within the day (localHour is monotonic), so the slice's
// global offset is the day offset plus the position of the first kept hour. days.length
// is unchanged — only the eligible hours per day shrink.
function bucketSameDayWindow(hours, startHour, endHour) {
  return bucketByLocalDay(hours).map((bucket) => {
    let firstLocalIndex = -1;
    const kept = [];
    bucket.hours.forEach((h, localIndex) => {
      if (h.localHour >= startHour && h.localHour < endHour) {
        if (firstLocalIndex === -1) firstLocalIndex = localIndex;
        kept.push(h);
      }
    });
    const offset = firstLocalIndex === -1 ? bucket.offset : bucket.offset + firstLocalIndex;
    return { offset, hours: kept };
  });
}

// Wrapped window (startHour > endHour) — the night-stitch (ADR-0003 amendment). The
// stitch unit is the NIGHT, not eligible-hours-then-bucket: night N pairs the late
// evening of calendar day N (localHour >= startHour) with the early morning of day
// N+1 (localHour < endHour). The window's dayIndex is the EVENING's calendar day, so
// "tonight" lands on today's card. Exactly one midnight is crossed per night (bounded,
// opt-in), so this cannot resurrect the unbounded cross-day fusion.
function bucketNightWindow(hours, startHour, endHour) {
  // Ordinal of each distinct local calendar day (0 = first day in the horizon).
  const dayOrdinal = new Map();
  for (const h of hours) if (!dayOrdinal.has(h.localDay)) dayOrdinal.set(h.localDay, dayOrdinal.size);

  const byNight = new Map(); // nightIndex -> { offset, hours }
  hours.forEach((h, i) => {
    let nightIndex;
    if (h.localHour >= startHour) nightIndex = dayOrdinal.get(h.localDay);        // this night's evening
    else if (h.localHour < endHour) nightIndex = dayOrdinal.get(h.localDay) - 1;  // previous night's morning
    else return;                                                                  // daytime — not nocturnal
    // Orphan morning: day-0's early hours whose evening is BEFORE the horizon belong
    // to a night that does not exist (ADR-0003) — dropped, never their own day.
    if (nightIndex < 0) return;
    if (!byNight.has(nightIndex)) byNight.set(nightIndex, { offset: i, hours: [] });
    byNight.get(nightIndex).hours.push(h);
  });

  // Dense, ordered from night 0 (tonight). Each calendar day 0..D-1 contributes an
  // evening, so the present nights are 0..max with no gaps in a real horizon.
  const buckets = [];
  const maxNight = byNight.size === 0 ? -1 : Math.max(...byNight.keys());
  for (let n = 0; n <= maxNight; n++) {
    buckets.push(byNight.get(n) || { offset: 0, hours: [] });
  }
  return buckets;
}

// Choose the bucketing strategy from the activity's optional time-of-day window
// (ADR-0005). Absent window -> whole-day diurnal; startHour < endHour -> same-day;
// startHour > endHour -> midnight-wrap night-stitch. (startHour === endHour is
// rejected at request validation, so it never reaches here.)
function bucketsForActivity(hours, window) {
  if (!window) return bucketByLocalDay(hours);
  const { startHour, endHour } = window;
  if (startHour < endHour) return bucketSameDayWindow(hours, startHour, endHour);
  return bucketNightWindow(hours, startHour, endHour);
}

// Map a bucket to the wire day-shape, offsetting slice-relative window indices back
// to global hours[] positions.
function toDay(dayIndex, bucket, prefs) {
  const window = evaluate(bucket.hours, prefs);
  const day = { dayIndex, rating: window.rating };
  if (window.rating !== null) {
    day.startIndex = window.startIndex + bucket.offset;
    day.endIndex   = window.endIndex + bucket.offset;
    day.duration   = window.duration;
  }
  return day;
}

// Activities are CALLER-SUPPLIED (ADR-0002/0005): the engine holds no activity list.
// Bucketing happens PER ACTIVITY (not once outside the loop) because a wrapped window
// buckets by night while diurnal/same-day activities bucket by calendar day — so
// days.length is per-activity (ADR-0004 amendment). This is the seam the night-stitch
// cut along.
function evaluateAll(hours, activities) {
  const results = [];

  for (const activity of activities) {
    const prefs = { activityId: activity.id, thresholds: activity.thresholds };
    const buckets = bucketsForActivity(hours, activity.window);
    const days = buckets.map((bucket, dayIndex) => toDay(dayIndex, bucket, prefs));

    results.push({
      activityId:     activity.id,
      label:          activity.label,
      displayMetrics: activity.displayMetrics,
      days,
    });
  }

  return results;
}

module.exports = { evaluateAll, bucketByLocalDay, bucketsForActivity, toDay };
