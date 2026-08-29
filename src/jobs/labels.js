// Clock-label copy shared by both push jobs — the server-side twin of the iOS
// RangeText (ADR-0007 mirror; TimeDeriver.rangeLabel routes through it). A copy
// change here lands there in the same wave — both suites pin the shared table
// in tests/fixtures/clock-labels.json. Known limitation: half-hour zones
// (e.g. +05:30) render these labels :30 off.

function hourLabel(h) {
  if (h === 0) return '12am';
  if (h === 12) return '12pm';
  return h < 12 ? `${h}am` : `${h - 12}pm`;
}

// "7–10am" when both ends share a meridiem, "10pm–2am" when crossing.
function rangeLabel(startH, endH) {
  const start = hourLabel(startH);
  const end = hourLabel(endH);
  return start.slice(-2) === end.slice(-2) ? `${start.slice(0, -2)}–${end}` : `${start}–${end}`;
}

module.exports = { hourLabel, rangeLabel };
