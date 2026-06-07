const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('path');
const supertest = require('supertest');

function makeHours() {
  return Array.from({ length: 24 }, (_, i) => ({
    hour: i, temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false,
  }));
}

const fixture = { forecastStart: '2026-06-07T00:00:00', hours: makeHours() };

// Inject fake weather module into require cache before server loads
const weatherPath = path.resolve(__dirname, '../../src/weather/index.js');
require.cache[weatherPath] = {
  id: weatherPath, filename: weatherPath, loaded: true,
  exports: { getWeather: async () => fixture },
};

const app = require('../../src/server');

test('missing lat returns 400', async () => {
  const res = await supertest(app).get('/api/v1/rating?lon=55.2077');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lat');
});

test('missing lon returns 400', async () => {
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lon');
});

test('valid request returns 200 with correct top-level shape', async () => {
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 200);
  assert.ok('forecastStart' in res.body);
  assert.ok(Array.isArray(res.body.activities));
  assert.ok(Array.isArray(res.body.hours));
});

test('hours has 24 entries each with index 0-23', async () => {
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.body.hours.length, 24);
  res.body.hours.forEach((h, i) => assert.equal(h.index, i));
});

test('each activity has required fields; non-null rating includes window fields', async () => {
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  for (const activity of res.body.activities) {
    assert.ok('activityId' in activity, `missing activityId on ${activity.label}`);
    assert.ok('label' in activity,      `missing label on ${activity.activityId}`);
    assert.ok('rating' in activity,     `missing rating on ${activity.activityId}`);
    assert.ok('displayMetrics' in activity, `missing displayMetrics on ${activity.activityId}`);
    if (activity.rating !== null) {
      assert.ok('startIndex' in activity, `missing startIndex on ${activity.activityId}`);
      assert.ok('endIndex' in activity,   `missing endIndex on ${activity.activityId}`);
      assert.ok('duration' in activity,   `missing duration on ${activity.activityId}`);
    }
  }
});
