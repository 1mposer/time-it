
const starGazingPro = {
  label: "Stargazing Pro",
  thresholds: {

      tempMin: 5,				//celcius
      tempMax: 30,
      cloudCoverMin: 0,				//%
      cloudCoverMax: 20,  
      atmosTransperencyMin: 3,			// Naked Eye Limiting Magnitude  (NELM) 
      atmosTrasnperencyMax: 7,			// range from 0 -> 7 | best = 7 - worst = 0
      moonPhase: ["third quarter","first quarter"],
      specialSky: ["quadrantids", "lyrids","eta aquariids","perseids","orionids","leonids", "geminids"],
      planetOppositions: ["jupiter","mars","saturn","supermoon", "beavermoon"],
  },
};

const starGazingLite = {
  label: "Stargazing Lite",
  thresholds: {

      tempMin: 5,				//celcius
      tempMax: 30,
      cloudCoverMin: 0,				//%
      cloudCoverMax: 20,
      darknessMin: 4,				//the bortle scale measures the sky darkness 
      darknessMax: 9,				// range = 1 - 9 | 9 being the best - total darkness
      totalSolarEclipse: false,

  },
};


const starGazing = [starGazingPro, starGazingLite]

module.exports = { starGazing }

