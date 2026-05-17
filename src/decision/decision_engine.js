
function checkThreshold(value, config) {
  if (config.min !== undefined && value < config.min) return false;
  if (config.max !== undefined && value > config.max) return false;
  return true;
}

function evaluateHour(hourData, thresholds) {
  let allPass = true;
  let allRequiredPass = true;

  for (const [metric, config] of Object.entries(thresholds)) {
    const passes = checkThreshold(hourData[metric], config);
    if (!passes) {
      allPass = false;
      if (config.required) allRequiredPass = false;
    }
  }

  if (allPass) return "perfect";
  if (allRequiredPass) return "good";
  return "bad";
}

function findLongestRun(ratedHours, rating) {
  let best = null;
  let current = null;

  for (const ratedHour of ratedHours) {
    if (ratedHour.rating === rating) {
      if (!current) current = { startHour: ratedHour.hour, endHour: ratedHour.hour + 1, duration: 0 };
      current.endHour = ratedHour.hour + 1;
      current.duration++;
    } else {
      if (current && (!best || current.duration > best.duration)) best = { ...current };
      current = null;
    }
  }
  if (current && (!best || current.duration > best.duration)) best = { ...current };

  return best;
}

function evaluate(hours, userPrefs) {
  const ratedHours = hours.map((h) => ({
    hour: h.hour,
    rating: evaluateHour(h, userPrefs.thresholds),
  }));

  const perfectWindow = findLongestRun(ratedHours, "perfect");
  if (perfectWindow) return { rating: "perfect", ...perfectWindow };

  const goodWindow = findLongestRun(ratedHours, "good");
  if (goodWindow) return { rating: "good", ...goodWindow };

  return null;
}

module.exports = { evaluate };
