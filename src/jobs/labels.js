// Clock-label copy shared by the push jobs (#6c digest, #6d detector) — the
// server-side twin of the iOS TimeDeriver. Known shared limitation (STATUS §5):
// half-hour zones (e.g. Asia/Kolkata +05:30) render these ha-style labels :30
// off — cosmetic, tracked.

function hourLabel(h) {
  if (h === 0) return '12am';
  if (h === 12) return '12pm';
  return h < 12 ? `${h}am` : `${h - 12}pm`;
}

function rangeLabel(startH, endH) {
  const start = hourLabel(startH);
  const end = hourLabel(endH);
  // Same meridiem → suffix once ("7–10am"); crossing → both ("10pm–2am").
  return start.slice(-2) === end.slice(-2) ? `${start.slice(0, -2)}–${end}` : `${start}–${end}`;
}

module.exports = { hourLabel, rangeLabel };
