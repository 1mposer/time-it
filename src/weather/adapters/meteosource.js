const { zonedWallTimeToUtcIso } = require('../timeBoundary');

const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
  // Location IANA zone, exposed top-level under timezone=auto (ADR-0003).
  timezone:         (res) => res.timezone,
  // Under timezone=auto the provider serves LOCAL wall-time with no designator;
  // convert to the unified UTC-Z forecastStart contract using the location zone.
  forecastStart:    (firstRow, timezone) => zonedWallTimeToUtcIso(firstRow.date, timezone),
  temp:       (h) => h.temperature,
  humidity:   (h) => h.humidity,
  windSpeed:  (h) => h.wind?.speed ?? null,
  rainFall:   (h) => h.precipitation?.total ?? null,
  cloudCover: (h) => h.cloud_cover?.total ?? null,
  visibility: (h) => h.visibility,
  uV:         (h) => h.uv_index,
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
