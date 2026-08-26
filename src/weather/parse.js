const { UpstreamError } = require('./UpstreamError');

const FORECAST_HOURS = 168; // ceiling, not a fixed count — fewer passes through

// Normalises the raw provider response to { forecastStart, timezone, hours }.
// Hours are never fabricated. darkness/douglasScale/swellHeight/swellLength/
// tide/seaWarning are hardcoded placeholders pending real data sources.
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
    darkness:     0,
    douglasScale: 0,
    swellHeight:  0,
    swellLength:  0,
    tide:         0,
    seaWarning:   false,
  }));

  return { forecastStart, timezone, hours };
}

module.exports = { parseWeather, FORECAST_HOURS };
