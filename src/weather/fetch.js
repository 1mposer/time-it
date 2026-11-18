const { UpstreamError } = require('./UpstreamError');

// The `standard` path segment must match the account's Meteosource
// subscription tier; /free/ caps at 24h.
const BASE_URL = "https://www.meteosource.com/api/v1/standard/point";

// A provider that accepts the connection and never answers would otherwise
// hold the caller — and the shared cache's in-flight promise — for minutes.
// The timer covers the whole exchange, body read included.
const PROVIDER_TIMEOUT_MS = 8000;

// Every provider-side failure — timeout, network error, non-OK status, an
// unparseable body — surfaces as UpstreamError (→ 502).
async function fetchWeather(params) {
  const query = new URLSearchParams(params);
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort(new UpstreamError(`Weather provider timed out after ${PROVIDER_TIMEOUT_MS} ms`)),
    PROVIDER_TIMEOUT_MS,
  );
  try {
    let response;
    try {
      response = await fetch(`${BASE_URL}?${query.toString()}`, { signal: controller.signal });
    } catch (err) {
      throw toUpstream(err, 'Network failure contacting weather provider');
    }
    if (!response.ok) {
      throw new UpstreamError(`Weather provider responded with status ${response.status}`);
    }
    try {
      return await response.json();
    } catch (err) {
      throw toUpstream(err, 'Unreadable weather provider response');
    }
  } finally {
    clearTimeout(timer);
  }
}

function toUpstream(err, prefix) {
  if (err instanceof UpstreamError) return err;
  return new UpstreamError(`${prefix}: ${err?.message ?? err}`);
}

module.exports = { fetchWeather, PROVIDER_TIMEOUT_MS };
