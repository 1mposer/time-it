


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

		},

	},

}
	

















