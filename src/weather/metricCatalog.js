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

// What shape each known metric carries on the wire, so validation can reject a
// threshold whose kind cannot judge it: a numeric min/max against a label or a
// flag passes trivially (JS coerces `[] > 8` to false — a silent false Perfect).
//   numeric → { min?, max? }   flag → { type: 'flag', forbidTrue }   label → display-only
const METRIC_KINDS = Object.freeze({
  temp: 'numeric',
  humidity: 'numeric',
  windSpeed: 'numeric',
  rainFall: 'numeric',
  cloudCover: 'numeric',
  visibility: 'numeric',
  uV: 'numeric',
  moon: 'label',
  dustAlert: 'flag',
  darkness: 'numeric',
  douglasScale: 'numeric',
  swellHeight: 'numeric',
  swellLength: 'numeric',
  tide: 'numeric',
  seaWarning: 'flag',
});

// Known = live or coming-soon; anything else is rejected.
function isKnown(metric) {
  return LIVE_METRICS.has(metric) || COMING_SOON_METRICS.has(metric);
}

// Available = backed by real data now; only these are evaluable.
function isAvailable(metric) {
  return LIVE_METRICS.has(metric);
}

// 'numeric' | 'flag' | 'label' for a known metric; undefined otherwise.
function kindOf(metric) {
  return METRIC_KINDS[metric];
}

module.exports = { LIVE_METRICS, COMING_SOON_METRICS, METRIC_KINDS, isKnown, isAvailable, kindOf };
