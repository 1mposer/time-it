// this file is used to fetch data about the weather baby...
//https://www.meteosource.com/
//https://open-meteo.com/en/features#available_apis

async function getWeather() {

  const url = "https://www.meteosource.com/api/v1/free/nearest_place?lat=25.1627&lon=55.2077&key=";

  const params = new URLSearchParams({

    timezone: "UTC",
    language: "en",
    sections: "all",
    lat: "25.1627",
    lon: "55.2077",
    units: "metric",
    key: "",


  })


}


  try {
    const response = await fetch(url);
    if (!response.ok) {

      throw new Error('Response status: ${response.status}');
    }

    const result = await response.json();
    console.log(result);
  } catch (error) {
    console.error(error.message);
  }
}

getWeather()
