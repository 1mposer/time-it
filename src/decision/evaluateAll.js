const { evaluate } = require('./decision_engine');
const { activities } = require('../activities/index');

// Per-day bucketing layer (ADR-0003). Splits the flat hours[] into contiguous
// runs sharing a `localDay` (tagged upstream by the time-boundary module),
// recording each bucket's GLOBAL start offset into hours[]. The engine searches
// a bucket's hour-slice with slice-relative indices; the offset converts the
// result back to global indices before it reaches the wire (ADR-0004 pin 1).
function bucketByLocalDay(hours) {
  const buckets = [];
  for (let i = 0; i < hours.length; i++) {
    const last = buckets[buckets.length - 1];
    if (last && last.localDay === hours[i].localDay) last.hours.push(hours[i]);
    else buckets.push({ localDay: hours[i].localDay, offset: i, hours: [hours[i]] });
  }
  return buckets;
}

function evaluateAll(hours) {
  const buckets = bucketByLocalDay(hours);
  const results = [];

  for (const activity of activities) {
    const prefs = { activityId: activity.id, thresholds: activity.thresholds };

    const days = buckets.map((bucket, dayIndex) => {
      const window = evaluate(bucket.hours, prefs);
      const day = { dayIndex, rating: window.rating };
      if (window.rating !== null) {
        // Offset slice-relative indices back to global hours[] positions.
        day.startIndex = window.startIndex + bucket.offset;
        day.endIndex   = window.endIndex + bucket.offset;
        day.duration   = window.duration;
      }
      return day;
    });

    results.push({
      activityId:     activity.id,
      label:          activity.label,
      displayMetrics: activity.displayMetrics,
      days,
    });
  }

  return results;
}

module.exports = { evaluateAll };
