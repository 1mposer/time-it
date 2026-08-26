const { evaluate } = require('./decision_engine');

// Per-day bucketing over caller-supplied activities (ADR-0003). A bucket is
// { offset, hours }: a slice of the global hours[] plus its global start
// offset, which converts slice-relative window indices back to global ones
// (ADR-0004 pin 1).
// Seam (ADR-0003): hours must arrive pre-tagged with localDay/localHour —
// untagged hours silently collapse to a single bucket.

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

// Same-day window: calendar-day buckets filtered to localHour in
// [startHour, endHour); days.length is unchanged.
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

// Wrapped window — the night-stitch (ADR-0003 amendment): night N pairs the evening of day N
// (localHour >= startHour) with the next morning (localHour < endHour); the
// bucket's dayIndex is the evening's day. Day 0's pre-horizon orphan morning
// is dropped.
function bucketNightWindow(hours, startHour, endHour) {
  const dayOrdinal = new Map();
  for (const h of hours) if (!dayOrdinal.has(h.localDay)) dayOrdinal.set(h.localDay, dayOrdinal.size);

  const byNight = new Map();
  hours.forEach((h, i) => {
    let nightIndex;
    if (h.localHour >= startHour) nightIndex = dayOrdinal.get(h.localDay);
    else if (h.localHour < endHour) nightIndex = dayOrdinal.get(h.localDay) - 1;
    else return;
    if (nightIndex < 0) return;
    if (!byNight.has(nightIndex)) byNight.set(nightIndex, { offset: i, hours: [] });
    byNight.get(nightIndex).hours.push(h);
  });

  const buckets = [];
  const maxNight = byNight.size === 0 ? -1 : Math.max(...byNight.keys());
  for (let n = 0; n <= maxNight; n++) {
    buckets.push(byNight.get(n) || { offset: 0, hours: [] });
  }
  return buckets;
}

// Strategy from the activity's optional window (ADR-0005): absent → whole-day;
// startHour < endHour → same-day filter; startHour > endHour → night-stitch.
function bucketsForActivity(hours, window) {
  if (!window) return bucketByLocalDay(hours);
  const { startHour, endHour } = window;
  if (startHour < endHour) return bucketSameDayWindow(hours, startHour, endHour);
  return bucketNightWindow(hours, startHour, endHour);
}

// Map a bucket to the wire day shape, offsetting slice-relative window
// indices back to global hours[] positions.
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

// One result per caller-supplied activity, in request order. Bucketing is
// per-activity (a wrapped window buckets by night), so days.length varies
// per activity.
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
