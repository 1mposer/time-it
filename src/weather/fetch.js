const BASE_URL = "https://www.meteosource.com/api/v1/free/point";

async function fetchWeather(params) {
  const query = new URLSearchParams(params);
  const response = await fetch(`${BASE_URL}?${query.toString()}`);
  if (!response.ok) {
    throw new Error(`Response status: ${response.status}`);
  }
  return response.json();
}

module.exports = { fetchWeather };
