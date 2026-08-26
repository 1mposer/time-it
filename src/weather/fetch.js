const { UpstreamError } = require('./UpstreamError');

// The `standard` path segment must match the account's Meteosource
// subscription tier; /free/ caps at 24h.
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
