const meteosourceAdapter = {
  extractHours:     (res) => res.hourly.data,
  extractMoonPhase: (res) => res.astro?.data?.[0]?.moon_phase,
  forecastStart:    (firstRow) => firstRow.date,
  hour:       (h) => parseInt(h.date.split("T")[1].split(":")[0], 10),
  temp:       (h) => h.temperature,
  humidity:   (h) => h.humidity,
  windSpeed:  (h) => h.wind.speed,
  rainFall:   (h) => h.precipitation.total,
  cloudCover: (h) => h.cloud_cover?.total ?? h.cloud_cover,
  visibility: (h) => h.visibility,
  uV:         (h) => h.uv_index,
  dustAlert:  (h) => typeof h.weather === "string" && h.weather.includes("sandstorm"),
};

module.exports = { meteosourceAdapter };
