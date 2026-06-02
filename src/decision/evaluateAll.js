const { evaluate } = require('./decision_engine');
const { activities } = require('../activities/index');

function evaluateAll(hours) {
  const results = [];

  for (const activity of activities) {
    const window = evaluate(hours, {
      activityId: activity.id,
      thresholds: activity.thresholds,
    });
    results.push({
      ...window,
      label: activity.label,
      displayMetrics: activity.displayMetrics,
    });
  }

  return results;
}

module.exports = { evaluateAll };
