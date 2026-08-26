// Hourly push job (ADR-0006): alerts once when a new Perfect window appears in
// a device's next ~48h. Dedup: one alert per (device, activity, bucket date) —
// keyed on the bucket's calendar date via timeBoundary.bucketDate, never on
// window indices (they re-base with every fresh forecastStart) and never on
// hours[startIndex].localDay (a nocturnal morning-tail carries the MORNING's
// date). The dedup row is inserted before the push so a crash misses an
// alert, never duplicates one.

const { localHour, bucketDate } = require('../weather/timeBoundary');
const { StaleTokenError } = require('../notifications/apns');
const { hourLabel, rangeLabel } = require('./labels');

const MS_PER_HOUR = 3600 * 1000;
const HORIZON_BUCKETS = 2; // alert on buckets 0–1 only
const RETENTION_DAYS = 2; // prune dedup rows older than today − 2

// Builds the push title/body. endIndex is exclusive — the end label reads the
// boundary hour, and a window has "ended" once that instant passes.
function composeAlert({ label, nocturnal, dayIndex, day, forecastStart, timezone, nowMs }) {
  const startMs = Date.parse(forecastStart) + day.startIndex * MS_PER_HOUR;
  const endMs = Date.parse(forecastStart) + day.endIndex * MS_PER_HOUR;
  let body;
  if (nowMs >= startMs) {
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
      'SELECT device_id, apns_token, home_lat, home_lon, timezone, activities FROM devices WHERE apns_token IS NOT NULL'
    );

    for (const device of rows) {
      try {
        const { forecastStart, timezone, hours } = await getWeather(device.home_lat, device.home_lon);
        const results = evaluateAll(hours, device.activities);
        const windowById = new Map(device.activities.map((a) => [a.id, a.window]));
        const startMsBase = Date.parse(forecastStart);
        const nowMs = now();

        let deviceDeactivated = false;
        for (const result of results) {
          if (deviceDeactivated) break;
          const window = windowById.get(result.activityId);
          const nocturnal = Boolean(window && window.startHour > window.endHour);

          for (const day of result.days.slice(0, HORIZON_BUCKETS)) {
            if (day.rating !== 'perfect') continue;
            if (startMsBase + day.endIndex * MS_PER_HOUR <= nowMs) continue;

            const bucket = bucketDate(forecastStart, timezone, day.dayIndex);
            const inserted = await db.query(
              'INSERT INTO notification_state (device_id, activity_id, bucket_date) VALUES ($1, $2, $3::date) ON CONFLICT DO NOTHING',
              [device.device_id, result.activityId, bucket]
            );
            if (inserted.rowCount !== 1) continue;

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
                // Never-erase (ADR-0010): blank the dead push address, keep the
                // row — its notification_state rows survive too.
                await db.query(
                  'UPDATE devices SET apns_token = NULL, updated_at = now() WHERE device_id = $1',
                  [device.device_id]
                );
                console.warn(`perfect-window detector: device ${device.device_id} token rejected by APNs (stale) — token blanked, row kept`);
                deviceDeactivated = true;
                break;
              }
              throw err;
            }
          }
        }
      } catch (err) {
        console.error(`perfect-window detector: device ${device.device_id} failed`, err);
      }
    }

    const todayUtc = new Date(now()).toISOString().slice(0, 10);
    await db.query(
      `DELETE FROM notification_state WHERE bucket_date < $1::date - ${RETENTION_DAYS}`,
      [todayUtc]
    );
  }

  return { runDetectorPass };
}

module.exports = { createPerfectWindowDetectorJob };
