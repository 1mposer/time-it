# SPEC_14_FEASIBILITY — audit of the dashboard rework against the reset priorities

**Audit date:** 2026-08-10 · Phase 4 of the reconciliation audit (branch `reconcil`).
Subject: `implementation-spec-14-dashboard-rework.md` (locked 2026-08-09, unbuilt,
untracked in git and absent from the ROADMAP).

> ⚠️ **Partially superseded 2026-08-11 ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)):**
> the cut's **§9 DEFER is reversed** — frames now gate the spec 14 rendering. The wizard
> and ±1h deferrals stand. The body below is the 2026-08-10 record, unedited.

---

## Verdict

**Split verdict:**

- **The minimal cut (§ "Smallest version" below): FEASIBLE NOW**, after exactly one
  prerequisite — SHIP #1, discarding the phantom-locked working tree so
  `AuthoredActivity.swift` and the project file are free (owner already decided this at
  the gate).
- **The full spec as written: FEASIBLE AFTER** two things exist that it silently assumes:
  (1) a written, reviewed spec for the 4-step wizard — today the wizard exists only as
  Figma frames, the ROADMAP still calls its spec "deliberately unwritten," and the built
  app has only the #5b `AddActivityView` → `ActivityEditorView` flow; (2) the §9 Figma
  catch-up frames approved through the established approval gate, which sits on the
  owner + Figma-agent track, not on this codebase.
- **NOT FEASIBLE for any part: nothing.** The spec is unusually precise for its size;
  its gaps are enumerable (below), not structural.

## Critical path — answered first, plainly

As specced on 2026-08-09, the rework was **adjacent** to the provable use case: the
dashboard already renders truthful day-0 verdicts, and the trust problem it fixes was
diagnosed with zero users. **The owner promoted it into ship scope at the 2026-08-10
gate** ("more reliable visual information … removes the redundancy in the details
page") — that is a legitimate scope decision and is now recorded; the honest cost
statement is that it lengthens the path to TestFlight by the size of the cut, and the
audit's job becomes making that cut as small as possible. Bucket: **SHIP (minimal cut)**,
**DEFER (wizard + flex)**.

## Shared surfaces touched; what it blocks, unblocks, constrains

| Surface | Effect |
|---|---|
| S4 `AuthoredActivity`/`ActivityStore` | **Redefines `window == nil`** (whole-day → dormant) and deletes the editor's whole-day path. This is the deepest semantic change — every consumer of the store (POST projection, future snapshot projection, card rendering) reads the new meaning. |
| S5 device snapshot | Changes what clients *send* (dormant exclusion; §4 would send widened windows). **This is why spec 14 must precede the push client (SHIP #5 before #6):** build the snapshot projection once, against the final model. |
| S2 evaluation semantics | Adds `HourQuality`, the fourth client-side mirror of server logic, against ADR-0002's explicit "two engines drift" rejection (INTERFACE_MAP C2). Not a reason to block — the wire-freeze makes it the only move — but the decision should stop being implicit: **write a one-page ADR-0007 ("client-side mirrors are the accepted price of the frozen wire; current mirrors: metric catalog, clock labels, hour evaluation; every threshold-semantics change lands in both engines")**. #8's DEFER entry now carries that tax explicitly. |
| S8 Figma | §9 requires a catch-up pass on the same pages where the two Figma docs already contradict each other (C6). The cut decouples code from this. |
| Wire contract | **Zero server diffs — verified genuine.** The spec's own fence holds everywhere in its text; `window` stays optional on the wire, so the deferred whole-day "surprise" feature (ios/GLOSSARY.md) loses its client UI but keeps its wire optionality. |

**Blocks:** nothing (it is the front of the iOS queue once unlocked).
**Unblocked by:** SHIP #1 only.
**Silently constrains:** #8 (`requireTrue` must be implemented twice once `HourQuality`
exists); any future "server returns per-hour tiers" wire evolution (the mirror becomes
dead weight — acceptable, now recorded); seed/template UX (prefills replace #5b's
active-by-default seeding).

## Internal completeness — every point where an agent must invent

The spec is strong: pinned invariant (§3), full test list (§10), acceptance criteria,
explicit vocabulary. Remaining inventions, ranked:

| # | Gap | Forced invention | Severity |
|---|---|---|---|
| I1 | **§6 is written against "the designed 4-step wizard" — which is not in the codebase.** No file, no spec; ROADMAP says its spec is deliberately unwritten. | The agent must either *build* a whole wizard (unscoped, unreviewed — roughly the size of the rest of the spec combined) or *reinterpret* every wizard reference onto the #5b editor. | **Blocking for the full spec; resolved by the cut** (below: editor-retrofit, wizard deferred). |
| I2 | **All-dormant header state.** §1: all-dormant makes no network call — but `HeaderView` renders current-hour temp/wind/humidity from `hours[0]`, which now doesn't exist. | A header placeholder/dormant state (and its relationship to the #5c no-location empty state) must be designed. | Medium — small work, but visible on first launch, the worst place to improvise. **Note:** the owner's own existing device install lands in exactly this state on first post-update launch (its seeded whole-day activities become dormant) — expected behavior, name it in the acceptance pass so it isn't triaged as a regression. |
| I3 | **Phrase strings.** §5 gives one example ("Good, turning perfect") + "Mixed conditions"; the other eight of the ten strings and the Settings row copy are "TBD in the design pass." | Eight user-facing strings. | Low-medium — invent provisionally, owner reviews; strings are cheap to change. |
| I4 | **§9 sequencing ambiguity.** "Code does not wait on pixel-perfect frames for the mechanical parts, but card/detail rendering should track the approved frames" — the approval gate is owner-paced and external. | Which rendering decisions may proceed unapproved. | Medium for the full spec; **the cut resolves it**: data layer + provisional rendering now, visual polish tracks frames when approved, explicitly not gating TestFlight. |
| I5 | **Flex copy semantics (§4).** The widened window reaches the digest/detector, so push copy can name shoulder hours the user never picked, while the toggle's own caption promises "we'll also *watch*" (window unchanged in the user's mental model). | Whether push copy may name flex hours. | **Removed by the cut** (flex deferred). |
| I6 | **Gradient mechanics.** Stops per hour boundary vs per hour, blend width, the §3 invariant test's tolerance when two equal-length greenest runs exist (server tie-breaks earlier; the gradient shows both). | Stop-placement math; tie-tolerant test assertion. | Low — §10's test list constrains it enough. |
| I7 | **Detail red-day row.** §7 row = "day name · best-stretch time · bar"; a red day has no stretch. | Apply §2's rule (plain day name). | Trivial. |

## The smallest version that still serves the use case (the cut)

Owner-weighted: the two values named at the gate are the **truthful card gradient** and
the **de-redundant detail page**. The cut keeps both and everything they stand on:

**KEEP —**
- **§1 dormancy + mandatory range, retrofitted onto the existing editor** (no wizard):
  delete the "Only at certain hours" toggle, make the range pickers a required section,
  `nil` window renders the dormant "Set your range →" card, dormant excluded from the
  POST, all-dormant makes no request (with the I2 header state resolved), first-launch
  seeds land dormant.
- **§3 `HourQuality`** + the §3 fixture invariant (with the I6 tie-tolerant assertion).
- **§2 the gradient card** — gradient slice, no rating word, "Today · 6–8pm" sublabel,
  all-bad = solid red.
- **§6 prefills as editor prefills** — template tap opens the editor with the prefill
  table's range loaded but unsaved (confirmation = saving), which honors "prefills,
  never active defaults" without a wizard.
- **§7 the detail redesign** — header/setup-once/aligned range-zoomed week/tap-to-expand
  (the owner's second named value).
- **§5 phrases** — cheap (ten strings, one reduction rule) and **required anyway**: the
  Differentiate Without Color force-path is the accessibility answer for a card whose
  default carrier is color alone. Ship it; the Settings row copy is I3.
- **§8 nocturnal parity** — free by construction.
- §10 tests minus the flex group; prefill tests target the editor.

**DEFER (with the post-ship design wave) —**
- **§4 ±1h flexibility** entirely (strict *is* the default; removing it removes I5, the
  clamp logic, the softer-shoulder rendering, and the only push-copy debt in the spec).
- **The 4-step wizard** (needs its own spec; ROADMAP already believed this).
- **§9 pixel-perfect Figma tracking** — build provisional rendering now; reconcile
  visuals when the owner approves frames; do not let the Figma track gate TestFlight.

**Also do while in there (one-line items):** record ADR-0007 (client mirrors); update
`ios/GLOSSARY.md` tags (dormant, gradient, range-first — several "planned" entries
become "shipped").

## Execution readiness

With the cut applied, spec 14 is executable by an agent without further owner input
except: I3's provisional strings (flag for review) and the I2 header state (propose,
flag for review). Estimated shape: model/store/dormancy + `HourQuality` + card + detail
+ tests — comparable to the #5b build, smaller than #5a. It should be the first code to
land after the unlock, with the push-client spec written against its landed model.
