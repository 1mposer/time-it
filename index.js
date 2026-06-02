require('dotenv').config();
const { fetchWeather } = require('./src/weather/fetch');
const { parseWeather } = require('./src/weather/parse');
const { meteosourceAdapter } = require('./src/weather/adapters/meteosource');
const { evaluate } = require('./src/decision/decision_engine');

const sampleUserPrefs = {
  activityId: "volleyball",
  thresholds: {
    temp:      { min: 15, max: 35, required: true },
    humidity:  { max: 60,          required: true },
    windSpeed: { max: 15,          required: false },
    uV:        { max: 6,           required: false },
  },
};

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
  const { hours } = parseWeather(raw, meteosourceAdapter);

  const window = evaluate(hours, sampleUserPrefs);
  console.log(JSON.stringify(window, null, 2));
}

main().catch((err) => console.error(err.message));
