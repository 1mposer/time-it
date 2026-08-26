// Uniform error envelope (ADR-0005 §6) shared by every router: every error
// response is { errors: [{ path?, message }] } so clients parse one shape
// across codes.

const { UpstreamError } = require('../weather/UpstreamError');

function errorBody(message, path) {
  const err = path === undefined ? { message } : { path, message };
  return { errors: [err] };
}

// Shared catch mapping: provider failure → 502 (transient), anything else →
// 500 (server defect).
function sendRouteError(res, err) {
  if (err instanceof UpstreamError) {
    return res.status(502).json(errorBody('Weather data unavailable'));
  }
  console.error(err);
  return res.status(500).json(errorBody('Internal server error'));
}

module.exports = { errorBody, sendRouteError };
