const { UpstreamError } = require('./UpstreamError');

const BASE_URL = "https://www.meteosource.com/api/v1/free/point";

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
