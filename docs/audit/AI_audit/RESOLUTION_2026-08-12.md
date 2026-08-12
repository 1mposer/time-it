# Resolution — adjudication of the 2026-08-11 redundancy audit

**Date:** 2026-08-12 · **Branch:** `ideating` · **Adjudicator:** owner + agent (grill session — every ruling below is owner-confirmed). This closes the audit's "pending human/senior-agent cross-contamination check". Policy outcome of record: [ADR-0009](../../adr/0009-tiered-doc-truth.md) (tiered doc truth + the two-home UI rule).

## How the A-items were arbitrated

Code was consulted before any doc was believed; where code was silent (unbuilt features), the owner ruled.

| # | Arbiter | Ruled truth | False copy (fixed) |
|---|---|---|---|
| A1 | owner | Showcase card = **stored dormant Activity** (spec 14 §1 model) | GLOSSARY's not-an-Activity overlay model |
| A2 | code (`SeedTemplates.firstLaunchSeeds`) | First launch **seeds** cycling + fishing-lite; store never empty | GLOSSARY "store starts empty" |
| A3 | owner — **reversed the audit's lean** | Wizard = **5-screen** (Add sheet shipped; screens 2–5 deferred; Template path skips Name+Icon) | spec 14 ×3 + ROADMAP "4-step" |
| A4 | dated decision (2026-08-10 minimal cut) | Showcase cluster = ship scope (spec 14 minimal cut); wizard screens 2–5 = deferred | GLOSSARY "(planned)" tags |
| A5/A6 | code (`fetch.js` `/standard/`) | Meteosource on **Standard**, ~166 h live-verified | OWNER_NOTES renew item; grill-doc handoff (annotated, not rewritten — frozen file) |
| A7 | filesystem | Stray `meteosource_standard_openapi.json` — already gone before adjudication | — |
| A8 | dated event (2026-08-11) | Railway Hobby upgrade done | OWNER_NOTES "eventually" |
| A9 | code (`app.js` `initDb()`/`exit(1)`) | `DATABASE_URL` mandatory | README API_KEY-only setup |
| A10 | code (`dailyDigest.js`) | Digest = 6–11 local catch-up band | CONTEXT "local 6am" |
| A11 | fileKey identity | "Main - Time it" (FIGMA.md spelling) | ios/README + Guidelines hyphenation |

**New ruling surfaced during adjudication:** deleting the last Activity **re-seeds the dormant showcase** (spec 14 §6 now records it — the behavior previously existed only in GLOSSARY, in the dead overlay model, and spec 14 never covered delete-all).

## Corrections to the audit (the cross-check's findings)

- **A3 reversed:** GLOSSARY's "5 logical screens" was closest to right; the audit's implied lean toward the "4-step" majority was wrong. GLOSSARY:39/101/104 required no fix; spec 14 and ROADMAP did.
- **A7 was already resolved** at adjudication time.
- Two empirical regularities drove ADR-0009: **all 11 drifts sat in non-owner copies** (owner files + code were right in every dispute), and **only volatile facts drifted** (contract facts in up to 7 copies: zero decay).

## Applied (this branch, 4 commits)

1. Truth fixes — all A-items + the sweep's additional stale sites (push-client spec #11 refs, STATUS blocked line, OWNER_NOTES).
2. ADR-0009 + STATUS §1 tiered rule (volatile/contract definitions inline) + CLAUDE.md discovery pointer.
3. Volatile-fact consolidation — status facts collapsed to ROADMAP; template catalog to `SeedTemplates.swift` + spec 14 §6; engine rule out of the vendor README; surprise-notification row added to ROADMAP §Deferred.
4. Two-home UI strip — FIGMA.md and Guidelines.md no longer carry design values (addresses/behavior only); `Theme.swift` header re-pointed; the audit closed with this file.

Section-B contract-fact mirrors were deliberately **not** consolidated — sanctioned by ADR-0009.
