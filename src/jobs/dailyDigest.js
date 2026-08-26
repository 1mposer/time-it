// Daily digest job (ADR-0006): hourly cron pass that sends each device at most
// one push per local day — during the 6..11 morning catch-up band (a band, not
// a single hour, so a redeploy across 6am can't drop a timezone's digest), and
// only when something qualifies. All local-day/hour math goes through
// src/weather/timeBoundary.js — never hand-rolled Intl calls.

const { localDay, localHour, bucketDate } = require('../weather/timeBoundary');
const { StaleTokenError } = require('../notifications/apns');
const { rangeLabel } = require('./labels');

const MS_PER_HOUR = 3600 * 1000;
const DIGEST_START_HOUR = 6;
const DIGEST_END_HOUR = 12; // exclusive — past noon, skip

// The #6c §7 type trap: pg returns DATE columns as JS Date objects, and
// dateObject < 'YYYY-MM-DD' is always false in JS — normalise the marker to
// its 'YYYY-MM-DD' string before any comparison.
function markerDateString(marker) {
  if (marker == null) return null;
  if (marker instanceof Date) {
    const y = marker.getFullYear();
    const m = String(marker.getMonth() + 1).padStart(2, '0');
    const d = String(marker.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return String(marker).slice(0, 10);
}

const WEEKDAY_FMT = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'UTC' });
function weekdayLabel(dateString) {
  const [y, m, d] = dateString.split('-').map(Number);
  return WEEKDAY_FMT.format(new Date(Date.UTC(y, m - 1, d)));
}

const capitalize = (rating) => rating.charAt(0).toUpperCase() + rating.slice(1);

// Composes the single digest push, or null when nothing qualifies: today
// lines from each Activity's days[0] (endIndex is exclusive — the end label
// reads the boundary hour) plus week-ahead Perfect highlights over buckets
// 2+ (bucket 1 belongs to the perfect-window detector). Nocturnal detection
// reads the snapshot's window — results never echo it.
function composeDigest(results, snapshotActivities, forecastStart, timezone) {
  const windowById = new Map(snapshotActivities.map((a) => [a.id, a.window]));
  const startMs = Date.parse(forecastStart);
  const localHourAt = (index) => localHour(startMs + index * MS_PER_HOUR, timezone);

  const todayLines = [];
  for (const result of results) {
    const day0 = result.days[0];
    if (!day0 || day0.rating === null) continue;
    const window = windowById.get(result.activityId);
    const nocturnal = window && window.startHour > window.endHour;
    const range = rangeLabel(localHourAt(day0.startIndex), localHourAt(day0.endIndex));
    todayLines.push(
      nocturnal
        ? `${result.label}: ${capitalize(day0.rating)} tonight ${range}`
        : `${result.label}: ${capitalize(day0.rating)} ${range}`
    );
  }

  const weekLines = [];
  for (const result of results) {
    const hit = result.days.slice(2).find((d) => d.rating === 'perfect');
    if (!hit) continue;
    weekLines.push(`${weekdayLabel(bucketDate(forecastStart, timezone, hit.dayIndex))}: Perfect for ${result.label}`);
  }

  const lines = [...todayLines, ...weekLines];
  if (lines.length === 0) return null;
  return { title: 'Daily Digest', body: lines.join('\n'), payload: { type: 'dailyDigest' } };
}

function createDailyDigestJob({ db, getWeather, evaluateAll, sendPush, now = Date.now }) {
  async function runDigestPass() {
    const { rows } = await db.query(
      'SELECT device_id, apns_token, home_lat, home_lon, timezone, activities, last_digest_date FROM devices WHERE apns_token IS NOT NULL'
    );

    for (const device of rows) {
      try {
        const nowMs = now();
        const hour = localHour(nowMs, device.timezone);
        if (hour < DIGEST_START_HOUR || hour >= DIGEST_END_HOUR) continue;

        const today = localDay(nowMs, device.timezone);
        const sent = markerDateString(device.last_digest_date);
        if (sent !== null && sent >= today) continue;

        const { forecastStart, timezone, hours } = await getWeather(device.home_lat, device.home_lon);
        const results = evaluateAll(hours, device.activities);
        const message = composeDigest(results, device.activities, forecastStart, timezone);
        if (!message) continue;

        try {
          await sendPush(device.apns_token, message);
        } catch (err) {
          if (err instanceof StaleTokenError) {
            // Never-erase (ADR-0010): blank the dead push address, keep the row.
            await db.query(
              'UPDATE devices SET apns_token = NULL, updated_at = now() WHERE device_id = $1',
              [device.device_id]
            );
            console.warn(`daily digest: device ${device.device_id} token rejected by APNs (stale) — token blanked, row kept`);
            continue;
          }
          throw err;
        }

        await db.query('UPDATE devices SET last_digest_date = $2::date WHERE device_id = $1', [
          device.device_id,
          today,
        ]);
      } catch (err) {
        console.error(`daily digest: device ${device.device_id} failed`, err);
      }
    }
  }

  return { runDigestPass };
}

module.exports = { createDailyDigestJob, composeDigest, markerDateString };
