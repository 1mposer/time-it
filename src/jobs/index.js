// In-process job scheduler (ADR-0006): one hourly node-cron tick runs the digest pass
// then the detector pass, each with its own catch so one failing never skips
// the other. Single-replica only — more would duplicate pushes. Started by
// app.js after listen.

const cron = require('node-cron');
const db = require('../db');
const { getCachedWeather } = require('../services/weatherCache');
const { evaluateAll } = require('../decision/evaluateAll');
const { sendPush } = require('../notifications/apns');
const { createDailyDigestJob } = require('./dailyDigest');
const { createPerfectWindowDetectorJob } = require('./perfectWindowDetector');

// The jobs read weather through the shared cache as origin 'job': never
// counted against the outside provider budget and never served a stale
// forecast (a push is only ever built from fresh data).
function jobWeather(cache) {
  return (lat, lon) => cache(lat, lon, { origin: 'job' });
}

function startJobs({
  schedule = cron.schedule,
  weatherCache = getCachedWeather,
  jobFactories = { createDailyDigestJob, createPerfectWindowDetectorJob },
} = {}) {
  const deps = { db, getWeather: jobWeather(weatherCache), evaluateAll, sendPush };
  const digest = jobFactories.createDailyDigestJob(deps);
  const detector = jobFactories.createPerfectWindowDetectorJob(deps);
  schedule('0 * * * *', async () => {
    await digest.runDigestPass().catch((err) => console.error('daily digest pass failed', err));
    await detector.runDetectorPass().catch((err) => console.error('perfect-window detector pass failed', err));
  });
}

module.exports = { startJobs, jobWeather };
