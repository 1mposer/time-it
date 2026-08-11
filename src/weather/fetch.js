const { UpstreamError } = require('./UpstreamError');

// standard tier — 7-day hourly horizon (ADR-0003). /free/ caps at 24h and is unusable here.
// The path segment must match the account's subscription (was /flexi/ until 2026-08-11).
const BASE_URL = "https://www.meteosource.com/api/v1/standard/point";

async function fetchWeather(params) {
  const query = new URLSearchParams(params);
  let response;
  try {
    response = await fetch(`${BASE_URL}?${query.toString()}`);
  } catch (err) {
    throw new UpstreamError(`Network failure contacting weather provider: ${err.message}`);
  }
  if (!response.ok) {
    throw new UpstreamError(`Weather provider responded with status ${response.status}`);
  }
  return response.json();
}

module.exports = { fetchWeather };
