// Day score (ADR-0011): a depth-in-band confidence number computed beside the
// rating, from the same window-filtered / night-stitched bucket slices.
// Independence rule (the false-Perfect firewall): nothing here feeds
// evaluateHour/findLongestWindow, the digest, or the detector — the score is a
// derived display number, never a second verdict.

const { checkThreshold } = require('./decision_engine');

// Depth-in-band 0..100 for one value against one threshold.
// Two-sided band: linear — 0 at either edge, 100 at the centre. One-sided (and
// a degenerate zero-width band, whose centre is likewise undefined): binary —
// 100 inside, 0 outside. "Inside" is checkThreshold's own inclusive comparison
// rather than a re-derived one, so the two can never drift; that also gives the
// B2 posture for free (null/absent data fails, so it scores 0).
function metricScore(value, config) {
  if (!checkThreshold(value, config)) return 0;
  if (config.type === 'flag') return 100;

  const twoSided = config.min !== undefined && config.max !== undefined;
  if (!twoSided) return 100;

  const halfWidth = (config.max - config.min) / 2;
  if (halfWidth === 0) return 100; // min === max: no centre to measure depth from
  const centre = (config.min + config.max) / 2;
  return 100 * (1 - Math.abs(value - centre) / halfWidth);
}

// Mean over the activity's THRESHOLDED metrics only — display-only metrics
// never contribute. A failing required threshold zeroes the whole hour,
// mirroring the hour turning Bad in evaluateHour. An empty threshold map scores
// 100: there is nothing to judge and evaluateHour rates such an hour "perfect",
// so the score must agree rather than divide by zero.
function hourScore(hour, thresholds) {
  const entries = Object.entries(thresholds);
  if (entries.length === 0) return 100;

  let total = 0;
  for (const [metric, config] of entries) {
    if (config.required && !checkThreshold(hour[metric], config)) return 0;
    total += metricScore(hour[metric], config);
  }
  return total / entries.length;
}

// Mean over the bucket's window hours — the hour scores are NOT pre-rounded,
// so the fractional parts carry into the day mean — then rounded to the nearest
// integer (half-up) and clamped to 1..100, so an all-zero day still renders a
// drawable numeral and the tier colour carries the verdict. null iff the bucket
// holds zero window hours (the ADR null rule).
// The non-finite guard keeps that "null iff" an invariant rather than a
// coincidence: checkThreshold returns true for NaN (both NaN < min and
// NaN > max are false), so a NaN metric value would reach the mean, and a NaN
// score serializes as `null` — silently claiming an empty bucket. Unreachable
// through today's wire (JSON cannot encode NaN and the validators force finite
// bounds), but garbage data must fail like absent data does under B2, so it
// lands on the floor instead.
function dayScore(hours, thresholds) {
  if (hours.length === 0) return null;

  const mean = hours.reduce((sum, h) => sum + hourScore(h, thresholds), 0) / hours.length;
  if (!Number.isFinite(mean)) return 1;
  return Math.min(100, Math.max(1, Math.round(mean)));
}

module.exports = { metricScore, hourScore, dayScore };
