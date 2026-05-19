const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluate } = require("../../src/decision/decision_engine");

const prefs = {
  activityId: "volleyball",
  thresholds: {
    temp:     { min: 15, max: 35, required: true },
    humidity: { max: 60,          required: true },
  },
};

// helper: build a 24-hour forecast where every hour is Perfect
function perfectHours(startClockHour) {
  return Array.from({ length: 24 }, (_, i) => ({
    hour:     (startClockHour + i) % 24,
    temp:     25,
    humidity: 40,
  }));
}

// helper: build a forecast from an array of {pass} flags
function hoursFromPasses(passes) {
  return passes.map((pass, i) => ({
    hour:     i,
    temp:     pass ? 25 : 100,   // fail required temp threshold when !pass
    humidity: 40,
  }));
}

test("midnight-crossing 24-hour Perfect window", () => {
  const result = evaluate(perfectHours(15), prefs);
  assert.deepEqual(result, {
    rating: "perfect",
    activityId: "volleyball",
    startIndex: 0,
    endIndex: 24,
    duration: 24,
  });
});

test("single-hour Perfect window surrounded by Bad", () => {
  const passes = Array(24).fill(false);
  passes[5] = true;
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.startIndex, 5);
  assert.equal(result.endIndex, 6);
  assert.equal(result.duration, 1);
});

test("no qualifying hours returns null-rating shape", () => {
  const passes = Array(24).fill(false);
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.deepEqual(result, { rating: null, activityId: "volleyball" });
});

test("Perfect window preferred over longer Good window", () => {
  // 2 Perfect hours, then 5 Good hours (humidity high but not required-failing)
  // Configure thresholds so humidity is non-required
  const localPrefs = {
    activityId: "volleyball",
    thresholds: {
      temp:     { min: 15, max: 35, required: true },
      humidity: { max: 60,          required: false },
    },
  };
  const hours = [
    { hour: 0, temp: 25, humidity: 40 }, // perfect
    { hour: 1, temp: 25, humidity: 40 }, // perfect
    { hour: 2, temp: 25, humidity: 90 }, // good (humidity fails, but not required)
    { hour: 3, temp: 25, humidity: 90 }, // good
    { hour: 4, temp: 25, humidity: 90 }, // good
    { hour: 5, temp: 25, humidity: 90 }, // good
    { hour: 6, temp: 25, humidity: 90 }, // good
  ];
  // pad to 24
  while (hours.length < 24) hours.push({ hour: hours.length, temp: 100, humidity: 40 });
  const result = evaluate(hours, localPrefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.duration, 2);
});

test("Perfect run ending at the last array element is captured", () => {
  const passes = Array(24).fill(false);
  passes[22] = true;
  passes[23] = true;
  const result = evaluate(hoursFromPasses(passes), prefs);
  assert.equal(result.rating, "perfect");
  assert.equal(result.startIndex, 22);
  assert.equal(result.endIndex, 24);
  assert.equal(result.duration, 2);
});
