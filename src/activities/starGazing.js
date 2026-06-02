// DEFERRED: starGazingPro requires atmosTransparency, moon phase matching,
// meteor shower calendar, and planet opposition data. None of these are
// provided by Meteosource. Implement when an astronomy data source is integrated.
//
// const starGazingPro = {
//   id: "stargazing-pro",
//   label: "Stargazing Pro",
//   thresholds: {
//     temp:               { min: 5, max: 30, required: true  },
//     cloudCover:         { max: 20,          required: true  },
//     atmosTransparency:  { min: 3, max: 7,   required: false },  // NELM scale 0-7
//     moonPhase:          ["third quarter", "first quarter"],     // calendar lookup needed
//     specialSky:         ["quadrantids", "lyrids", ...],        // calendar lookup needed
//     planetOppositions:  ["jupiter", "mars", ...],              // calendar lookup needed
//   },
// };

// DEFERRED: totalSolarEclipse removed from starGazingLite thresholds.
// The engine's flag type only supports forbidTrue (penalise when an alert is present).
// A solar eclipse is an event you want to be present — "require true" — which the engine
// cannot currently express. Tracked in Issue #8 (implement-spec-issue-8-require-true-threshold.md).

const starGazingLite = {
  id: "stargazing-lite",
  label: "Stargazing Lite",
  displayMetrics: ["temp", "cloudCover"],
  thresholds: {
    temp:       { min: 5, max: 30, required: true  },
    cloudCover: {         max: 20, required: true  },  // % cloud cover; must be near-clear
    darkness:   { max: 4,          required: false },  // Bortle scale 1-9; 1=darkest (best); ≤4 = rural sky — NOTE: parse.js hardcodes 0, trivially passes until astronomy data source integrated
  },
};

const starGazing = [starGazingLite];

module.exports = { starGazing };
