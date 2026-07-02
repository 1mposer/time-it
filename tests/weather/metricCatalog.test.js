const test = require('node:test');
const assert = require('node:assert/strict');
const {
  LIVE_METRICS,
  COMING_SOON_METRICS,
  isKnown,
  isAvailable,
} = require('../../src/weather/metricCatalog');

// The catalog is the server-side source of truth ADR-0005's coming-soon hard-400
// reads. Live = real adapter data; coming-soon = parse.js placeholders that would
// trivially pass a threshold (the silent false-Perfect hazard).
test('live metrics are exactly the real-data fields parse.js emits', () => {
  assert.deepStrictEqual(
    [...LIVE_METRICS].sort(),
    ['cloudCover', 'dustAlert', 'humidity', 'moon', 'rainFall', 'temp', 'uV', 'visibility', 'windSpeed'].sort(),
  );
});

test('coming-soon metrics are exactly the parse.js placeholder fields', () => {
  assert.deepStrictEqual(
    [...COMING_SOON_METRICS].sort(),
    ['darkness', 'douglasScale', 'seaWarning', 'swellHeight', 'swellLength', 'tide'].sort(),
  );
});

test('live and coming-soon are disjoint', () => {
  for (const m of LIVE_METRICS) assert.equal(COMING_SOON_METRICS.has(m), false, `${m} in both sets`);
});

test('isKnown: true for live and coming-soon, false for garbage', () => {
  assert.equal(isKnown('temp'), true);
  assert.equal(isKnown('seaWarning'), true); // coming-soon is still a known key
  assert.equal(isKnown('notAMetric'), false);
});

test('isAvailable: true only for live metrics', () => {
  assert.equal(isAvailable('temp'), true);
  assert.equal(isAvailable('seaWarning'), false); // known but not live
  assert.equal(isAvailable('notAMetric'), false);
});
