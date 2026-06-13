const { evaluate } = require('./decision_engine');
const { activities } = require('../activities/index');

function evaluateAll(hours) {
  const results = [];

  for (const activity of activities) {
    const window = evaluate(hours, {
      activityId: activity.id,
      thresholds: activity.thresholds,
    });

    const result = {
      activityId:     activity.id,
      label:          activity.label,
      displayMetrics: activity.displayMetrics,
      rating:         window.rating,
    };
    if (window.rating !== null) {
      result.startIndex = window.startIndex;
      result.endIndex   = window.endIndex;
      result.duration   = window.duration;
    }
    results.push(result);
  }

  return results;
}

module.exports = { evaluateAll };
