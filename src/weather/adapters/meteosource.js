const { UpstreamError } = require('../UpstreamError');
const { zonedWallTimeToUtcIso } = require('../timeBoundary');

const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
  // Location IANA zone, exposed top-level under timezone=auto (ADR-0003).
  timezone:         (res) => res.timezone,
  // Under timezone=auto the provider serves LOCAL wall-time with no designator;
  // convert to the unified UTC-Z forecastStart contract using the location zone.
  // Shape-guard first: a malformed/missing provider date is a malformed PAYLOAD
  // (502, not 500). Without this it reaches Intl(new Date(NaN)) → RangeError →
  // the route's generic-500 branch, breaking the typed-error contract (ADR-0004).
  // Guarding here also protects downstream tagLocalDays, which trusts forecastStart.
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
  // Meteosource returns uv_index: null at night (no UV after dark). Default to 0
  // — nighttime UV genuinely IS 0, so this keeps uV a non-nullable number on the
  // wire (per the contract) rather than passing a null the way the wind/rain/cloud
  // trio does (where 0 would be a false reading, so those stay nullable).
  uV:         (h) => h.uv_index ?? 0,
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
