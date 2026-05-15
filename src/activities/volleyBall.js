
const volleyBall = {
  label: "Volleyball",
  thresholds: {

      tempMin: 15,					//celcius
      tempMax: 35,
      humidityMax: 60,					//%
      windMax: 15,					//km/h
      uvMax: 6,						//UV index
      dustAlert: false,					//No dust storms allowed

  },
};

module.exports = {volleyBall}

