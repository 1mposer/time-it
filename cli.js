require('dotenv').config();
const { fetchWeather } = require('./src/weather/fetch');
const { parseWeather } = require('./src/weather/parse');
const { meteosourceAdapter } = require('./src/weather/adapters/meteosource');
const { evaluate } = require('./src/decision/decision_engine');

// Activities are caller-supplied now (ADR-0005); the curated backend list is gone.
// This dev CLI carries one inline sample profile just to preview a live evaluation.
const PREVIEW_ACTIVITY = {
  id: 'volleyball',
  label: 'Volleyball',
  displayMetrics: ['temp', 'windSpeed'],
  thresholds: {
    temp: { min: 15, max: 35, required: true },
    windSpeed: { max: 15, required: false },
  },
};

async function main() {
  const activity = PREVIEW_ACTIVITY;

  const params = {
    lat: '25.1627',
    lon: '55.2077',
    timezone: 'auto',  // the paid point endpoint exposes the location IANA zone only under auto (ADR-0003)
    language: 'en',
    sections: 'all',
    units: 'metric',
    key: process.env.API_KEY,
  };

  const raw = await fetchWeather(params);
  const { forecastStart, hours } = parseWeather(raw, meteosourceAdapter);

  const window = evaluate(hours, {
    activityId: activity.id,
    thresholds: activity.thresholds,
  });

  console.log(JSON.stringify({ forecastStart, ...window }, null, 2));
}

main().catch((err) => console.error(err.message));
