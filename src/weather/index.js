const { fetchWeather } = require('./fetch');
const { parseWeather } = require('./parse');
const { tagLocalDays } = require('./timeBoundary');
const { meteosourceAdapter } = require('./adapters/meteosource');

async function getWeather(lat, lon) {
  if (!process.env.API_KEY) {
    throw new Error('API_KEY environment variable is not set');
  }

  const params = {
    lat,
    lon,
    // timezone=auto is the only mode that exposes the location IANA zone (ADR-0003);
    // it returns LOCAL timestamps, reconciled to UTC-Z in the adapter.
    timezone: 'auto',
    language: 'en',
    sections: 'all',
    units: 'metric',
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  const { forecastStart, timezone, hours } = parseWeather(raw, meteosourceAdapter);
  // Tag each hour with its forecast-location calendar day so the decision engine
  // can bucket by day without reasoning about timezones. localDay is internal —
  // the route strips it before the wire.
  return { forecastStart, timezone, hours: tagLocalDays(hours, forecastStart, timezone) };
}

module.exports = { getWeather };
