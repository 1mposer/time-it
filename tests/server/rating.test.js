const test = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');
const supertest = require('supertest');

const createRatingRouter = require('../../src/routes/rating');
const { UpstreamError } = require('../../src/weather/UpstreamError');

function makeHours() {
  return Array.from({ length: 24 }, (_, i) => ({
    hour: i, temp: 25, humidity: 40, windSpeed: 10, rainFall: 0,
    cloudCover: 10, visibility: 10, moon: [], uV: 3, dustAlert: false,
    darkness: 0, douglasScale: 0, swellHeight: 0, swellLength: 0,
    tide: 0, seaWarning: false,
  }));
}

// Build a minimal app with the router under test and injected dependencies.
function makeApp({ getWeather, evaluateAll }) {
  const app = express();
  app.use(express.json());
  app.use('/api/v1', createRatingRouter({ getWeather, evaluateAll }));
  return app;
}

const happyFixture = { forecastStart: '2026-06-07T00:00:00', hours: makeHours() };
const happyGetWeather  = async () => happyFixture;
const realEvaluateAll  = require('../../src/decision').evaluateAll;

test('missing lat returns 400', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lon=55.2077');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lat');
});

test('missing lon returns 400', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627');
  assert.equal(res.status, 400);
  assert.equal(res.body.error, 'Missing required parameter: lon');
});

test('valid request returns 200 with correct top-level shape', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 200);
  assert.ok('forecastStart' in res.body);
  assert.ok(Array.isArray(res.body.activities));
  assert.ok(Array.isArray(res.body.hours));
});

test('hours has 24 entries each with index 0-23', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.body.hours.length, 24);
  res.body.hours.forEach((h, i) => assert.equal(h.index, i));
});

test('each activity has required fields; non-null rating includes window fields', async () => {
  const app = makeApp({ getWeather: happyGetWeather, evaluateAll: realEvaluateAll });
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

// B3 — provider failures surface as 502
test('UpstreamError from getWeather → 502 (B3)', async () => {
  const failingGetWeather = async () => { throw new UpstreamError('provider down'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 502);
  assert.equal(res.body.error, 'Weather data unavailable');
});

// B3 — internal/unexpected errors surface as 500, NOT 502
test('Generic Error from getWeather → 500, not 502 (B3)', async () => {
  // Generic Error whose message mentions "fetch" — would previously be misclassified as 502
  const failingGetWeather = async () => { throw new Error('fetch is not defined'); };
  const app = makeApp({ getWeather: failingGetWeather, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  assert.equal(res.status, 500);
});

// B4 — timezone query param is ignored: getWeather is never called with a third arg
test('timezone query param is ignored — not forwarded to getWeather (B4)', async () => {
  let receivedArgs = null;
  const spyGetWeather = async (...args) => {
    receivedArgs = args;
    return happyFixture;
  };
  const app = makeApp({ getWeather: spyGetWeather, evaluateAll: realEvaluateAll });
  await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077&timezone=Asia/Dubai');
  assert.equal(receivedArgs.length, 2, `expected only (lat, lon), got ${receivedArgs.length} args: ${JSON.stringify(receivedArgs)}`);
});

// E3 (server-level) — null-rated activities in the response do NOT include window keys
test('null-rated activities have no startIndex/endIndex/duration in response JSON (E3)', async () => {
  // Force every required threshold to fail with extreme temp
  const fixture = { forecastStart: '2026-06-07T00:00:00', hours: makeHours().map(h => ({ ...h, temp: 100 })) };
  const app = makeApp({ getWeather: async () => fixture, evaluateAll: realEvaluateAll });
  const res = await supertest(app).get('/api/v1/rating?lat=25.1627&lon=55.2077');
  const nullRated = res.body.activities.filter(a => a.rating === null);
  assert.ok(nullRated.length > 0);
  for (const a of nullRated) {
    assert.equal('startIndex' in a, false, `startIndex leaked into JSON for ${a.activityId}`);
    assert.equal('endIndex' in a,   false);
    assert.equal('duration' in a,   false);
  }
});
