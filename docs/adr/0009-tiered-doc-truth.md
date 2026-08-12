# Tiered doc truth — volatile facts have one home; contract facts may be mirrored

Status: Accepted (2026-08-12, owner-ruled after the redundancy-audit adjudication). Amends the absolute "a fact stated in two homes is a bug — link, don't restate" rule (STATUS §1, 2026-08-10).

**Decision.** Documentation truth is tiered by *volatility*, not policed as zero-duplication:

- A **volatile fact** is true *as of a date* — status, plan/tier names, built/unbuilt, dates, in-flux product decisions. Test: *can this sentence become false just by the project moving forward?* A volatile fact lives in **exactly one** home (the STATUS §1 table); everywhere else links.
- A **contract fact** is a timeless rule — wire shapes, semantics, invariants. It only changes by deliberate redesign. It **may** be restated where readers need it inline (CLAUDE.md stays a self-contained onboarding file); the owner file is the reference of record, and changing a contract fact means sweeping its mirrors in the same change.

**The two-home UI rule (same ruling).** Design values — tokens, palette, type, spacing, geometry, frame contents — are never homed in a doc. Their **design truth** is the Figma file itself (docs carry only *addresses*: fileKey, node IDs, page map, gate state — `docs/design/FIGMA.md`); their **shipped truth** is the code (`Theme.swift`, the SwiftUI views). The Figma MCP server makes the file agent-queryable, so a value table in markdown is a stale cache of an API the agent can call.

**Why.** The 2026-08-11 redundancy audit ([`docs/audit/AI_audit/`](../audit/AI_audit/)) found ~45 restated facts, 11 already drifted. The adjudication (2026-08-12, same dir) established two empirical regularities: **every drift was in a non-owner copy** (the declared owner files and the code were right in all 11 disputes), and **only volatile facts drifted** — stable contract facts sat in up to 7 copies with zero decay. Drift tracks rate-of-change, not copy count. The absolute rule therefore aimed at the wrong target: it condemned the harmless mirrors that make CLAUDE.md self-contained while doing nothing extra for the volatile facts that actually rot. Under the tiered rule, a status change is a one-file edit, and CLAUDE.md keeps the full wire contract inline for every agent session.

The living statement of the rule (with the ownership table) is STATUS §1; CLAUDE.md's read-order paragraph carries the discovery pointer. Truth rulings adjudicated alongside this decision (showcase card = stored dormant Activity; the 5-screen wizard; delete-all re-seeds) are recorded in [`docs/audit/AI_audit/RESOLUTION_2026-08-12.md`](../audit/AI_audit/RESOLUTION_2026-08-12.md) and applied to their owner docs.
