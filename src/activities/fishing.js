

const boatFishingPro = {
  label: "Boat Fishing Pro",

  thresholds: {
	
      tempMin: 0,
      tempMax: 0,
      douglasScaleMin: 0,     //  calm = 0 (0 m) | rough = 5 (2.5m -> 4m) | phenomenal = 9  (over 14m)
      douglasScaleMax: 9,
      swellHeightMin: 0,      // low swell = >2m   |  moderate swell = between 2.0m - 4.0m   | heavy swell = more than 4.0m
      swellHeightMax: 4,
      swellLengthMin: 0,      // short = <100m   | average = 100-200m  | long = >200m
      swellLengthMax: 200,
      tideMin: 0,             // do more research : tide in meters
      tideMax: 9,
      seaWarning: false,

  },		
};

const boatFishingLite = {
  label: "Boat Fishing Lite",

  thresholds: {
	
      tempMin: 0,
      tempMax: 0,
      douglasScaleMin: 0,     //  calm = 0 (0 m) | rough = 5 (2.5m -> 4m) | phenomenal = 9  (over 14m)
      douglasScaleMax: 9,
      tideMin: 0,             // do more research : tide in meters
      tideMax: 9,
      seaWarning: false,

  },		
};

const shoreFishing = {
  label: "Shore Fishing",

  thresholds: {
	
      tempMin: 0,
      tempMax: 0,
      douglasScaleMin: 0,     //  calm = 0 (0 m) | rough = 5 (2.5m -> 4m) | phenomenal = 9  (over 14m)
      douglasScaleMax: 9,
      tideMin: 0,             // do more research : tide in meters
      tideMax: 9,
      seaWarning: false,

  },		
};



const fishing = [boatFishingPro, boatFishingLite, shoreFishing];

module.exports = { fishing };

