const test = require('node:test');
const assert = require('node:assert/strict');

const { createPerfectWindowDetectorJob } = require('../../src/jobs/perfectWindowDetector');
const { StaleTokenError } = require('../../src/notifications/apns');

// ---------------------------------------------------------------------------
// Fakes. The db fake keeps a STATEFUL notification_state set (keys
// 'device|activity|date') so re-run tests exercise the real dedup semantics:
// INSERT ... ON CONFLICT DO NOTHING reports rowCount 0 on a hit, and the pass's
// prune deletes keys older than (today − 2 days) exactly as the SQL would.
// ---------------------------------------------------------------------------

function makeDetectorDb(rows, seedKeys = []) {
  const state = new Set(seedKeys);
  const deactivatedDevices = [];
  return {
    state,
    deactivatedDevices,
    query: async (text, params) => {
      if (text.startsWith('SELECT')) {
        // Mirror the WHERE clause (see the digest fake): only a filtering
        // SELECT gets filtered rows.
        if (text.includes('apns_token IS NOT NULL')) {
          return { rows: rows.filter((r) => r.apns_token != null) };
        }
        return { rows };
      }
      if (text.startsWith('UPDATE devices SET apns_token = NULL')) {
        deactivatedDevices.push(params[0]);
        const row = rows.find((r) => r.device_id === params[0]);
        if (row) row.apns_token = null; // token blanked, row kept (ADR-0010)
        return { rows: [] };
      }
      if (text.startsWith('INSERT INTO notification_state')) {
        const key = params.join('|');
        if (state.has(key)) return { rowCount: 0, rows: [] };
        state.add(key);
        return { rowCount: 1, rows: [] };
      }
      if (text.startsWith('DELETE FROM notification_state')) {
        // Mirror `bucket_date < $1::date - 2`.
        const cutoff = new Date(Date.parse(`${params[0]}T00:00:00Z`) - 2 * 86400000)
          .toISOString().slice(0, 10);
        for (const key of [...state]) {
          if (key.split('|')[2] < cutoff) state.delete(key);
        }
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
    ...overrides,
  };
}

// forecastStart 02:00Z = 06:00 Asia/Dubai — index i sits at local hour 6 + i.
const FORECAST_START = '2026-08-01T02:00:00Z';
const DUBAI = 'Asia/Dubai';
const fakeWeather = (forecastStart = FORECAST_START, timezone = DUBAI) =>
  async () => ({ forecastStart, timezone, hours: [] });

const cannedResults = (results) => () => results;

function makeSentLog() {
  const sent = [];
  return { sent, sendPush: async (token, message) => { sent.push({ token, message }); } };
}

// db and sent log are injectable so multi-run tests share state across passes.
function runPass({ rows, results, nowIso, forecastStart, timezone, db, sendPush, sent }) {
  const theDb = db || makeDetectorDb(rows);
  const log = makeSentLog();
  const job = createPerfectWindowDetectorJob({
    db: theDb,
    getWeather: fakeWeather(forecastStart, timezone),
    evaluateAll: typeof results === 'function' ? results : cannedResults(results),
    sendPush: sendPush || (sent ? async (t, m) => sent.push({ token: t, message: m }) : log.sendPush),
    now: () => Date.parse(nowIso),
  });
  return job.runDetectorPass().then(() => ({ db: theDb, sent: sent || log.sent }));
}

const perfectDay = (dayIndex, startIndex, endIndex) =>
  ({ dayIndex, rating: 'perfect', startIndex, endIndex, duration: endIndex - startIndex });
const nullDay = (dayIndex) => ({ dayIndex, rating: null });

// Cycling result: Perfect today [1, 4) = 07:00–10:00 local.
const PERFECT_BUCKET0 = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
  days: [perfectDay(0, 1, 4), nullDay(1), nullDay(2)] }];

// --- one alert per (device, activity, bucket) ---

test('a new Perfect in bucket 0 sends one push and writes one state row', async () => {
  const { db, sent } = await runPass({ rows: [makeDevice()], results: PERFECT_BUCKET0, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, 'a1b2c3');
  assert.equal(sent[0].message.title, 'Perfect Cycling window');
  assert.equal(sent[0].message.body, 'Today 7–10am (3h)');
  assert.deepStrictEqual(sent[0].message.payload,
    { type: 'perfectWindow', activityId: 'cycling', bucketDate: '2026-08-01' });
  assert.deepStrictEqual([...db.state], ['device-1|cycling|2026-08-01']);
});

test('re-running the same forecast sends nothing more', async () => {
  const rows = [makeDevice()];
  const { db, sent } = await runPass({ rows, results: PERFECT_BUCKET0, nowIso: '2026-08-01T02:30:00Z' });
  const second = await runPass({ rows, results: PERFECT_BUCKET0, nowIso: '2026-08-01T03:30:00Z', db });
  assert.equal(sent.length, 1);
  assert.equal(second.sent.length, 0, 'the dedup row suppresses the second pass');
});

test('a re-based forecastStart (the old startIndex bug) does not re-alert the same real-world window', async () => {
  const rows = [makeDevice()];
  const { db } = await runPass({ rows, results: PERFECT_BUCKET0, nowIso: '2026-08-01T02:30:00Z' });
  // One hour later the provider re-bases: forecastStart 03:00Z, and the SAME
  // 07:00–10:00 window is now [0, 3). Index-keyed dedup would re-alert here.
  const rebased = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [perfectDay(0, 0, 3), nullDay(1)] }];
  const second = await runPass({
    rows, results: rebased, nowIso: '2026-08-01T03:30:00Z',
    forecastStart: '2026-08-01T03:00:00Z', db,
  });
  assert.equal(second.sent.length, 0, 'bucket_date is stable across re-basing');
  assert.equal(db.state.size, 1);
});

// --- Perfect-only + the inherent upgrade path ---

test('a Good-only bucket never alerts; its later upgrade to Perfect does', async () => {
  const rows = [makeDevice()];
  const goodOnly = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [{ dayIndex: 0, rating: 'good', startIndex: 1, endIndex: 4, duration: 3 }, nullDay(1)] }];
  const first = await runPass({ rows, results: goodOnly, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(first.sent.length, 0);
  assert.equal(first.db.state.size, 0, 'Good consumes no dedup key');

  // Upgrade: the bucket's FIRST Perfect alerts inherently — no rating column.
  const second = await runPass({ rows, results: PERFECT_BUCKET0, nowIso: '2026-08-01T03:30:00Z', db: first.db });
  assert.equal(second.sent.length, 1);
});

// --- horizon ---

test('buckets 0 and 1 both alert (the capped first-registration burst); bucket 2 never does', async () => {
  const results = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [perfectDay(0, 1, 4), perfectDay(1, 25, 28), perfectDay(2, 49, 52)] }];
  const { db, sent } = await runPass({ rows: [makeDevice()], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 2, 'buckets 0–1 only — day 2+ belongs to the digest');
  assert.equal(sent[0].message.body, 'Today 7–10am (3h)');
  assert.equal(sent[1].message.body, 'Tomorrow 7–10am (3h)');
  assert.deepStrictEqual([...db.state].sort(),
    ['device-1|cycling|2026-08-01', 'device-1|cycling|2026-08-02']);
});

// --- ended vs ongoing (endIndex is EXCLUSIVE — [startIndex, endIndex)) ---

test('an already-ended window neither alerts nor consumes a dedup key', async () => {
  // 12:30 local — the 07:00–10:00 window's end instant (10:00) has passed.
  const { db, sent } = await runPass({ rows: [makeDevice()], results: PERFECT_BUCKET0, nowIso: '2026-08-01T08:30:00Z' });
  assert.equal(sent.length, 0);
  assert.equal(db.state.size, 0, 'skip happens BEFORE the insert');
});

test('an ongoing window alerts with "now until" copy', async () => {
  // 07:30 local — inside [07:00, 10:00).
  const { sent } = await runPass({ rows: [makeDevice()], results: PERFECT_BUCKET0, nowIso: '2026-08-01T03:30:00Z' });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].message.body, 'Now until 10am');
});

test('a window ending exactly now is ended, not ongoing (exclusive bound)', async () => {
  // 10:00 local exactly: end instant == now → ended.
  const { sent } = await runPass({ rows: [makeDevice()], results: PERFECT_BUCKET0, nowIso: '2026-08-01T06:00:00Z' });
  assert.equal(sent.length, 0);
});

// --- nocturnal: evening-keyed bucket_date + "Tonight" copy ---

const nocturnalDevice = (window) => makeDevice({
  activities: [{ id: 'star', label: 'Stargazing', displayMetrics: ['temp'],
    thresholds: { temp: { min: 5, required: true } }, window }],
});

test('nocturnal bucket 0 keys on the EVENING\'s date and reads "Tonight"', async () => {
  // startIndex 16 → 22:00 local Aug 1; endIndex 20 → 02:00 local Aug 2.
  const results = [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
    days: [perfectDay(0, 16, 20), nullDay(1)] }];
  const { db, sent } = await runPass({
    rows: [nocturnalDevice({ startHour: 22, endHour: 2 })], results, nowIso: '2026-08-01T02:30:00Z',
  });
  assert.equal(sent.length, 1);
  assert.equal(sent[0].message.body, 'Tonight 10pm–2am (4h)');
  assert.deepStrictEqual([...db.state], ['device-1|star|2026-08-01'],
    'the wrapped window\'s early-morning tail belongs to its evening');
});

test('morning-tail nocturnal window (entirely after midnight) still keys on the evening\'s date', async () => {
  // Window 22→4; Perfect 01:00–03:00 local Aug 2 = indices [19, 21), dayIndex 0.
  // hours[19].localDay would be 2026-08-02 — deriving bucket_date from it is the
  // audited trap; dayIndex-based derivation must yield the evening's 2026-08-01.
  const results = [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
    days: [perfectDay(0, 19, 21), nullDay(1)] }];
  const { db, sent } = await runPass({
    rows: [nocturnalDevice({ startHour: 22, endHour: 4 })], results, nowIso: '2026-08-01T02:30:00Z',
  });
  assert.equal(sent.length, 1);
  assert.deepStrictEqual([...db.state], ['device-1|star|2026-08-01']);
});

test('jitter shifting a night\'s window across midnight neither re-alerts nor consumes the next night\'s key', async () => {
  const rows = [nocturnalDevice({ startHour: 22, endHour: 4 })];
  // First run: Perfect 23:00–01:00 = [17, 19), dayIndex 0 → alerts, key 2026-08-01.
  const first = await runPass({
    rows,
    results: [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
      days: [perfectDay(0, 17, 19), nullDay(1)] }],
    nowIso: '2026-08-01T02:30:00Z',
  });
  assert.equal(first.sent.length, 1);

  // Jitter: the same night's window shifts to 00:00–02:00 = [18, 20) — now
  // entirely past midnight, but still dayIndex 0. Must NOT re-alert.
  const second = await runPass({
    rows,
    results: [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
      days: [perfectDay(0, 18, 20), nullDay(1)] }],
    nowIso: '2026-08-01T03:30:00Z', db: first.db,
  });
  assert.equal(second.sent.length, 0, 'same night, same key — jitter cannot re-alert');

  // The NEXT night (dayIndex 1, evening Aug 2) has its own key and still alerts.
  const third = await runPass({
    rows,
    results: [{ activityId: 'star', label: 'Stargazing', displayMetrics: ['temp'],
      days: [perfectDay(0, 18, 20), perfectDay(1, 41, 43)] }],
    nowIso: '2026-08-01T04:30:00Z', db: first.db,
  });
  assert.equal(third.sent.length, 1, 'the misfiled-key failure mode: next night must not be suppressed');
  assert.equal(third.sent[0].message.payload.bucketDate, '2026-08-02');
  assert.equal(third.sent[0].message.body, 'Tomorrow night 11pm–1am (2h)');
});

// --- independence + races ---

test('two activities on one device get independent state rows and pushes', async () => {
  const device = makeDevice({
    activities: [
      { id: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
        thresholds: { temp: { min: 15, max: 35, required: true } } },
      { id: 'run', label: 'Running', displayMetrics: ['temp'],
        thresholds: { temp: { min: 10, max: 30, required: true } } },
    ],
  });
  const results = [
    { activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'], days: [perfectDay(0, 1, 4)] },
    { activityId: 'run', label: 'Running', displayMetrics: ['temp'], days: [perfectDay(0, 2, 5)] },
  ];
  const { db, sent } = await runPass({ rows: [device], results, nowIso: '2026-08-01T02:30:00Z' });
  assert.equal(sent.length, 2);
  assert.deepStrictEqual([...db.state].sort(),
    ['device-1|cycling|2026-08-01', 'device-1|run|2026-08-01']);
});

test('an insert conflict (concurrent-pass race) sends no duplicate push', async () => {
  const db = makeDetectorDb([makeDevice()], ['device-1|cycling|2026-08-01']);
  const { sent } = await runPass({ results: PERFECT_BUCKET0, nowIso: '2026-08-01T02:30:00Z', db });
  assert.equal(sent.length, 0, 'insert-first: only an actual insert may push');
});

// --- pruning ---

test('each pass prunes state rows older than today − 2 days', async () => {
  const db = makeDetectorDb([makeDevice()], [
    'device-1|cycling|2026-07-29', // < cutoff → pruned
    'device-1|cycling|2026-07-30', // == cutoff → kept (strict <)
  ]);
  await runPass({ results: [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [nullDay(0), nullDay(1)] }], nowIso: '2026-08-01T02:30:00Z', db });
  assert.deepStrictEqual([...db.state], ['device-1|cycling|2026-07-30']);
});

// --- stale token + isolation (ADR-0010 never-erase: deactivate, keep state) ---

test('StaleTokenError blanks the token, KEEPS the row and its state rows, logs, and stops its remaining alerts', async () => {
  const rows = [
    makeDevice({ device_id: 'stale', apns_token: 'dead' }),
    makeDevice({ device_id: 'alive', apns_token: 'live' }),
  ];
  const db = makeDetectorDb(rows);
  const sent = [];
  const results = [{ activityId: 'cycling', label: 'Cycling', displayMetrics: ['temp'],
    days: [perfectDay(0, 1, 4), perfectDay(1, 25, 28)] }];
  const job = createPerfectWindowDetectorJob({
    db,
    getWeather: fakeWeather(),
    evaluateAll: cannedResults(results),
    sendPush: async (token, message) => {
      if (token === 'dead') throw new StaleTokenError('gone');
      sent.push({ token, message });
    },
    now: () => Date.parse('2026-08-01T02:30:00Z'),
  });
  const warnings = [];
  const originalWarn = console.warn;
  console.warn = (...args) => warnings.push(args.join(' '));
  try {
    await job.runDetectorPass();
  } finally {
    console.warn = originalWarn;
  }
  assert.deepStrictEqual(db.deactivatedDevices, ['stale'], 'dead push addresses must not accumulate');
  const staleRow = rows.find((r) => r.device_id === 'stale');
  assert.equal(staleRow.apns_token, null, 'only the token is blanked');
  assert.ok(
    warnings.some((w) => w.includes('stale') && w.includes('token blanked, row kept')),
    'the deactivation is never silent (2026-08-19 debugging-session rule)'
  );
  // Nothing was deleted, so nothing cascades: the bucket-0 key the stale
  // device consumed before its push failed SURVIVES the deactivation.
  assert.deepStrictEqual([...db.state].sort(), [
    'alive|cycling|2026-08-01',
    'alive|cycling|2026-08-02',
    'stale|cycling|2026-08-01',
  ]);
  assert.equal(sent.length, 2, 'the healthy device still gets both bucket alerts');
  assert.ok(sent.every((s) => s.token === 'live'), 'deactivation stops the stale device\'s remaining alerts');
});

test('a deactivated (token-less) row is never selected: no weather call, no push, no key consumed', async () => {
  let weatherCalls = 0;
  const db = makeDetectorDb([makeDevice({ device_id: 'dormant', apns_token: null })]);
  const { sent, sendPush } = makeSentLog();
  const job = createPerfectWindowDetectorJob({
    db,
    getWeather: async () => { weatherCalls++; return { forecastStart: FORECAST_START, timezone: DUBAI, hours: [] }; },
    evaluateAll: cannedResults(PERFECT_BUCKET0),
    sendPush,
    now: () => Date.parse('2026-08-01T02:30:00Z'),
  });
  await job.runDetectorPass();
  assert.equal(weatherCalls, 0, 'dormant-for-push rows are filtered in SQL — the weather call is saved too');
  assert.equal(sent.length, 0);
  assert.equal(db.state.size, 0);
});

test('one device failing never stops the pass', async () => {
  const rows = [
    makeDevice({ device_id: 'broken', home_lat: 0, home_lon: 0 }),
    makeDevice({ device_id: 'healthy', apns_token: 'healthy-token' }),
  ];
  const db = makeDetectorDb(rows);
  const { sent, sendPush } = makeSentLog();
  const job = createPerfectWindowDetectorJob({
    db,
    getWeather: async (lat) => {
      if (lat === 0) throw new Error('provider exploded');
      return { forecastStart: FORECAST_START, timezone: DUBAI, hours: [] };
    },
    evaluateAll: cannedResults(PERFECT_BUCKET0),
    sendPush,
    now: () => Date.parse('2026-08-01T02:30:00Z'),
  });
  await job.runDetectorPass();
  assert.equal(sent.length, 1);
  assert.equal(sent[0].token, 'healthy-token');
});

test('a dormant (empty) snapshot evaluates to [] and sends nothing', async () => {
  const { sent } = await runPass({
    rows: [makeDevice({ activities: [] })],
    results: (hours, activities) => { assert.deepStrictEqual(activities, []); return []; },
    nowIso: '2026-08-01T02:30:00Z',
  });
  assert.equal(sent.length, 0);
});
