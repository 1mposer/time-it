require('dotenv').config();
const { fetchWeather } = require('./src/weather/fetch');
const { parseWeather } = require('./src/weather/parse');
const { meteosourceAdapter } = require('./src/weather/adapters/meteosource');

async function main() {
  const params = {
    lat: "25.1627",
    lon: "55.2077",
    timezone: "UTC",
    language: "en",
    sections: "all",
    units: "metric",
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  const hours = parseWeather(raw, meteosourceAdapter);
  console.log(JSON.stringify(hours, null, 2));
}

main().catch((err) => console.error(err.message));
