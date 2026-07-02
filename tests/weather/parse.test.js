const test = require('node:test');
const assert = require('node:assert/strict');
const { parseWeather } = require('../../src/weather/parse');
const { UpstreamError } = require('../../src/weather/UpstreamError');

// Minimal stub adapter — exercises parseWeather in isolation.
function makeStubAdapter(overrides = {}) {
  return {
    extractHours:     (res) => res.hourly.data,
    extractMoonPhase: (res) => res.astro?.phase,
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

function makeRaw(hourCount = 24) {
  return {
    hourly: { data: Array.from({ length: hourCount }, (_, i) => ({ date: `2026-06-10T${String(i % 24).padStart(2, '0')}:00:00`, hour: i })) },
    astro:  { phase: 'waxing crescent' },
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
