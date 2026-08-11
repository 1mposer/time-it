# DOCS_AUDIT — /docs as a product, audited for its actual users (the owner + agents)

> ✅ **EXECUTED 2026-08-10** — every containment and corrective item below landed on `reconcil` (docs commits `ebbf8c4`→); the preventive rules live in STATUS §1 and ROADMAP §Rules. This file is now the archived record of what was changed and why.

**Audit date:** 2026-08-10 · Phase 5 of the reconciliation audit (branch `reconcil`).
Method: CAPA framing (root cause → containment → corrective → preventive → verification),
applied to a 30-file, ~5,500-line docs corpus. Bias: fewer, denser, more authoritative
files. Every claim below is evidenced by a specific file/line pattern found in Phase 0–2
extraction.

---

## 1. The problem, stated as a defect

The docs corpus requires a manual reconciliation pass nearly every session and **still
drifts**. Evidence: a large fraction of all commits are `docs:` reconciliation commits
(including a move-then-revert of the #6c/#6d specs — `ff9a712`/`45e8a0b` — caused purely
by ambiguity about where a half-done spec lives); "deployed" banners sit above fully
unchecked acceptance boxes (#6c, #6d, #5c); a "✅ IMPLEMENTED, all §8 items pass" header
sits above six unticked §8 boxes (Figma foundations); the grill's "Decisions locked"
table still presents four superseded contracts as locked; ADR-0003 still pins a digest
shape ADR-0006 superseded; Guidelines.md — named "canonical" by two specs — still
carries tab-bar/sign-in/PRO rows for features that were cut and never built.

## 2. Root cause (5-Why, compact)

- **Why does it drift despite constant reconciliation?** Because each fact lives in 3–5
  files: status is quadruplicated (STATUS banner ⟷ ROADMAP ⟷ spec headers ⟷ CLAUDE
  build-order), the push contract is stated four times, visual truth three times.
- **Why is each fact multi-homed?** Because every event is recorded by *adding prose* to
  every orientation doc it touches, and superseded text is *bannered over* rather than
  edited (the #7/#8 STALE banners over live-tense bodies are the pattern at its purest).
- **Why banner-over instead of edit?** Because no rule assigns each fact class exactly
  one home — the read order (CLAUDE → CONTEXT → STATUS) defines *sequence*, not
  *ownership*, so writers defensively update everywhere and readers can't know which
  copy wins without the "truth rule" table that STATUS itself maintains.
- **Why has this held?** The practice was formed when the corpus was ~8 files (pre-#5);
  at 30 files the fan-out exceeds what a session reliably completes, so every session
  leaves a partial fan-out — which *is* the drift.

**Root cause:** *no single-home ownership rule per fact class, so every update is an
unbounded manual fan-out, and amendment-by-banner leaves the superseded text alive.*
Eliminating this explains all observed symptoms.

## 3. Containment — deletions and one-liners (one commit, do first)

| Action | File(s) |
|---|---|
| Delete | `docs/STATUS_LOG.md` (its own header forbids reading it; git history is the log) |
| Delete | `docs/issues/current/implement-spec-issue-7-marine-data.md` (KILL per PRIORITY_RESET; GitHub issue is the tombstone) |
| Delete the WeatherKit-lock notes | STATUS banner clause, OWNER_NOTES "no other agent may…" block, the Figma handoff's hands-off list (owner discarded the working tree at the gate) |
| Add missing one-line historical banners | `completed/implement-spec-issue-3…`, `-4…`, `-10…` (the only completed specs with **no** banner at all) |
| Add RESOLVED line | `docs/review/issue-5b-authoring-code-review.md` (all 7 findings fixed per STATUS_LOG 07-15 — record it before the log is deleted) |
| Annotate the four superseded grill rows | `personalization_grill.md` locked table (`bestDayIndex`, fixed-168, `floor(index/24)`, UTC-index window) + CRON P4 |
| Annotate ADR-0003's digest sentence | one line: "superseded by ADR-0006 (day-0 + week-ahead)" |
| Commit the two untracked living docs | `implementation-spec-14…` and `handoff-weatherkit-provider-abstraction.md` (analysis worth keeping; currently one `rm -rf` from gone) |

## 4. Corrective — file-by-file verdicts

### Orientation layer (the interface agents load first)

| File | Verdict | Specific change |
|---|---|---|
| `CLAUDE.md` (366) | **KEEP** — the code-truth map is the corpus's best artifact | Remove the "Current build order" section (→ one link to ROADMAP); it's the fourth status home. After the #6c/#6d specs archive, CLAUDE's push section becomes the *single* as-built push reference — already true in practice. |
| `docs/CONTEXT.md` (122) | **KEEP** — the glossary is genuinely good and single-homed | Touch only when spec 14 lands (the "Locked UX direction" parenthetical under Time-of-day window becomes as-built). |
| `docs/STATUS.md` (79 lines, but the banner + §5 are ~2,300 words) | **REWRITE to ≤ one screen** | Keep: the truth-rule table, a NOW / NEXT / BLOCKED table (≤10 rows, links only), open-blockers list (§4, pruned). Kill: the banner narrative (history → git), §5's ~1,400-word bullet — its unique facts disperse to their homes: per-issue status → ROADMAP; push/build detail → CLAUDE + the specs; session/ops facts → OWNER_NOTES. |
| `docs/issues/ROADMAP.md` (32) | **REWRITE as the single per-item status home** | Fold in PRIORITY_RESET's SHIP order (items 1–8, incl. the previously unnamed TestFlight step), the DEFER list with promote conditions, and the KILL record. One line per item: status · bucket · link. Add spec 14 and the new push-client spec; delete the "UX evolution" entry (→ pointer to spec 14). |
| `docs/OWNER_NOTES.local.md` (80) | **KEEP** — right pattern (private, factual, single-homed) | Prune resolved items: the WeatherKit-lock block, item 4 after the log-line fold-in; compress the corrected "add-on exists" note. |

### Decisions layer

| File | Verdict | Specific change |
|---|---|---|
| `docs/adr/0001–0006` | **KEEP** | ADR-0003: the one-line supersession note (§3). Optional while touching: each ADR gains a one-line `Status: Accepted (date)` header — five of six currently have none. |
| **NEW `docs/adr/0007-client-side-mirrors.md`** (~1 page) | **ADD** | Records the decision made implicitly three times and about to be made a fourth (SPEC_14_FEASIBILITY): client mirrors of server logic are the accepted price of the frozen wire; names the mirrors and the rule that threshold-semantics changes land in both engines. Must also record the weighed-and-deferred alternative — **additive per-hour tiers on the wire** (additive fields don't break the tolerant iOS decoder) — and the trigger for revisiting it: the next new mirror, or the first mirror-drift bug. The only *added* document in this audit — it removes future re-litigation, which is the test the mission set for additions. |
| `docs/personalization_grill.md` (361) | **KEEP frozen** | §3 annotations only. It stays the rationale archive; it must stop being a place where superseded contracts look current. |

### Specs layer (`docs/issues/`)

| File | Verdict | Specific change |
|---|---|---|
| `current/implement-spec-issue-6c…` (152) | **ARCHIVE** | Tick the built boxes, banner "backend ✅ deployed 2026-08-03; §9 extracted", move to `completed/`. |
| `current/implement-spec-issue-6d…` (73) | **ARCHIVE** | Same. |
| **NEW `current/implement-spec-push-client.md`** | **ADD (extraction, not addition)** | The #6c §9 client + #6d payload handling + both live-acceptance passes, written against spec 14's landed model (dormancy exclusion included). This is SHIP #6's work order; today it's smeared across two archived specs, ADR-0006, STATUS §5 and OWNER_NOTES. |
| `current/implementation-spec-14…` (231) | **KEEP (the living spec)** | Annotate with the gate outcome: §4 flex and the wizard reading of §6 marked DEFERRED per SPEC_14_FEASIBILITY; commit it; give it a ROADMAP row. |
| `current/implement-spec-issue-8…` (50) | **SHRINK to a ~15-line stub** | Capability + the kind-validation gap + promote conditions. The body is pre-rebuild fiction the banner already disowns; the stub keeps the knowledge, deletes the trap. |
| `current/design-decisions-issue-5.md` (147) | **SPLIT** | SF-Symbols manifest + card anatomy → `Guidelines.md`; the rest (nav model, mockup-mismatch table — both now as-built) → `completed/` with a banner. |
| `current/handoff-weatherkit…` (216) | **MOVE to `completed/`** with a `DEFERRED post-ship (owner 2026-08-10) — input to the future provider ADR` banner | It is good analysis; it is not current work. |
| `completed/*` (9 files) | **KEEP as history** | Banners only (§3). Rule R2 below ends the body-reconciliation practice — completed bodies are records of what was believed, never edited again. |

### Design & iOS layer

| File | Verdict | Specific change |
|---|---|---|
| `docs/design/figma_foundations…` (172) + `current/handoff-figma-design-iteration.md` (182) | **MERGE → `docs/design/FIGMA.md`** (~120 lines) | Keep: fileKey + page map, the Semantic token table with VariableIDs, the PUA codepoint table (explicitly non-re-derivable on Linux), the approval-gate protocol, the tool gotchas. **Resolve C6 in writing:** `Theme colors` = frozen as-built code mirror until spec 14's rendering lands, then retired; `App Colors` = legacy, bound by the wizard mind-map, never bind new work. Both source files delete (foundations' build story → one history line). |
| `ios/guidelines/Guidelines.md` (169) | **EDIT — make canonical mean canonical** | *Delete* the cut-feature rows the scope note merely disclaims (tab bar, sign-in entries, PRO badge, `-pro` suffix rule); fix the header-placeholder note (live since 2026-07-12) and the fixed "6am–12am" timeline axis (global indices since #5a); absorb the symbols manifest + card anatomy from design-decisions. Two specs call this file the source of truth — it currently lies in five places. |
| `ios/GLOSSARY.md` (117) | **KEEP** | Refresh tags during the spec 14 build (dormant/gradient/range-first become shipped; add the #5c location terms it's missing). |
| `ios/README.md` (9) | **EDIT** | Point at `completed/`, add #5c to the lineage. |
| `README.md` (66) | **EDIT (low priority)** | Fix the Pro line ("deferred", not "enforced"), "7-day" → "up to 7-day", push "not yet built" → "backends live, client pending". |
| `docs/review/deep-modules-review.md` (153) | **EDIT** | Clear the volatile §3 (it describes June's "about to be bound by #5a" moment as *now*); the durable charter stays. |
| `docs/API_documentation/` | **KEEP untouched** | The exemplary pattern — single-homed vendor facts, agent-trimmed, dated. The FIGMA.md merge deliberately copies this shape. |
| These five audit files | **SELF-RULE** | After the owner consumes them: PRIORITY_RESET's tables fold into ROADMAP; the other four move to `docs/audit-2026-08-10/` or `completed/`. The audit must not become a sixth status home. |

**Net effect:** ~30 project docs → ~24; roughly 700–900 lines deleted against ~140 added
(ADR-0007 + the push-client spec, both extractions of existing knowledge); status homes
4 → 2; every one of the 19 contradiction sites itemized in Phases 0–2 closed.

## 5. Preventive — four rules, no new tooling

1. **Single home per fact class.** Per-item status lives *only* in ROADMAP; the
   now/next/blocked snapshot *only* in STATUS; code-as-built *only* in CLAUDE.md;
   decisions *only* in ADRs; vendor facts *only* in `API_documentation/`. Everything
   else links. A fact stated twice is a bug.
2. **Specs die on completion.** The merge commit that completes an issue also ticks its
   boxes, adds the one-line banner, and moves it to `completed/`. Completed bodies are
   never edited again — they are records, not truth.
3. **Supersede by editing the loser.** An amendment is not done until the superseded
   text carries the annotation, in the same commit. (This rule alone would have
   prevented the ADR-0003, grill, foundations-header, and Guidelines failures.)
4. **`current/` holds only living work orders.** Reference docs live in their layer;
   handoffs carry a fold-in-by date at creation and die on schedule.

## 6. Effectiveness verification (reuses an existing practice — adds nothing)

The repo already runs occasional "stale-test" sessions (`068b346`). Run one ~2 weeks
after the corrective commit lands. **Pass criteria:** a fresh agent, given only the read
order (CLAUDE → CONTEXT → STATUS → ROADMAP), states what to build next, what's blocked,
and the current contracts — with zero contradictions encountered and zero questions the
owner must answer from memory. **Fail** (any contradiction found) reopens this audit's
§2 root cause, not just the symptom.

## 7. The four reader-burden questions, answered directly

- **Where does a reader hold too much in their head?** STATUS §5 (one ~1,400-word bullet
  mixing twelve concerns); starting the push client today requires synthesizing five
  documents (#6c §9, #6d payload, ADR-0006, STATUS §5, OWNER_NOTES) — the new spec
  collapses it to one.
- **What is stale/duplicated/contradicted?** Itemized in §1, §3, §4 — nineteen sites,
  each with its fix above.
- **What decision does a doc fail to record?** The client-mirror policy (→ ADR-0007);
  the ship/distribution step (→ ROADMAP); the wizard-vs-editor reading of spec 14
  (→ SPEC_14_FEASIBILITY, now recorded); Figma token authority (→ FIGMA.md).
- **What is missing for an agent to start without re-explanation?** The push-client
  spec (→ NEW), the TestFlight runbook line in ROADMAP, and honest banners on the three
  banner-less completed specs.
