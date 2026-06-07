const { fetchWeather } = require('./fetch');
const { parseWeather } = require('./parse');
const { meteosourceAdapter } = require('./adapters/meteosource');

async function getWeather(lat, lon, timezone = "UTC") {
  const params = {
    lat,
    lon,
    timezone,
    language: "en",
    sections: "all",
    units: "metric",
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  return parseWeather(raw, meteosourceAdapter);
}

module.exports = { getWeather };
