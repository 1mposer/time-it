// Per-activity validation rules (ADR-0005) shared by the rating and devices
// routes. Owns the duplicate-id check and the activities ceiling; the
// non-empty rule stays with each caller. Any unknown or coming-soon metric —
// in either displayMetrics or thresholds — is a hard reject: a threshold on
// placeholder data would pass trivially (a silent false Perfect).

const { isKnown, isAvailable } = require('../weather/metricCatalog');

const MAX_ACTIVITIES = 50; // abuse ceiling, not a tier gate (ADR-0005)

const isFiniteNumber = (v) => typeof v === 'number' && Number.isFinite(v);
const isNonEmptyString = (v) => typeof v === 'string' && v.length > 0;
const isIntInRange = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;

function validateMetricKey(metric, path, errors) {
  if (!isKnown(metric)) {
    errors.push({ path, message: `unknown metric: ${metric}` });
  } else if (!isAvailable(metric)) {
    errors.push({ path, message: `coming-soon metric not yet available: ${metric}` });
  }
}

// Thresholded metrics must be a subset of displayMetrics; a numeric threshold
// needs at least one bound (min <= max); a flag needs forbidTrue: true;
// required is mandatory on every threshold.
function validateThreshold(metric, config, displaySet, path, errors) {
  if (config === null || typeof config !== 'object') {
    errors.push({ path, message: 'threshold must be an object' });
    return;
  }

  if (!displaySet.has(metric)) {
    errors.push({ path, message: `thresholded metric "${metric}" is not in displayMetrics` });
  }
  validateMetricKey(metric, path, errors);

  if ('requireTrue' in config) {
    errors.push({ path, message: 'requireTrue is not supported in v1 (Issue #8)' });
  }
  if (typeof config.required !== 'boolean') {
    errors.push({ path, message: 'required is mandatory and must be a boolean' });
  }

  if (config.type === 'flag') {
    if (config.forbidTrue !== true) {
      errors.push({ path, message: 'a flag threshold must set forbidTrue: true' });
    }
    return;
  }

  const hasMin = 'min' in config;
  const hasMax = 'max' in config;
  if (!hasMin && !hasMax) {
    errors.push({ path, message: 'a numeric threshold needs at least one of min/max' });
    return;
  }
  if (hasMin && !isFiniteNumber(config.min)) {
    errors.push({ path, message: 'min must be a number' });
  }
  if (hasMax && !isFiniteNumber(config.max)) {
    errors.push({ path, message: 'max must be a number' });
  }
  if (hasMin && hasMax && isFiniteNumber(config.min) && isFiniteNumber(config.max) && config.min > config.max) {
    errors.push({ path, message: 'min greater than max' });
  }
}

function validateWindow(window, path, errors) {
  if (window === null || typeof window !== 'object') {
    errors.push({ path, message: 'window must be an object' });
    return;
  }
  const { startHour, endHour } = window;
  if (!isIntInRange(startHour, 0, 23) || !isIntInRange(endHour, 0, 23)) {
    errors.push({ path, message: 'window startHour/endHour must be integers in 0..23' });
    return;
  }
  if (startHour === endHour) {
    errors.push({ path, message: 'startHour equals endHour (empty window; omit window for whole-day)' });
  }
}

function validateActivity(activity, path, seenIds, errors) {
  if (activity === null || typeof activity !== 'object') {
    errors.push({ path, message: 'activity must be an object' });
    return;
  }

  if (!isNonEmptyString(activity.id)) {
    errors.push({ path: `${path}.id`, message: 'id is required and must be a non-empty string' });
  } else if (seenIds.has(activity.id)) {
    errors.push({ path: `${path}.id`, message: `duplicate id within request: ${activity.id}` });
  } else {
    seenIds.add(activity.id);
  }

  if (!isNonEmptyString(activity.label)) {
    errors.push({ path: `${path}.label`, message: 'label is required and must be a non-empty string' });
  }

  const display = activity.displayMetrics;
  const displaySet = new Set(Array.isArray(display) ? display : []);
  if (!Array.isArray(display) || display.length === 0) {
    errors.push({ path: `${path}.displayMetrics`, message: 'displayMetrics is required and must be non-empty' });
  } else {
    for (const metric of display) {
      validateMetricKey(metric, `${path}.displayMetrics`, errors);
    }
  }

  const thresholds = activity.thresholds;
  if (thresholds === null || typeof thresholds !== 'object') {
    errors.push({ path: `${path}.thresholds`, message: 'thresholds is required and must be an object' });
  } else {
    for (const [metric, config] of Object.entries(thresholds)) {
      validateThreshold(metric, config, displaySet, `${path}.thresholds.${metric}`, errors);
    }
  }

  if ('window' in activity && activity.window !== undefined) {
    validateWindow(activity.window, `${path}.window`, errors);
  }
}

// Validates an already-an-array activities list; error paths compose from
// pathPrefix. Returns { path, message } errors; empty array = valid.
function validateActivities(activities, pathPrefix = 'activities') {
  const errors = [];
  if (activities.length > MAX_ACTIVITIES) {
    errors.push({ path: pathPrefix, message: `activities exceeds the limit of ${MAX_ACTIVITIES}` });
    return errors;
  }
  const seenIds = new Set();
  activities.forEach((activity, i) => {
    validateActivity(activity, `${pathPrefix}[${i}]`, seenIds, errors);
  });
  return errors;
}

module.exports = { validateActivities, MAX_ACTIVITIES, isFiniteNumber, isNonEmptyString };
