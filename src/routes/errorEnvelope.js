// Uniform error envelope (ADR-0005 §6), shared by every router so the shape
// never forks across routes: EVERY error response — 400 validation, 502
// provider, 500 unexpected — returns a structured { errors: [{ path?, message }] }
// array the iOS decoder parses as one shape (502/500 are single-element arrays).
// Extracted from rating.js for Issue #6c; the rating route's wire output is
// byte-identical to the pre-extraction inline version.

const { UpstreamError } = require('../weather/UpstreamError');

function errorBody(message, path) {
  const err = path === undefined ? { message } : { path, message };
  return { errors: [err] };
}

// The catch-block mapping every route shares: a provider-side failure is a 502
// (transient — the client may retry); anything else is a 500 (server defect).
function sendRouteError(res, err) {
  if (err instanceof UpstreamError) {
    return res.status(502).json(errorBody('Weather data unavailable'));
  }
  console.error(err);
  return res.status(500).json(errorBody('Internal server error'));
}

module.exports = { errorBody, sendRouteError };
