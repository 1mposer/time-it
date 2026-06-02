const volleyBall = [
  {
    id: "volleyball",
    label: "Volleyball",
    displayMetrics: ["temp", "windSpeed", "humidity", "uV"],
    thresholds: {
      temp:      { min: 15, max: 35, required: true  },
      humidity:  {          max: 60, required: true  },
      windSpeed: {          max: 15, required: false },
      uV:        {          max: 6,  required: false },
      dustAlert: { forbidTrue: true, type: "flag", required: true },
    },
  },
];

module.exports = { volleyBall };
