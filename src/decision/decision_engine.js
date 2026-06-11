function checkThreshold(value, config) {
  // Absent data fails the threshold rather than silently passing via NaN/0 coercion.
  if (value === null || value === undefined) return false;
  if (config.type === "flag" && config.forbidTrue && value === true) return false;
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

function findLongestWindow(ratings, targetRating) {
  let best = null;
  let current = null;

  for (let i = 0; i < ratings.length; i++) {
    if (ratings[i] === targetRating) {
      if (!current) current = { startIndex: i, endIndex: i + 1, duration: 1 };
      else {
        current.endIndex = i + 1;
        current.duration++;
      }
    } else {
      // Strict `>` — on a tie, the earlier window wins (iOS shows the earlier block).
      if (current && (!best || current.duration > best.duration)) best = current;
      current = null;
    }
  }
  if (current && (!best || current.duration > best.duration)) best = current;

  return best;
}

function evaluate(hours, userPrefs) {
  const ratings = hours.map((h) => evaluateHour(h, userPrefs.thresholds));

  const perfectWindow = findLongestWindow(ratings, "perfect");
  if (perfectWindow) {
    return { rating: "perfect", activityId: userPrefs.activityId, ...perfectWindow };
  }

  const goodWindow = findLongestWindow(ratings, "good");
  if (goodWindow) {
    return { rating: "good", activityId: userPrefs.activityId, ...goodWindow };
  }

  return { rating: null, activityId: userPrefs.activityId };
}

module.exports = { evaluate };
