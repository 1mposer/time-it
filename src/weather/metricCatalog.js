// Source of truth (ADR-0005) for which weather metrics exist and which carry
// live data versus a coming-soon placeholder. Validation hard-rejects
// coming-soon metrics: a threshold on placeholder data would pass trivially
// (a silent false Perfect).

// Real adapter data.
const LIVE_METRICS = new Set([
  'temp',
  'humidity',
  'windSpeed',
  'rainFall',
  'cloudCover',
  'visibility',
  'uV',
  'moon',
  'dustAlert',
]);

// parse.js placeholders (0/false) pending real data sources.
const COMING_SOON_METRICS = new Set([
  'darkness',
  'douglasScale',
  'swellHeight',
  'swellLength',
  'tide',
  'seaWarning',
]);

// Known = live or coming-soon; anything else is rejected.
function isKnown(metric) {
  return LIVE_METRICS.has(metric) || COMING_SOON_METRICS.has(metric);
}

// Available = backed by real data now; only these are evaluable.
function isAvailable(metric) {
  return LIVE_METRICS.has(metric);
}

module.exports = { LIVE_METRICS, COMING_SOON_METRICS, isKnown, isAvailable };
