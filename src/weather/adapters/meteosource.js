const { UpstreamError } = require('../UpstreamError');

const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
  forecastStart:    (firstRow) => firstRow.date.endsWith('Z') ? firstRow.date : `${firstRow.date}Z`,
  hour: (h) => {
    if (typeof h.date !== 'string' || !h.date.includes('T')) {
      throw new UpstreamError(`Expected ISO 8601 date with 'T' separator, got: ${h.date}`);
    }
    return parseInt(h.date.split('T')[1].split(':')[0], 10);
  },
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
