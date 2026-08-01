// Daily digest job (#6c spec §7, ADR-0006). Runs on an hourly cron pass; for
// each registered device whose local hour is in the 6..11 catch-up band and
// whose digest hasn't been sent for local-today, evaluates the snapshot with
// the SAME engine /rating uses and sends at most one push per device per day —
// only when something qualifies (no "no windows" push).
//
// Catch-up selector (audited 2026-07-16): 6 <= localHour < 12, NOT === 6 — a
// Railway redeploy across the 6am tick would otherwise silently drop the
// digest for a whole timezone band for the day. The sent-today marker makes
// the catch-up idempotent; past noon a "morning" digest is worse than none, so
// the device is skipped until tomorrow.
//
// All local-day/hour math goes through src/weather/timeBoundary.js — never
// hand-rolled Intl calls (spec §7 / handoff constraint 6).

const { localDay, localHour, bucketDate } = require('../weather/timeBoundary');
const { StaleTokenError } = require('../notifications/apns');
const { rangeLabel } = require('./labels');

const MS_PER_HOUR = 3600 * 1000;
const DIGEST_START_HOUR = 6;
const DIGEST_END_HOUR = 12; // exclusive — past noon, skip (no evening "morning" digest)

// §7 type trap: pg returns DATE columns as JS Date objects (constructed at
// LOCAL midnight via new Date(y, m-1, d)), and `dateObject < 'YYYY-MM-DD'` is
// always false in JS (the string coerces to NaN) — a naive comparison silently
// means one digest per device, EVER. Normalise the driver value back to its
// 'YYYY-MM-DD' string via the local components the driver set, then compare
// strings (lexicographic order is chronological for ISO dates).
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

// --- copy composition ---
// hourLabel/rangeLabel live in ./labels.js (shared with the #6d detector).

const WEEKDAY_FMT = new Intl.DateTimeFormat('en-US', { weekday: 'short', timeZone: 'UTC' });
function weekdayLabel(dateString) {
  const [y, m, d] = dateString.split('-').map(Number);
  return WEEKDAY_FMT.format(new Date(Date.UTC(y, m - 1, d)));
}

const capitalize = (rating) => rating.charAt(0).toUpperCase() + rating.slice(1);

// Compose the single digest push, or null when nothing qualifies.
//
// `window` is input-only — evaluateAll results echo activityId/label/
// displayMetrics but NOT window — so the snapshot's activities array stays in
// scope beside the results and nocturnal detection (wrapped window) reads from
// it (audit 2026-07-16).
function composeDigest(results, snapshotActivities, forecastStart, timezone) {
  const windowById = new Map(snapshotActivities.map((a) => [a.id, a.window]));
  const startMs = Date.parse(forecastStart);
  const localHourAt = (index) => localHour(startMs + index * MS_PER_HOUR, timezone);

  // Today section: each Activity whose days[0] qualifies. endIndex is EXCLUSIVE
  // ([startIndex, endIndex)) so the label at endIndex is the window's end
  // boundary — a 7→10 window is "7–10am", ending as 10am begins.
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

  // Week-ahead section: earliest Perfect day per Activity in buckets 2 through
  // days.length − 1. NEVER a literal 2–6 (audit 2026-07-16): days.length is
  // per-activity — a diurnal horizon is usually 8 buckets (the partial tail day
  // must be able to surface), a nocturnal one can be 6. Bucket 1 is deliberately
  // absent everywhere in the digest: tomorrow's Perfect belongs to the #6d
  // detector; tomorrow's Good surfaces in-app only (ADR-0006 trade-off).
  const weekLines = [];
  for (const result of results) {
    const hit = result.days.slice(2).find((d) => d.rating === 'perfect');
    if (!hit) continue;
    weekLines.push(`${weekdayLabel(bucketDate(forecastStart, timezone, hit.dayIndex))}: Perfect for ${result.label}`);
  }

  const lines = [...todayLines, ...weekLines];
  if (lines.length === 0) return null; // both sections empty → no push
  return { title: 'Daily Digest', body: lines.join('\n'), payload: { type: 'dailyDigest' } };
}

function createDailyDigestJob({ db, getWeather, evaluateAll, sendPush, now = Date.now }) {
  async function runDigestPass() {
    const { rows } = await db.query(
      'SELECT device_id, apns_token, home_lat, home_lon, timezone, activities, last_digest_date FROM devices'
    );

    for (const device of rows) {
      try {
        const nowMs = now();
        const hour = localHour(nowMs, device.timezone);
        if (hour < DIGEST_START_HOUR || hour >= DIGEST_END_HOUR) continue;

        const today = localDay(nowMs, device.timezone);
        const sent = markerDateString(device.last_digest_date);
        if (sent !== null && sent >= today) continue; // one push per device per day

        // Hours come back localDay/localHour-tagged from getWeather — exactly
        // what evaluateAll needs. A dormant (empty) snapshot evaluates to []
        // and composes nothing.
        const { forecastStart, timezone, hours } = await getWeather(device.home_lat, device.home_lon);
        const results = evaluateAll(hours, device.activities);
        const message = composeDigest(results, device.activities, forecastStart, timezone);
        if (!message) continue;

        try {
          await sendPush(device.apns_token, message);
        } catch (err) {
          if (err instanceof StaleTokenError) {
            // Dead tokens must not accumulate (spec §5).
            await db.query('DELETE FROM devices WHERE device_id = $1', [device.device_id]);
            continue;
          }
          throw err;
        }

        // Marker set only AFTER a successful send, cast in SQL from the
        // 'YYYY-MM-DD' string — no JS Date comparison anywhere on this path.
        await db.query('UPDATE devices SET last_digest_date = $2::date WHERE device_id = $1', [
          device.device_id,
          today,
        ]);
      } catch (err) {
        // Per-device isolation: one failure never stops the pass.
        console.error(`daily digest: device ${device.device_id} failed`, err);
      }
    }
  }

  return { runDigestPass };
}

module.exports = { createDailyDigestJob, composeDigest, markerDateString };
