// Meteosource field extractors — swap this file to change weather provider.

const { UpstreamError } = require('../UpstreamError');
const { zonedWallTimeToUtcIso } = require('../timeBoundary');

const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
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
  // null at night — defaulted to 0 (nighttime UV genuinely is 0), so uV stays
  // non-null on the wire unlike the nullable wind/rain/cloud trio.
  uV:         (h) => h.uv_index ?? 0,
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
