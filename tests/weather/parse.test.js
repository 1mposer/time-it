const test = require('node:test');
const assert = require('node:assert/strict');
const { parseWeather } = require('../../src/weather/parse');
const { UpstreamError } = require('../../src/weather/UpstreamError');

// Minimal stub adapter — exercises parseWeather in isolation.
function makeStubAdapter(overrides = {}) {
  return {
    extractHours:     (res) => res.hourly.data,
    moonPhaseByDay:   (res) => res.moonByDay ?? {},
    localDate:        (row) => row.date.slice(0, 10),
    timezone:         (res) => res.timezone ?? 'Asia/Dubai',
    forecastStart:    (row) => row.date,
    temp:       (h) => h.temp ?? 25,
    humidity:   (h) => h.humidity ?? 40,
    windSpeed:  (h) => h.windSpeed ?? 10,
    rainFall:   (h) => h.rainFall ?? 0,
    cloudCover: (h) => h.cloudCover ?? 10,
    visibility: (h) => h.visibility ?? 10,
    uV:         (h) => h.uV ?? 3,
    dustAlert:  (h) => h.dustAlert ?? false,
    ...overrides,
  };
}

// Hours run consecutively from 2026-06-10T00:00 local (day rolls at i = 24, 48 …);
// moonByDay covers only the first two days, so a long horizon has orphan days.
function makeRaw(hourCount = 24) {
  const start = Date.UTC(2026, 5, 10);
  return {
    hourly: { data: Array.from({ length: hourCount }, (_, i) => ({
      date: new Date(start + i * 3600_000).toISOString().slice(0, 19), hour: i,
    })) },
    moonByDay: { '2026-06-10': 'waxing crescent', '2026-06-11': 'first quarter' },
  };
}

test('parseWeather returns forecastStart from the first hour (stub adapter passes through)', () => {
  // Stub adapter passes the date through — confirms parseWeather just forwards what the adapter returns
  const { forecastStart } = parseWeather(makeRaw(), makeStubAdapter());
  assert.equal(forecastStart, '2026-06-10T00:00:00');
});

test('parseWeather surfaces the top-level timezone from the adapter', () => {
  const { timezone } = parseWeather(makeRaw(), makeStubAdapter());
  assert.equal(timezone, 'Asia/Dubai');
});

// ADR-0003: 168 is a CEILING, not a count. Slice caps at 168; fewer passes through.
test('parseWeather caps the horizon at the 168-hour ceiling', () => {
  const { hours } = parseWeather(makeRaw(200), makeStubAdapter());
  assert.equal(hours.length, 168);
});

test('parseWeather passes through a provider count below the ceiling (never fabricates)', () => {
  const { hours } = parseWeather(makeRaw(161), makeStubAdapter());
  assert.equal(hours.length, 161);
});

test('parseWeather throws UpstreamError when hourly data is empty (A5)', () => {
  const raw = { hourly: { data: [] }, astro: { phase: 'full' } };
  assert.throws(() => parseWeather(raw, makeStubAdapter()), UpstreamError);
});

test('each hour has its own moon array — pushing to one does not affect others (G1)', () => {
  const { hours } = parseWeather(makeRaw(), makeStubAdapter());
  hours[0].moon.push('mutated');
  assert.equal(hours[1].moon.includes('mutated'), false, 'mutating hour[0].moon leaked into hour[1]');
  assert.equal(hours[5].moon.includes('mutated'), false, 'mutating hour[0].moon leaked into hour[5]');
});

// #27: moon is daily data — each hour carries its own day's phase, and a day the
// provider's daily section did not cover gets [] (never fabricated, never the
// previous day's phase carried over).
test('moon phase is spread per local day from the daily astro map (#27)', () => {
  const { hours } = parseWeather(makeRaw(72), makeStubAdapter());
  assert.deepStrictEqual(hours[0].moon, ['waxing crescent']);
  assert.deepStrictEqual(hours[23].moon, ['waxing crescent']);
  assert.deepStrictEqual(hours[24].moon, ['first quarter']);
  assert.deepStrictEqual(hours[47].moon, ['first quarter']);
  assert.deepStrictEqual(hours[48].moon, [], 'a day with no daily astro entry has no phase');
});

test('moon is [] on every hour when the adapter finds no daily astro data (#27)', () => {
  const raw = makeRaw();
  delete raw.moonByDay;
  const { hours } = parseWeather(raw, makeStubAdapter());
  assert.ok(hours.every((h) => Array.isArray(h.moon) && h.moon.length === 0));
});

test('marine placeholder fields are present with 0/false defaults', () => {
  const { hours } = parseWeather(makeRaw(), makeStubAdapter());
  const h = hours[0];
  assert.equal(h.douglasScale, 0);
  assert.equal(h.swellHeight, 0);
  assert.equal(h.swellLength, 0);
  assert.equal(h.tide, 0);
  assert.equal(h.darkness, 0);
  assert.equal(h.seaWarning, false);
});

// Contract pin: parseWeather hour-object key order. `hour` is dropped (ADR-0004b
// — the client renders from forecastStart + timezone + index); `index` is added
// at the route layer (see rating.js).
test('hour object key order matches the documented contract (no `hour`)', () => {
  const { hours } = parseWeather(makeRaw(), makeStubAdapter());
  assert.deepStrictEqual(Object.keys(hours[0]), [
    'temp', 'humidity', 'windSpeed', 'rainFall', 'cloudCover',
    'visibility', 'moon', 'uV', 'dustAlert',
    'darkness', 'douglasScale', 'swellHeight', 'swellLength', 'tide', 'seaWarning',
  ]);
});
