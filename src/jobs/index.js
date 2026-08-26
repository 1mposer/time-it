// In-process job scheduler (ADR-0006): one hourly node-cron tick runs the digest pass
// then the detector pass, each with its own catch so one failing never skips
// the other. Single-replica only — more would duplicate pushes. Started by
// app.js after listen.

const cron = require('node-cron');
const db = require('../db');
const { getCachedWeather } = require('../services/weatherCache');
const { evaluateAll } = require('../decision');
const { sendPush } = require('../notifications/apns');
const { createDailyDigestJob } = require('./dailyDigest');
const { createPerfectWindowDetectorJob } = require('./perfectWindowDetector');

function startJobs({ schedule = cron.schedule } = {}) {
  const deps = { db, getWeather: getCachedWeather, evaluateAll, sendPush };
  const digest = createDailyDigestJob(deps);
  const detector = createPerfectWindowDetectorJob(deps);
  schedule('0 * * * *', async () => {
    await digest.runDigestPass().catch((err) => console.error('daily digest pass failed', err));
    await detector.runDetectorPass().catch((err) => console.error('perfect-window detector pass failed', err));
  });
}

module.exports = { startJobs };
