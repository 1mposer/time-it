require('dotenv').config();
const { parseWeather } = require('./parseWeather');
const { meteosourceAdapter } = require('./meteosource.adapter');
// https://www.meteosource.com/
// https://open-meteo.com/en/features#available_apis

async function getWeather() {

  const params = {

    lat: "25.1627",
    lon: "55.2077",
    timezone: "UTC",
    language: "en",
    sections: "all",
    units: "metric",
    key: process.env.API_KEY,
  };

  const query = new URLSearchParams(params);

  const baseURL = "https://www.meteosource.com/api/v1/free/point";

  const fullURL = baseURL + "?" + query.toString();

  
  try {
    const response = await fetch(fullURL);
    if (!response.ok) {

      throw new Error(`Response status: ${response.status}`);
    }

    const result = await response.json();
    const hours = parseWeather(result, meteosourceAdapter);
    console.log(JSON.stringify(hours, null, 2));
  } catch (error) {
    console.error(error.message);
  }
}

getWeather()
