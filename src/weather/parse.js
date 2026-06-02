function parseWeather(rawResponse, adapter) {
  const phase = adapter.extractMoonPhase(rawResponse);
  const moon = phase ? [phase] : [];

  const allHours = adapter.extractHours(rawResponse);
  const forecastStart = adapter.forecastStart(allHours[0]);

  const hours = allHours.slice(0, 24).map((row) => ({
    hour:         adapter.hour(row),
    temp:         adapter.temp(row),
    humidity:     adapter.humidity(row),
    windSpeed:    adapter.windSpeed(row),
    rainFall:     adapter.rainFall(row),
    cloudCover:   adapter.cloudCover(row),
    visibility:   adapter.visibility(row),
    moon,
    uV:           adapter.uV(row),
    dustAlert:    adapter.dustAlert(row),
    // PENDING Issue #7 — wire real marine data from Meteosource adapter
    // douglasScale, swellHeight, swellLength, seaWarning are placeholder values.
    // Fishing activity ratings will trivially pass these thresholds until real data is integrated.
    darkness:     0,       // PENDING: astronomy data source (not Meteosource)
    douglasScale: 0,       // PENDING Issue #7: Meteosource marine data
    swellHeight:  0,       // PENDING Issue #7: Meteosource marine data
    swellLength:  0,       // PENDING Issue #7: Meteosource marine data
    tide:         0,       // DEFERRED: requires separate tidal API — no data source identified
    seaWarning:   false,   // PENDING: UAE maritime authority API — not Meteosource
  }));

  return { forecastStart, hours };
}

module.exports = { parseWeather };
