// In-process job scheduler (#6c spec §7, ADR-0006). node-cron on the always-on
// single-replica web service — 2+ replicas would duplicate pushes. Started by
// app.js AFTER listen, never at require time. The hourly pass is the digest's
// catch-up selector's heartbeat; #6d's detector will join the same schedule.

const cron = require('node-cron');
const db = require('../db');
const { getCachedWeather } = require('../services/weatherCache');
const { evaluateAll } = require('../decision');
const { sendPush } = require('../notifications/apns');
const { createDailyDigestJob } = require('./dailyDigest');

function startJobs({ schedule = cron.schedule } = {}) {
  const digest = createDailyDigestJob({ db, getWeather: getCachedWeather, evaluateAll, sendPush });
  schedule('0 * * * *', () => {
    // A pass-level failure (e.g. db down) is logged, never thrown — the next
    // hourly tick retries; per-device isolation lives inside the pass.
    digest.runDigestPass().catch((err) => console.error('daily digest pass failed', err));
  });
}

module.exports = { startJobs };
