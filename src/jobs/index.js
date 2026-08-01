// In-process job scheduler (#6c spec §7, #6d spec §2, ADR-0006). node-cron on
// the always-on single-replica web service — 2+ replicas would duplicate
// pushes. Started by app.js AFTER listen, never at require time. One hourly
// tick runs both passes sequentially: the digest first, then the detector —
// they share the 60-min weather cache, so both passes in the same hour cost
// one provider call per location.

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
    // A pass-level failure (e.g. db down) is logged, never thrown — the next
    // hourly tick retries; per-device isolation lives inside each pass. Each
    // pass fails independently: a digest wipeout must not skip the detector.
    await digest.runDigestPass().catch((err) => console.error('daily digest pass failed', err));
    await detector.runDetectorPass().catch((err) => console.error('perfect-window detector pass failed', err));
  });
}

module.exports = { startJobs };
