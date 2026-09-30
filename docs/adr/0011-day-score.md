# Day score — a 1–100 per-day confidence number on each `days[]` bucket

Status: **Accepted** (owner, 2026-10-01 — as drafted, including the one-sided-binary, clamp-to-1, and empty-window-null calls). Drafted 2026-09-30 from the owner's Figma formula note (node `457:446`, [FIGMA.md §11](../design/FIGMA.md)); §11 frames owner-approved 2026-09-30. Build orders: `docs/issues/current/implementation_spec_01-day-score-server.md` / `implementation_spec_02-ios-score-ring.md`.

**Decision.** Each entry in an activity's `days[]` gains one **additive, optional** wire field: `score` — an integer `1..100`, or `null`. It is the number the card v2 ring draws and the detail v3 hero reads. Nothing else on the wire changes; the request shape and `validateRatingRequest` are untouched.

**Formula** (the owner's note, made precise — computed in the decision module from the same window-filtered, night-stitched hour-slices the rating uses):

- **Per hour, per thresholded metric** — a *depth-in-band* score `0..100`:
  - **Two-sided numeric band** (`min` and `max`): linear — `0` at either edge, `100` at the band centre. Outside the band: `0`.
  - **One-sided numeric band** (`min`-only or `max`-only): the note's "centre" is undefined, so the rule is **binary — `100` inside, `0` outside**. *Recorded simplification:* a graded one-sided score needs a per-metric reference span the metric catalog doesn't carry; if the ring reads too flat on one-sided-heavy activities (e.g. a `max`-only `windSpeed`), revisit by adding catalog spans — a formula change inside this ADR's frame, not a wire change.
  - **Flag threshold** (`forbidTrue`): `false` → `100`, `true` → `0`.
  - **Missing data** (`null`/absent value): scores `0` — same posture as `checkThreshold`'s B2 rule (absent data fails, never passes silently).
- **Required miss zeroes the hour**: if any `required: true` threshold fails in that hour, the hour's score is `0` regardless of the other metrics (mirrors the hour turning Bad).
- **Hour score** = mean over the activity's *thresholded* metrics only — display-only metrics (`displayMetrics` beyond `thresholds`) never contribute, and `moon`/coming-soon metrics can't appear here at all (they are unthresholdable, [metric catalog](../../src/weather/metricCatalog.js)).
- **Day score** = mean over the bucket's window hours, rounded to the nearest integer, then **clamped to `1..100`** — an all-zero day renders as `1`, so the ring always has a drawable numeral; the tier colour, not the 0-vs-1 distinction, carries the verdict (numeral colour follows the rating tier — design truth in the §11 frames).

**Null rule.** `score` is `null` **iff the bucket contains zero window hours** (e.g. a day-0 whose entire Range is already past the forecast start, or a provider-truncated tail bucket). A rating-`null` day with hours present still gets a real (low) score — score and rating are computed independently.

**Independence rule (the false-Perfect firewall).** The score is display-only and **never feeds the rating**, the digest, or the Perfect-window detector — `evaluateHour`/`findLongestWindow` don't read it, push copy doesn't mention it. It is a derived number *beside* the verdict, not a second verdict.

**Client rule.** The iOS decoder treats an absent or unrecognized `score` as `null` (the 2026-07-12 hardening posture: a missing field can never fail the decode); a `null` score renders the ring empty. No new backend is needed for the detail's per-hour values — `hours[]` already carries them; only the per-day score is new. *(The per-hour scores behind the detail's strip are recomputed client-side from the same thresholds — an accepted ADR-0007-style mirror; the wire carries only the day number.)*

**Why.** The card v2 brief (owner, 2026-09-21) makes the card wordless beyond name, numerals and colour — the ring needs one number that means "how confidently does the forecast fit what you asked for." Depth-in-band is that number: it degrades smoothly as conditions drift toward a threshold edge, unlike the three-tier rating which snaps. Computing it server-side in the engine keeps the two sides from drifting (the ADR-0007 lesson) and gives the push path the same number for free if a future digest wants it — while the independence rule keeps it from ever contaminating the verdict the way a placeholder-fed threshold would (the [ADR-0005](0005-custom-activity-request-schema.md) false-Perfect backstop, applied to derived numbers).

**Consequences.** CLAUDE.md's wire-contract mirror gets the `score` field in the same change that ships the engine work (contract fact — sweep rule, [ADR-0009](0009-tiered-doc-truth.md)). Tests pin worked examples: two-sided centre/edge/outside, one-sided binary, flag, required-miss zeroing, the null rule on an empty-window bucket, and a hand-computed nocturnal bucket. `days[]` key order gains `score` after `duration`; the golden snapshot test updates in the same commit.
