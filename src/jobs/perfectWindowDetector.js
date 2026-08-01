// Perfect-window detector (#6d spec, ADR-0006). Hourly pass beside the digest:
// push the moment a NEW Perfect window appears in a device's near-term forecast.
//
// Dedup is bucket-keyed (device_id, activity_id, bucket_date) — NEVER index-
// keyed: global indices re-base against every fresh forecastStart, so the
// pre-rebuild startIndex dedup re-alerted the same window hourly. bucket_date
// comes from timeBoundary.bucketDate (date-of-day-0 + dayIndex) and NOT from
// hours[startIndex].localDay (audit 2026-07-16): a nocturnal bucket spans
// midnight, so a morning-tail window's startIndex hour carries the MORNING's
// date — jitter across midnight would re-alert the same night AND the misfiled
// key would suppress the real next-night alert. dayIndex is the evening's
// ordinal by construction, so the dayIndex derivation is correct for diurnal
// and nocturnal alike.
//
// Insert-first, push-second: a crash between the two makes a missed alert,
// never a duplicate (spam is the worse failure). Perfect-only — Good belongs
// to the digest; a good→perfect upgrade alerts inherently as that bucket's
// first Perfect. Horizon: buckets 0–1 (~48h) — far-out days are volatile and
// there is no retraction push; they surface via the digest's week-ahead line.

const { localHour, bucketDate } = require('../weather/timeBoundary');
const { StaleTokenError } = require('../notifications/apns');
const { hourLabel, rangeLabel } = require('./labels');

const MS_PER_HOUR = 3600 * 1000;
const HORIZON_BUCKETS = 2; // buckets 0–1 only (decision 2026-07-16)
const RETENTION_DAYS = 2; // prune keys older than today − 2 (table stays O(devices × activities × 2))

// endIndex is EXCLUSIVE ([startIndex, endIndex), duration = end − start) — the
// engine contract pinned by decision_engine.js and its tests. The end clock
// label therefore reads the boundary hour directly (a 7→10 window is "7–10am"),
// and "ended" means the END instant has passed (≤ now). An off-by-one here goes
// straight into push copy — treat as contract, not detail.
function composeAlert({ label, nocturnal, dayIndex, day, forecastStart, timezone, nowMs }) {
  const startMs = Date.parse(forecastStart) + day.startIndex * MS_PER_HOUR;
  const endMs = Date.parse(forecastStart) + day.endIndex * MS_PER_HOUR;
  let body;
  if (nowMs >= startMs) {
    // Ongoing: the start instant has passed but the end instant hasn't.
    body = `Now until ${hourLabel(localHour(endMs, timezone))}`;
  } else {
    const dayLabel = dayIndex === 0 ? (nocturnal ? 'Tonight' : 'Today') : (nocturnal ? 'Tomorrow night' : 'Tomorrow');
    body = `${dayLabel} ${rangeLabel(localHour(startMs, timezone), localHour(endMs, timezone))} (${day.duration}h)`;
  }
  return { title: `Perfect ${label} window`, body };
}

function createPerfectWindowDetectorJob({ db, getWeather, evaluateAll, sendPush, now = Date.now }) {
  async function runDetectorPass() {
    const { rows } = await db.query(
      'SELECT device_id, apns_token, home_lat, home_lon, timezone, activities FROM devices'
    );

    for (const device of rows) {
      try {
        const { forecastStart, timezone, hours } = await getWeather(device.home_lat, device.home_lon);
        const results = evaluateAll(hours, device.activities);
        // `window` is input-only (never echoed in results) — nocturnal
        // detection reads the snapshot, same as the digest's "tonight" line.
        const windowById = new Map(device.activities.map((a) => [a.id, a.window]));
        const startMsBase = Date.parse(forecastStart);
        const nowMs = now();

        let deviceDeleted = false;
        for (const result of results) {
          if (deviceDeleted) break;
          const window = windowById.get(result.activityId);
          const nocturnal = Boolean(window && window.startHour > window.endHour);

          for (const day of result.days.slice(0, HORIZON_BUCKETS)) {
            if (day.rating !== 'perfect') continue;
            // Already ended → skip BEFORE the insert (no key consumed).
            if (startMsBase + day.endIndex * MS_PER_HOUR <= nowMs) continue;

            const bucket = bucketDate(forecastStart, timezone, day.dayIndex);
            const inserted = await db.query(
              'INSERT INTO notification_state (device_id, activity_id, bucket_date) VALUES ($1, $2, $3::date) ON CONFLICT DO NOTHING',
              [device.device_id, result.activityId, bucket]
            );
            if (inserted.rowCount !== 1) continue; // already alerted (or a concurrent pass won the race)

            const { title, body } = composeAlert({
              label: result.label, nocturnal, dayIndex: day.dayIndex, day, forecastStart, timezone, nowMs,
            });
            try {
              await sendPush(device.apns_token, {
                title,
                body,
                payload: { type: 'perfectWindow', activityId: result.activityId, bucketDate: bucket },
              });
            } catch (err) {
              if (err instanceof StaleTokenError) {
                // Dead token: drop the row (its state rows cascade away) and
                // stop alerting this device.
                await db.query('DELETE FROM devices WHERE device_id = $1', [device.device_id]);
                deviceDeleted = true;
                break;
              }
              throw err;
            }
          }
        }
      } catch (err) {
        // Per-device isolation: one failure never stops the pass.
        console.error(`perfect-window detector: device ${device.device_id} failed`, err);
      }
    }

    // Prune spent keys so the table stays bounded. UTC "today" is fine here:
    // the 2-day slack dwarfs any zone offset, and no live key is ever < today − 2.
    const todayUtc = new Date(now()).toISOString().slice(0, 10);
    await db.query(
      `DELETE FROM notification_state WHERE bucket_date < $1::date - ${RETENTION_DAYS}`,
      [todayUtc]
    );
  }

  return { runDetectorPass };
}

module.exports = { createPerfectWindowDetectorJob };
