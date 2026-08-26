// Time-boundary module (ADR-0003): the locale/time sibling of the weather
// adapter. Tags each hour with an internal `localDay` key (UTC forecastStart +
// IANA zone) so the decision engine buckets by local calendar day without
// reasoning about timezones/DST itself. `localDay` is internal, never on the wire.

const MS_PER_HOUR = 3600 * 1000;

// One formatter per zone; reuse keeps the hot loop cheap.
const formatterCache = new Map();
function dayFormatter(timezone) {
  let fmt = formatterCache.get(timezone);
  if (!fmt) {
    // en-CA renders YYYY-MM-DD; timeZone keeps it DST-correct.
    fmt = new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    });
    formatterCache.set(timezone, fmt);
  }
  return fmt;
}

// Landmine (ADR-0003): the local day MUST derive from a UTC instant — a bare
// `new Date("2026-06-19T12:00:00")` parses in the SERVER's zone, silently
// shifting every bucket on a non-UTC host. The `Z`-suffixed `forecastStart`
// gives the unambiguous instant; Intl resolves the calendar day from there.
function localDay(instantMs, timezone) {
  return dayFormatter(timezone).format(new Date(instantMs));
}

// Hour-of-day (0..23) in the location zone at a UTC instant — localDay's
// sibling, used by the window filter + night-stitch (ADR-0003/0005). Same
// UTC-instant discipline; h23 so local midnight reads 0, not 24.
const hourFormatterCache = new Map();
function hourFormatter(timezone) {
  let fmt = hourFormatterCache.get(timezone);
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', { timeZone: timezone, hour: '2-digit', hourCycle: 'h23' });
    hourFormatterCache.set(timezone, fmt);
  }
  return fmt;
}
function localHour(instantMs, timezone) {
  const part = hourFormatter(timezone).formatToParts(new Date(instantMs)).find((p) => p.type === 'hour');
  return Number(part.value);
}

// Offset (ms) of the zone from UTC at an instant: format in the zone, read
// the wall components back, and diff — DST-correct without a library.
function zoneOffsetMsAt(instantMs, timezone) {
  const fmt = new Intl.DateTimeFormat('en-US', {
    timeZone: timezone,
    hourCycle: 'h23',
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const p = Object.fromEntries(fmt.formatToParts(new Date(instantMs)).map((x) => [x.type, x.value]));
  const wallAsUtc = Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute, +p.second);
  return wallAsUtc - instantMs;
}

// Inverse of localDay: a LOCAL wall-time in `timezone` -> UTC-Z instant
// (ADR-0003). Meteosource's timezone=auto returns bare local timestamps;
// this reconciles them to the UTC-Z `forecastStart` contract.
function zonedWallTimeToUtcIso(wallTime, timezone) {
  // An already-zoned timestamp (Z or +hh:mm) is an absolute instant — trust it.
  if (/(Z|[+-]\d{2}:\d{2})$/.test(wallTime)) {
    return new Date(wallTime).toISOString().replace(/\.\d{3}Z$/, 'Z');
  }
  // Treat wall components as UTC for a provisional instant, then correct by
  // the zone's offset — a second pass handles the rare DST case where that
  // offset shifts between the provisional and true instant.
  const provisional = Date.parse(`${wallTime}Z`);
  let utcMs = provisional - zoneOffsetMsAt(provisional, timezone);
  utcMs = provisional - zoneOffsetMsAt(utcMs, timezone);
  return new Date(utcMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

// The calendar date a bucket's dayIndex refers to: date-of-day-0 + dayIndex
// days, as 'YYYY-MM-DD'. dayIndex 0 is today (for a nocturnal activity, the
// EVENING's day — night-stitch convention), so plain arithmetic on the day-0
// string is exact. Shared by the digest's week-ahead labels and the
// detector's bucket_date dedup key — do not hand-roll a sibling.
function bucketDate(forecastStart, timezone, dayIndex) {
  const day0 = localDay(Date.parse(forecastStart), timezone);
  const [y, m, d] = day0.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + dayIndex)).toISOString().slice(0, 10);
}

function tagLocalDays(hours, forecastStart, timezone) {
  const startMs = Date.parse(forecastStart);
  return hours.map((hour, index) => {
    const instantMs = startMs + index * MS_PER_HOUR;
    return {
      ...hour,
      localDay: localDay(instantMs, timezone),
      localHour: localHour(instantMs, timezone),
    };
  });
}

module.exports = { tagLocalDays, localDay, localHour, zonedWallTimeToUtcIso, bucketDate };
