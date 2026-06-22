const { UpstreamError } = require('./UpstreamError');

// 7-day rolling horizon ceiling (ADR-0003). 168 = 7 x 24 is a CEILING, not a
// fixed count: the provider serves however many clean hourly entries it returns
// (Meteosource flexi ~161-168), capped here. We never fabricate hours to a target.
const FORECAST_HOURS = 168;

function parseWeather(rawResponse, adapter) {
  const allHours = adapter.extractHours(rawResponse);
  if (!allHours || allHours.length === 0) {
    throw new UpstreamError('Empty forecast from provider');
  }

  const phase = adapter.extractMoonPhase(rawResponse);
  const moon = phase ? [phase] : [];
  const timezone = adapter.timezone(rawResponse);
  const forecastStart = adapter.forecastStart(allHours[0], timezone);

  const hours = allHours.slice(0, FORECAST_HOURS).map((row) => ({
    temp:         adapter.temp(row),
    humidity:     adapter.humidity(row),
    windSpeed:    adapter.windSpeed(row),
    rainFall:     adapter.rainFall(row),
    cloudCover:   adapter.cloudCover(row),
    visibility:   adapter.visibility(row),
    moon:         [...moon],
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

  return { forecastStart, timezone, hours };
}

module.exports = { parseWeather, FORECAST_HOURS };
