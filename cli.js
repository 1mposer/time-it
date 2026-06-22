require('dotenv').config();
const { fetchWeather } = require('./src/weather/fetch');
const { parseWeather } = require('./src/weather/parse');
const { meteosourceAdapter } = require('./src/weather/adapters/meteosource');
const { evaluate } = require('./src/decision/decision_engine');
const { activities } = require('./src/activities');

const PREVIEW_ACTIVITY_ID = 'volleyball';

async function main() {
  const activity = activities.find((a) => a.id === PREVIEW_ACTIVITY_ID);
  if (!activity) {
    throw new Error(`Activity "${PREVIEW_ACTIVITY_ID}" not found in src/activities/index.js`);
  }

  const params = {
    lat: '25.1627',
    lon: '55.2077',
    timezone: 'auto',  // flexi exposes the location IANA zone only under auto (ADR-0003)
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
