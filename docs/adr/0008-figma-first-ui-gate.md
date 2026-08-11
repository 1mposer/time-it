# UI is Figma-first — frames precede code

Status: Accepted (2026-08-11, owner directive). Reverses the spec 14 cut's §9 decoupling ("code does not wait on frames", 2026-08-10).

**Decision.** Every UI change, addition, or edit is applied in Figma — and owner-approved — **before** it reaches code. No provisional rendering, no "reconcile later". Pure logic (services, store semantics, wire projections, tests) has no Figma surface and is not gated: the gate is on rendering, not on models.

**Why.** Figma is the developer's UI interface for this application: the design file is where UI is seen, steered, and approved. Code carrying UI the file has never shown is code the owner never reviewed. The design file may run ahead of the app; the app must never run ahead of the design file.

Operating procedure, page map, and the current frame backlog live in [`docs/design/FIGMA.md`](../design/FIGMA.md) (§6 gate, §7 backlog).
