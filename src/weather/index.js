// Public weather entry: getWeather(lat, lon) → { forecastStart, timezone,
// hours }, each hour tagged with internal localDay/localHour keys.

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
    // The only mode that exposes the location IANA zone; returns LOCAL
    // timestamps, reconciled to UTC-Z in the adapter.
    timezone: 'auto',
    language: 'en',
    sections: 'all',
    units: 'metric',
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  const { forecastStart, timezone, hours } = parseWeather(raw, meteosourceAdapter);
  return { forecastStart, timezone, hours: tagLocalDays(hours, forecastStart, timezone) };
}

module.exports = { getWeather };
