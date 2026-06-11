const { fetchWeather } = require('./fetch');
const { parseWeather } = require('./parse');
const { meteosourceAdapter } = require('./adapters/meteosource');

async function getWeather(lat, lon) {
  if (!process.env.API_KEY) {
    throw new Error('API_KEY environment variable is not set');
  }

  const params = {
    lat,
    lon,
    timezone: 'UTC',
    language: 'en',
    sections: 'all',
    units: 'metric',
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  return parseWeather(raw, meteosourceAdapter);
}

module.exports = { getWeather };
