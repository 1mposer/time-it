const boatFishingPro = {
  id: "boat-fishing-pro",
  label: "Boat Fishing Pro",
  displayMetrics: ["temp"],
  thresholds: {
    temp:         { min: 10, max: 40,  required: true  },
    douglasScale: {          max: 3,   required: true  },  // 0=calm 3=slight 5=rough 9=phenomenal
    swellHeight:  {          max: 2.5, required: true  },  // metres; >4m = heavy swell
    swellLength:  {          max: 200, required: false },  // metres
    seaWarning:   { forbidTrue: true, type: "flag", required: true },
  },
};

const boatFishingLite = {
  id: "boat-fishing-lite",
  label: "Boat Fishing Lite",
  displayMetrics: ["temp", "windSpeed"],
  thresholds: {
    temp:       { min: 10, max: 40, required: true  },
    windSpeed:  {          max: 25, required: true  },
    seaWarning: { forbidTrue: true, type: "flag", required: true },
  },
};

const shoreFishing = {
  id: "shore-fishing",
  label: "Shore Fishing",
  displayMetrics: ["temp", "windSpeed"],
  thresholds: {
    temp:         { min: 15, max: 38, required: true  },
    windSpeed:    {          max: 20, required: false },
    douglasScale: {          max: 4,  required: false },
    seaWarning:   { forbidTrue: true, type: "flag", required: true },
  },
};

const fishing = [boatFishingPro, boatFishingLite, shoreFishing];

module.exports = { fishing };
