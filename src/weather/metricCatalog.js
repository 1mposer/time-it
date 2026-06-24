// Metric catalog (ADR-0005) — the server-side source of truth for which weather
// metrics exist and which carry LIVE data versus a coming-soon placeholder. The
// backend "knows which metrics are live because it owns the adapters": LIVE_METRICS
// are the real fields the adapter/parse layer emits; COMING_SOON_METRICS are the
// fields parse.js hardcodes to 0/false pending a data source. A threshold on a
// coming-soon metric would pass trivially against the placeholder — the silent
// false-Perfect hazard — so request validation hard-rejects it (ADR-0005 §6).
//
// Kept deliberately separate from validation and parse so the deferred
// GET /api/v1/metrics catalog route (ADR-0006) can read from this one source.

// Real adapter data (src/weather/parse.js).
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

// parse.js placeholders (0/false) — see the "Pending / placeholder data" table.
const COMING_SOON_METRICS = new Set([
  'darkness',
  'douglasScale',
  'swellHeight',
  'swellLength',
  'tide',
  'seaWarning',
]);

// A key is "known" if the system has a column for it at all (live or coming-soon);
// anything else is garbage the client should never send.
function isKnown(metric) {
  return LIVE_METRICS.has(metric) || COMING_SOON_METRICS.has(metric);
}

// "Available" = backed by real data right now. Only live metrics are evaluable.
function isAvailable(metric) {
  return LIVE_METRICS.has(metric);
}

module.exports = { LIVE_METRICS, COMING_SOON_METRICS, isKnown, isAvailable };
