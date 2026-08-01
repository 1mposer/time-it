const test = require('node:test');
const assert = require('node:assert/strict');

const { createDailyDigestJob, markerDateString } = require('../../src/jobs/dailyDigest');
const { StaleTokenError } = require('../../src/notifications/apns');
const { bucketDate } = require('../../src/weather/timeBoundary');

// ---------------------------------------------------------------------------
// Fakes. The db fake returns rows in the REAL pg driver shape — in particular
// last_digest_date as a JS Date at local midnight (pg does new Date(y, m-1, d)
// for DATE columns). A string-returning fake would mask the §7 type trap.
// ---------------------------------------------------------------------------

function makeJobDb(rows) {
  const deleted = [];
  const markers = [];
  return {
    deleted,
    markers,
    query: async (text, params) => {
      if (text.startsWith('SELECT')) return { rows };
      if (text.startsWith('DELETE FROM devices')) { deleted.push(params[0]); return { rows: [] }; }
      if (text.startsWith('UPDATE devices SET last_digest_date')) {
        markers.push({ deviceId: params[0], date: params[1] });
        return { rows: [] };
      }
      throw new Error(`fake db: unexpected query: ${text}`);
    },
  };
}

function makeDevice(overrides = {}) {
  return {
    device_id: 'device-1',
    apns_token: 'a1b2c3',
    home_lat: 25.16,
    home_lon: 55.21,
    timezone: 'Asia/Dubai',
    activities: [{ id: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
      thresholds: { temp: { min: 15, max: 35, required: true } } }],
    last_digest_date: null,
    ...overrides,
  };
}

// forecastStart 02:00Z = 06:00 Asia/Dubai — index i sits at local hour 6 + i.
const FORECAST_START = '2026-08-01T02:00:00Z';
const DUBAI = 'Asia/Dubai';
const fakeWeather = (forecastStart = FORECAST_START, timezone = DUBAI) =>
  async () => ({ forecastStart, timezone, hours: [] });

// evaluateAll fake: returns canned results, echoing the engine's contract shape.
const cannedResults = (results) => () => results;

function makeSentLog() {
  const sent = [];
  return { sent, sendPush: async (token, message) => { sent.push({ token, message }); } };
}

function runPass({ rows, results, nowIso, forecastStart, timezone, sendPush }) {
  const db = makeJobDb(rows);
  const log = makeSentLog();
  const job = createDailyDigestJob({
    db,
    getWeather: fakeWeather(forecastStart, timezone),
    evaluateAll: typeof results === 'function' ? results : cannedResults(results),
    sendPush: sendPush || log.sendPush,
    now: () => Date.parse(nowIso),
  });
  return job.runDigestPass().then(() => ({ db, sent: log.sent }));
}

const PERFECT_DAY0 = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
  days: [{ dayIndex: 0, rating: 'perfect', startIndex: 1, endIndex: 4, duration: 3 }] }];

// --- local-6am selection across zones ---
test('devices in different zones fire on different passes (Dubai vs Toronto)', async () => {
  const rows = [
    makeDevice({ device_id: 'dubai', timezone: 'Asia/Dubai' }),
    makeDevice({ device_id: 'toronto', timezone: 'America/Toronto' }),
  ];
  // 02:30Z: Dubai 06:30 (eligible), Toronto 22:30 previous day (not eligible).
  let { sent } = await runPass({ rows, results: PERFECT_DAY0, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, rows[0].apns_token);

  // 10:30Z: Dubai 14:30 (past noon — skip), Toronto 06:30 (eligible).
  const rows2 = [
    makeDevice({ device_id: 'dubai', timezone: 'Asia/Dubai', apns_token: 'dubai-token' }),
    makeDevice({ device_id: 'toronto', timezone: 'America/Toronto', apns_token: 'toronto-token' }),
  ];
  ({ sent } = await runPass({ rows: rows2, results: PERFECT_DAY0, nowIso: '2026-08-01T10:30:00Z' }));
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, 'toronto-token');
});

// --- catch-up band (6 <= h < 12, audit 2026-07-16) ---
test('a missed 6am tick is caught up once at 7–11 local; past noon is skipped', async () => {
  const rows = [makeDevice()];
  // 05:30Z = 09:30 Dubai — inside the catch-up band.
  let result = await runPass({ rows, results: PERFECT_DAY0, nowIso: '2026-08-01T05:30:00Z' });
  assert.equal(result.sent.length, 1, 'catch-up at 9:30 local delivers');
  assert.deepStrictEqual(result.db.markers, [{ deviceId: 'device-1', date: '2026-08-01' }]);

  // 08:30Z = 12:30 Dubai — past noon, a "morning" digest is worse than none.
  result = await runPass({ rows: [makeDevice()], results: PERFECT_DAY0, nowIso: '2026-08-01T08:30:00Z' });
  assert.equal(result.sent.length, 0);

  // 01:30Z = 05:30 Dubai — before the band.
  result = await runPass({ rows: [makeDevice()], results: PERFECT_DAY0, nowIso: '2026-08-01T01:30:00Z' });
  assert.equal(result.sent.length, 0);
});

// --- sent-today suppression with the REAL driver Date shape (§7 type trap) ---
test('a device already sent today (Date-object marker) is suppressed; yesterday is not', async () => {
  // pg driver shape: DATE 2026-08-01 -> new Date(2026, 7, 1) at LOCAL midnight.
  const sentToday = makeDevice({ last_digest_date: new Date(2026, 7, 1) });
  let result = await runPass({ rows: [sentToday], results: PERFECT_DAY0, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(result.sent.length, 0, 'marker == local today → one push per device per day');

  const sentYesterday = makeDevice({ last_digest_date: new Date(2026, 6, 31) });
  result = await runPass({ rows: [sentYesterday], results: PERFECT_DAY0, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(result.sent.length, 1, 'marker < local today → sends');
  assert.deepStrictEqual(result.db.markers, [{ deviceId: 'device-1', date: '2026-08-01' }]);
});

test('markerDateString normalises the driver Date to YYYY-MM-DD (the naive < comparison is always false)', () => {
  const marker = new Date(2026, 7, 1);
  assert.equal(marker < '2026-08-02', false, 'the trap: Date < string coerces to NaN');
  assert.equal(markerDateString(marker), '2026-08-01');
  assert.equal(markerDateString(null), null);
  assert.equal(markerDateString('2026-08-01'), '2026-08-01');
});

// --- per-device error isolation ---
test('one device failing never stops the pass', async () => {
  const rows = [
    makeDevice({ device_id: 'broken', home_lat: 0, home_lon: 0 }),
    makeDevice({ device_id: 'healthy', apns_token: 'healthy-token' }),
  ];
  const db = makeJobDb(rows);
  const { sent, sendPush } = makeSentLog();
  const job = createDailyDigestJob({
    db,
    getWeather: async (lat) => {
      if (lat === 0) throw new Error('provider exploded');
      return { forecastStart: FORECAST_START, timezone: DUBAI, hours: [] };
    },
    evaluateAll: cannedResults(PERFECT_DAY0),
    sendPush,
    now: () => Date.parse('2026-08-01T02:30:00Z'),
  });
  await job.runDigestPass();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, 'healthy-token');
});

// --- no qualifying windows → no push, marker NOT set ---
test('nothing qualifying (all-null days) sends nothing and leaves the marker unset', async () => {
  const results = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [{ dayIndex: 0, rating: null }, { dayIndex: 1, rating: null }, { dayIndex: 2, rating: null }] }];
  const { db, sent } = await runPass({ rows: [makeDevice()], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 0);
  assert.equal(db.markers.length, 0, 'a later pass in the band may still deliver if the forecast improves');
});

test('a dormant (empty) snapshot evaluates to [] and sends nothing', async () => {
  const { sent } = await runPass({
    rows: [makeDevice({ activities: [] })],
    results: (hours, activities) => { assert.deepStrictEqual(activities, []); return []; },
    nowIso: '2026-08-01T02:30:00Z',
  });
  assert.equal(sent.length, 0);
});

// --- copy composition ---
test('diurnal today line: "Cycling: Perfect 7–10am" (global indices → location-local clock)', async () => {
  // forecastStart 06:00 local; window [startIndex 1, endIndex 4) = 07:00–10:00.
  const { sent } = await runPass({ rows: [makeDevice()], results: PERFECT_DAY0, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].message.title, 'Daily Digest');
  assert.equal(sent[0].message.body, 'Cycling: Perfect 7–10am');
  assert.deepStrictEqual(sent[0].message.payload, { type: 'dailyDigest' });
});

test('nocturnal bucket 0 reads "tonight" with a cross-midnight range (window from the SNAPSHOT, not the results)', async () => {
  const device = makeDevice({
    activities: [{ id: 'star', label: 'Stargazing', displayMetrics: ['temp'],
      thresholds: { temp: { min: 5, required: true } }, window: { startHour: 22, endHour: 2 } }],
  });
  // results echo NO window field (input-only) — nocturnal detection must read the snapshot.
  const results = [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
    days: [{ dayIndex: 0, rating: 'perfect', startIndex: 16, endIndex: 20, duration: 4 }] }];
  // startIndex 16 → 22:00 local; endIndex 20 → 02:00 next day.
  const { sent } = await runPass({ rows: [device], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent[0].message.body, 'Stargazing: Perfect tonight 10pm–2am');
});

test('good rating composes as Good; a "no window today" activity is omitted from the today section', async () => {
  const results = [
    { activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
      days: [{ dayIndex: 0, rating: 'good', startIndex: 1, endIndex: 4, duration: 3 }] },
    { activityId: 'run', label: 'Running', displayMetrics: ['temp'],
      days: [{ dayIndex: 0, rating: null }] },
  ];
  const { sent } = await runPass({ rows: [makeDevice()], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent[0].message.body, 'Cycling: Good 7–10am');
});

test('week-ahead: earliest Perfect in buckets 2..end — an 8-bucket tail-day Perfect appears; bucket 1 never does', async () => {
  const day = (dayIndex, rating) => rating
    ? { dayIndex, rating, startIndex: dayIndex * 24, endIndex: dayIndex * 24 + 3, duration: 3 }
    : { dayIndex, rating: null };
  const results = [
    // 8-bucket diurnal horizon: perfect at bucket 1 (detector's turf — must NOT
    // appear) and at the partial tail bucket 7 (a hardcoded 2–6 would hide it).
    { activityId: 'fishing', label: 'Fishing', displayMetrics: ['temp'],
      days: [day(0, null), day(1, 'perfect'), day(2, null), day(3, null), day(4, null), day(5, null), day(6, null), day(7, 'perfect')] },
  ];
  const { sent } = await runPass({ rows: [makeDevice()], results, nowIso: '2026-08-01T02:30:00Z' });
  // day 0 = 2026-08-01 (Sat); bucket 7 = 2026-08-08 (Sat).
  assert.equal(bucketDate(FORECAST_START, DUBAI, 7), '2026-08-08');
  assert.equal(sent[0].message.body, 'Sat: Perfect for Fishing');
});

test('a 6-bucket nocturnal horizon is never over-indexed and its tail Perfect surfaces', async () => {
  const device = makeDevice({
    activities: [{ id: 'star', label: 'Stargazing', displayMetrics: ['temp'],
      thresholds: { temp: { min: 5, required: true } }, window: { startHour: 22, endHour: 2 } }],
  });
  const results = [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
    days: [
      { dayIndex: 0, rating: null }, { dayIndex: 1, rating: null }, { dayIndex: 2, rating: null },
      { dayIndex: 3, rating: null }, { dayIndex: 4, rating: null },
      { dayIndex: 5, rating: 'perfect', startIndex: 136, endIndex: 140, duration: 4 },
    ] }];
  const { sent } = await runPass({ rows: [device], results, nowIso: '2026-08-01T02:30:00Z' });
  // day 0 = Sat 2026-08-01 → bucket 5 = Thu 2026-08-06.
  assert.equal(sent[0].message.body, 'Thu: Perfect for Stargazing');
});

test('today and week-ahead sections combine into one push, one line each', async () => {
  const results = [
    { activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
      days: [{ dayIndex: 0, rating: 'perfect', startIndex: 1, endIndex: 4, duration: 3 },
             { dayIndex: 1, rating: null },
             { dayIndex: 2, rating: 'perfect', startIndex: 50, endIndex: 55, duration: 5 }] },
  ];
  const { sent } = await runPass({ rows: [makeDevice()], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 1, 'ONE push per device');
  assert.equal(sent[0].message.body, 'Cycling: Perfect 7–10am\nMon: Perfect for Cycling');
});

// --- stale token ---
test('StaleTokenError deletes the device row and does not set the marker', async () => {
  const rows = [
    makeDevice({ device_id: 'stale', apns_token: 'dead' }),
    makeDevice({ device_id: 'alive', apns_token: 'live' }),
  ];
  const db = makeJobDb(rows);
  const sent = [];
  const job = createDailyDigestJob({
    db,
    getWeather: fakeWeather(),
    evaluateAll: cannedResults(PERFECT_DAY0),
    sendPush: async (token, message) => {
      if (token === 'dead') throw new StaleTokenError('gone');
      sent.push({ token, message });
    },
    now: () => Date.parse('2026-08-01T02:30:00Z'),
  });
  await job.runDigestPass();
  assert.deepStrictEqual(db.deleted, ['stale'], 'dead tokens must not accumulate');
  assert.deepStrictEqual(db.markers.map((m) => m.deviceId), ['alive'], 'no marker for the deleted row');
  assert.equal(sent.length, 1);
});
