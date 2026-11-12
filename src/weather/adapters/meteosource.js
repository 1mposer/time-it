// Meteosource field extractors — swap this file to change weather provider.

const { UpstreamError } = require('../UpstreamError');
const { zonedWallTimeToUtcIso } = require('../timeBoundary');

const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  // Astro lives under daily.data[].astro (there is no top-level astro section).
  // Returns { 'YYYY-MM-DD': 'new moon', ... } keyed on the location-local day
  // so parse.js can spread each day's phase across its hours. Meteosource
  // quantises to four phases (new_moon / first_quarter / full_moon /
  // last_quarter); the snake_case is rendered as a plain label.
  moonPhaseByDay:   (res) => {
    const byDay = {};
    for (const day of res.daily?.data ?? []) {
      const phase = day?.astro?.moon?.phase;
      if (typeof day?.day === 'string' && typeof phase === 'string' && phase.length > 0) {
        byDay[day.day.slice(0, 10)] = phase.replace(/_/g, ' ');
      }
    }
    return byDay;
  },
  // Sunrise/sunset per location-local day from daily.data[].astro.sun (local
  // wall-time under timezone=auto, same as the hourly `date`) — the uV
  // extractor's daylight test. A day without a sun object is left out.
  sunByDay:         (res) => {
    const byDay = {};
    for (const day of res.daily?.data ?? []) {
      const sun = day?.astro?.sun;
      if (typeof day?.day === 'string' && sun && typeof sun === 'object') {
        byDay[day.day.slice(0, 10)] = {
          rise: sun.rise ?? null,
          set: sun.set ?? null,
          alwaysUp: sun.always_up === true,
          alwaysDown: sun.always_down === true,
        };
      }
    }
    return byDay;
  },
  // The hourly row's location-local calendar date (timezone=auto serves local
  // wall-time) — the join key against moonPhaseByDay.
  localDate:        (h) => (typeof h?.date === 'string' ? h.date.slice(0, 10) : null),
  // Location IANA zone, exposed top-level under timezone=auto.
  timezone:         (res) => res.timezone,
  // The provider serves local wall-time under timezone=auto — convert to the
  // UTC-Z contract. A malformed date is a malformed payload (UpstreamError →
  // 502), never a generic 500.
  forecastStart:    (firstRow, timezone) => {
    if (typeof firstRow?.date !== 'string' || !firstRow.date.includes('T')) {
      throw new UpstreamError(`Expected ISO 8601 date with 'T' separator, got: ${firstRow?.date}`);
    }
    return zonedWallTimeToUtcIso(firstRow.date, timezone);
  },
  temp:       (h) => h.temperature,
  humidity:   (h) => h.humidity,
  windSpeed:  (h) => h.wind?.speed ?? null,
  rainFall:   (h) => h.precipitation?.total ?? null,
  cloudCover: (h) => h.cloud_cover?.total ?? null,
  visibility: (h) => h.visibility,
  // uv_index is null at night (genuinely 0 — kept as 0), but the provider also
  // stops sending it past its horizon (~day 5): a missing reading during full
  // daylight is UNKNOWN → null, which fails a threshold like the nullable trio
  // instead of passing any max as a fake 0 (the build-9 false-Perfect). `sun`
  // is the hour's day entry from sunByDay; no sun data → unknown → null.
  uV:         (h, sun) => {
    if (typeof h.uv_index === 'number') return h.uv_index;
    if (!sun) return null;
    if (sun.alwaysDown) return 0;
    if (sun.alwaysUp) return null;
    const instant = (s) => (typeof s === 'string' ? Date.parse(`${s.slice(0, 19)}Z`) : NaN);
    const start = instant(h.date);
    const rise = instant(sun.rise);
    const set = instant(sun.set);
    if ([start, rise, set].some(Number.isNaN)) return null;
    // Only an hour wholly inside sun-up is daylight: the twilight hours either
    // side read ~0 UV anyway (the provider's own dawn values are ~0.1).
    const fullDaylight = start >= rise && start + 3600_000 <= set;
    return fullDaylight ? null : 0;
  },
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
