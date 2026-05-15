


const activities = {


  volleyball:{
	label: "Volleyball",
	thresholds: {

	  tempMin: 15,						//celcius
	  tempMax: 35,
	  humidityMax: 60,					//%
	  windMax: 15,						//km/h
	  uvMax: 6,						//UV index
	  dustAlert: false,					//No dust storms allowed

    },
  },
	stargazing: {
		label: "Stargazing",
		thresholds: {
			stargazingPro: {

		  		tempMin: 5,					//celcius
		  		tempMax: 30,
		  		cloudCoverMin: 0,				//%
		  		cloudCoverMax: 20,  
		  		atmosTransperencyMin: 3,			// Naked Eye Limiting Magnitude  (NELM) 
		  		atmosTrasnperencyMax: 7,			// range from 0 -> 7 | best = 7 - worst = 0
		  		moonPhase: ["third quarter","first quarter"],
				specialSky: ["quadrantids", "lyrids","eta aquariids","perseids","orionids","leonids", "geminids"],
				planetOppositions: ["jupiter","mars","saturn","supermoon", "beavermoon"],
			},

			stargazingLite: {

				tempMin: 5,					//celcius
		  		tempMax: 30,
		  		cloudCoverMin: 0,				//%
		  		cloudCoverMax: 20,
				darknessMin: 4,				//the bortle scale measures the sky darkness 
				darknessMax: 9,				// range = 1 - 9 | 9 being the best - total darkness
				totalSolarEclipse: false,
			},
      boatFishing: {

        tempMin: 0,
        tempMax: 0,
        douglasScaleMin: 0,     //  calm = 0 (0 m) | rough = 5 (2.5m -> 4m) | phenomenal = 9  (over 14m)
        douglasScaleMax: 9,
        swellHeightMin: 0,      //  low swell = >2m   |  moderate swell = between 2.0m - 4.0m   | heavy swell = more than 4.0m
        swellHeightMax: 4,
        swellLengthMin: 0,      // short = <100m   | average = 100-200m  | long = >200m
        swellLengthMax: 200,
        tideMin: 0,             // do more research : tide in meters
        tideMax: 9,
        seaWarning: false,



      },

		},

	},

}

module.exports = { activities };

















