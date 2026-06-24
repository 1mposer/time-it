// Time-boundary module — the locale/time sibling of the provider adapter
// (ADR-0003). It normalises one thing only: the forecast location's calendar
// day. Given the UTC `forecastStart` instant and the location's IANA zone, it
// tags each hour with an internal `localDay` key so the decision engine can
// group results by local calendar day WITHOUT itself reasoning about
// timezones, offsets, or DST. `localDay` is internal — never on the wire.

const MS_PER_HOUR = 3600 * 1000;

// One formatter per zone is enough; reuse keeps the hot loop cheap.
const formatterCache = new Map();
function dayFormatter(timezone) {
  let fmt = formatterCache.get(timezone);
  if (!fmt) {
    // en-CA renders YYYY-MM-DD; timeZone makes it DST-correct for any real zone.
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

// Landmine (ADR-0003): the local day MUST be derived from a UTC instant. A bare
// `new Date("2026-06-19T12:00:00")` would parse in the *server's* local zone and
// silently shift every bucket on a non-UTC host. `forecastStart` is Z-suffixed,
// so Date.parse gives the unambiguous UTC instant; we add whole UTC hours and
// let Intl resolve the calendar day in the forecast location's zone.
function localDay(instantMs, timezone) {
  return dayFormatter(timezone).format(new Date(instantMs));
}

// The hour-of-day (0..23) in the location zone at a UTC instant — the sibling of
// localDay used by the time-of-day window + night-stitch (ADR-0005/0003). Same
// UTC-instant discipline as localDay; h23 cycle so local midnight reads 0, not 24.
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

// The offset (ms) the zone is from UTC at a given instant. Found by formatting
// the instant in the zone, reading the wall components back, and diffing — the
// standard library-free, DST-correct technique.
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

// Inverse of localDay: a LOCAL wall-time in `timezone` -> the UTC-Z instant.
// (ADR-0003 fetch wrinkle.) Meteosource under timezone=auto returns bare local
// timestamps; this reconciles them to the UTC-Z `forecastStart` contract.
function zonedWallTimeToUtcIso(wallTime, timezone) {
  // An already-zoned timestamp (Z or +hh:mm) is an absolute instant — trust it.
  if (/(Z|[+-]\d{2}:\d{2})$/.test(wallTime)) {
    return new Date(wallTime).toISOString().replace(/\.\d{3}Z$/, 'Z');
  }
  // Treat the wall components as if UTC to get a provisional instant, then
  // correct by the zone's offset. A second pass pins it across the rare case
  // where the offset differs between the provisional and the true instant (DST).
  const provisional = Date.parse(`${wallTime}Z`);
  let utcMs = provisional - zoneOffsetMsAt(provisional, timezone);
  utcMs = provisional - zoneOffsetMsAt(utcMs, timezone);
  return new Date(utcMs).toISOString().replace(/\.\d{3}Z$/, 'Z');
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

module.exports = { tagLocalDays, localDay, localHour, zonedWallTimeToUtcIso };
