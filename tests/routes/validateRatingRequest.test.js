const test = require('node:test');
const assert = require('node:assert/strict');
const { validateRatingRequest } = require('../../src/routes/validateRatingRequest');

// A minimal VALID body (ADR-0005). Helpers clone + mutate it so each test isolates
// one rejection. validateRatingRequest returns a structured error array — empty = valid.
function validBody() {
  return {
    lat: 25.1627,
    lon: 55.2077,
    activities: [
      {
        id: 'a1',
        label: 'Volleyball',
        // humidity is displayed but NOT thresholded — the show-but-don't-judge gap.
        displayMetrics: ['temp', 'windSpeed', 'humidity'],
        thresholds: {
          temp: { min: 15, max: 35, required: true },
          windSpeed: { max: 15, required: false },
        },
      },
    ],
  };
}

function paths(errors) {
  return errors.map((e) => e.path);
}

test('a valid body returns no errors', () => {
  assert.deepStrictEqual(validateRatingRequest(validBody()), []);
});

test('a valid wrapped (nocturnal) window passes', () => {
  const b = validBody();
  b.activities[0].window = { startHour: 22, endHour: 2 };
  assert.deepStrictEqual(validateRatingRequest(b), []);
});

test('a valid flag threshold passes', () => {
  const b = validBody();
  b.activities[0].displayMetrics.push('dustAlert');
  b.activities[0].thresholds.dustAlert = { type: 'flag', forbidTrue: true, required: true };
  assert.deepStrictEqual(validateRatingRequest(b), []);
});

// --- lat / lon ---
test('missing lat is rejected', () => {
  const b = validBody(); delete b.lat;
  assert.ok(paths(validateRatingRequest(b)).includes('lat'));
});
test('out-of-range lat is rejected', () => {
  const b = validBody(); b.lat = 91;
  assert.ok(paths(validateRatingRequest(b)).includes('lat'));
});
test('out-of-range lon is rejected', () => {
  const b = validBody(); b.lon = 200;
  assert.ok(paths(validateRatingRequest(b)).includes('lon'));
});
test('non-numeric lat is rejected', () => {
  const b = validBody(); b.lat = '25.1';
  assert.ok(paths(validateRatingRequest(b)).includes('lat'));
});

// --- activities array ---
test('empty activities is rejected', () => {
  const b = validBody(); b.activities = [];
  assert.ok(paths(validateRatingRequest(b)).includes('activities'));
});
test('missing activities is rejected', () => {
  const b = validBody(); delete b.activities;
  assert.ok(paths(validateRatingRequest(b)).includes('activities'));
});
test('activities over the abuse ceiling (~50) is rejected', () => {
  const b = validBody();
  const one = b.activities[0];
  b.activities = Array.from({ length: 51 }, (_, i) => ({ ...one, id: `a${i}` }));
  assert.ok(paths(validateRatingRequest(b)).includes('activities'));
});

// --- per-activity identity ---
test('missing label is rejected', () => {
  const b = validBody(); delete b.activities[0].label;
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].label'));
});
test('empty label is rejected', () => {
  const b = validBody(); b.activities[0].label = '';
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].label'));
});
test('missing id is rejected', () => {
  const b = validBody(); delete b.activities[0].id;
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].id'));
});
test('duplicate id within the request is rejected', () => {
  const b = validBody();
  b.activities.push({ ...b.activities[0] }); // same id 'a1'
  const errs = validateRatingRequest(b);
  assert.ok(paths(errs).includes('activities[1].id'), 'the duplicate occurrence is flagged');
});

// --- displayMetrics ---
test('empty displayMetrics is rejected', () => {
  const b = validBody(); b.activities[0].displayMetrics = [];
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].displayMetrics'));
});
test('unknown metric in displayMetrics is rejected', () => {
  const b = validBody(); b.activities[0].displayMetrics.push('notAMetric');
  assert.ok(validateRatingRequest(b).length > 0);
});
test('coming-soon metric in displayMetrics is rejected (false-Perfect backstop)', () => {
  const b = validBody(); b.activities[0].displayMetrics.push('seaWarning');
  assert.ok(validateRatingRequest(b).length > 0);
});

// --- thresholds: subset, availability, shape ---
test('threshold on a metric not in displayMetrics is rejected (subset invariant)', () => {
  const b = validBody();
  b.activities[0].thresholds.cloudCover = { max: 20, required: true }; // not displayed
  assert.ok(validateRatingRequest(b).length > 0);
});
test('coming-soon metric in thresholds is rejected', () => {
  const b = validBody();
  b.activities[0].displayMetrics.push('seaWarning');
  b.activities[0].thresholds.seaWarning = { type: 'flag', forbidTrue: true, required: true };
  assert.ok(validateRatingRequest(b).length > 0);
});
test('numeric min > max is rejected', () => {
  const b = validBody(); b.activities[0].thresholds.temp = { min: 40, max: 10, required: true };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].thresholds.temp'));
});
test('bound-less numeric threshold is rejected', () => {
  const b = validBody(); b.activities[0].thresholds.temp = { required: true };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].thresholds.temp'));
});
test('missing required on a threshold is rejected', () => {
  const b = validBody(); b.activities[0].thresholds.temp = { min: 15, max: 35 };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].thresholds.temp'));
});
test('requireTrue is rejected in v1 (Issue #8 unbuilt)', () => {
  const b = validBody();
  b.activities[0].displayMetrics.push('dustAlert');
  b.activities[0].thresholds.dustAlert = { type: 'flag', requireTrue: true, required: true };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].thresholds.dustAlert'));
});

// --- window ---
test('non-integer startHour is rejected', () => {
  const b = validBody(); b.activities[0].window = { startHour: 1.5, endHour: 4 };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].window'));
});
test('out-of-range endHour is rejected', () => {
  const b = validBody(); b.activities[0].window = { startHour: 2, endHour: 24 };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].window'));
});
test('startHour === endHour is rejected (empty set under half-open)', () => {
  const b = validBody(); b.activities[0].window = { startHour: 5, endHour: 5 };
  assert.ok(paths(validateRatingRequest(b)).includes('activities[0].window'));
});

// --- atomicity / structure ---
test('errors are structured { path, message } and atomic (all collected)', () => {
  const b = validBody();
  delete b.lat;
  b.activities[0].label = '';
  const errs = validateRatingRequest(b);
  assert.ok(errs.length >= 2, 'collects multiple errors, not first-wins');
  for (const e of errs) {
    assert.equal(typeof e.path, 'string');
    assert.equal(typeof e.message, 'string');
  }
});
