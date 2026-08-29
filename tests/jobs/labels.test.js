const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { hourLabel, rangeLabel } = require('../../src/jobs/labels');

// Cross-repo pinned table (ADR-0007): the same fixture pins the iOS RangeText
// mirror (RangeTextTests reads it via #filePath). A copy change edits the
// fixture once and both suites must follow.
const table = JSON.parse(fs.readFileSync(path.join(__dirname, '../fixtures/clock-labels.json'), 'utf8'));

test('hourLabel matches the shared clock-label table', () => {
  for (const [hour, label] of Object.entries(table.hourLabels)) {
    assert.equal(hourLabel(Number(hour)), label);
  }
});

test('rangeLabel matches the shared clock-label table', () => {
  for (const { startHour, endHour, label } of table.rangeLabels) {
    assert.equal(rangeLabel(startHour, endHour), label);
  }
});
