# Ship phase — the 1.0 ship gate (ROADMAP item 23)

> Living work order, created 2026-11-18. **Status home: [ROADMAP item 23](../ROADMAP.md).** This file holds the phase checklist, the owner's rulings and the Release Captain's ledger — nothing else. Fold-in: when App Review approves 1.0, fold the outcome into ROADMAP item 23 and move this file to `completed/`.
>
> **This repository is public.** Raw audit and review findings stay out of it until their fixes are deployed. They live in a local ledger folder on the owner's Linux machine (`~/time-it-ship-ledger/`), and this file refers to them by ID only. The same rule covers commit messages, branch names, PR text and new GitHub issues.

## How a cold session resumes

1. Read order as [`CLAUDE.md`](../../../CLAUDE.md) sets it, then [ROADMAP](../ROADMAP.md), then this file.
2. Find the first unticked box in §3. That phase's working files are in `~/time-it-ship-ledger/` (its `README.md` is the index).
3. Method: the `imposers_ship_gate` skill, as amended by §2 and §3 here. Agent workflow rules: `CLAUDE.md`.

## 1. Owner rulings

**2026-11-17 (handoff session)**

- The phase is an audit, not a design pass: security failure modes, an adversarial review, a deploy realignment (ready to host users; fallbacks for server and provider), App Store readiness.
- The adversarial review is **blind**: separate sessions that get the code only — no docs, no project memory.
- The final decider is the **Release Captain** (§2), so the owner is never the bottleneck.
- Bundle ID stays `com.timeit.app.dev`.
- When the weather provider fails, the server serves the last good forecast. No second provider in 1.0.
- **Straight to App Store review** — no external TestFlight stop. Overrides the 2026-08-22 hold ([ROADMAP item 9](../ROADMAP.md)).
- 1.0 ships **free**; payments come in 1.1.
- Bulk GitHub issue closes need one batch approval; label changes are fine.

**2026-11-18 (decision page — eleven rulings)**

1. Start now. Build 11 is complete on `main`.
2. 1.0 ships with today's first run; onboarding v2 and the dad test ([items 13–14](../ROADMAP.md)) follow 1.0 — a deliberate trade. Every deferred item goes into one spreadsheet, each row linked to its GitHub issue, for the owner's post-launch review (§5).
3. Issue #19 (first-launch "No location"): reproduce and fix, **or** the owner passes a clean fresh install on the phone, allow and deny. The Captain may not accept it unreproduced.
4. [ADR-0008](../../adr/0008-figma-first-ui-gate.md) is waived for three release changes only: the two feedback entries moving into Settings, a Privacy Policy row in Settings, and whatever the #19 fix changes on the empty first screen. Plain rows in the existing style; the owner reviews them on the phone.
5. The devices-route registration limit is built in 1.0 (was a [Deferred](../ROADMAP.md) row).
6. The open push live-acceptance boxes ([ROADMAP item 8](../ROADMAP.md)): the Captain decides, from a short test plan run during the audits. Listed in the sheet (§5).
7. A stale forecast may be shown for up to **6 hours**; an alert is never sent from it. Read as: neither push job evaluates stale data (the digest's 6–11 band absorbs the wait) — the Captain may refine this for the digest.
8. This file, one ROADMAP row and one STATUS line — no root `roadmap_ship.md`.
9. Everything is orchestrated from the Linux machine; iOS builds and tests run on the owner's Mac over SSH. Signing, archive and upload stay with the owner.
10. Build 11 is not uploaded yet.
11. The privacy and support pages are hosted on the owner's Time it website, live before release.

## 2. The Release Captain

One Opus agent (skill `ship-gate`), final authority below the owner's line.

- **Blocks the ship for:** something App Review will reject; a security exposure or a way to burn paid provider quota; a crash or data-loss path; a broken deploy or recovery path; a first run a reviewer cannot get through.
- **Rules without the owner:** accepted risks, deferrals to post-release, severity disputes, which issues are in the release.
- **May not:** accept #19 unreproduced (ruling 3).
- **Escalates to the owner:** money, legal and privacy-policy wording (including any mismatch between the privacy manifest, the App Privacy answers and what the app actually sends), brand, irreversible actions (bulk closes, the final submit).
- Every ruling and its reason goes into §6. The owner vetoes after the fact.

## 3. Phases

Each phase ends with a durable write (this file, the local ledger, or a merge) before the session sleeps.

- [x] **P0 — plan audit and owner rulings** (2026-11-17/18).
- [x] **P1 — Wave 0:** this file, ROADMAP item 23, the STATUS pointer, the sweep of the overridden hold (2026-11-18).
- [x] **P2 — Waves 1 and 2, in parallel** (2026-11-18 — all nine lanes reported; 88 findings in the local ledger). Read-only. Lanes do not talk to each other.

  | Lane | Agent | Ledger file |
  |---|---|---|
  | Server security | Sonnet | `wave1/server-security.md` |
  | iOS security and privacy | Sonnet | `wave1/ios-security.md` |
  | Deploy and resilience | Sonnet | `wave1/deploy-resilience.md` |
  | App Store readiness (seeded from issue #29) | Sonnet | `wave1/store-readiness.md` |
  | #19 reproduction, on the Mac | Sonnet | `wave1/issue19-repro.md` |
  | Push acceptance test plan (item 8) | Sonnet | `wave1/push-acceptance-plan.md` |
  | Store copy and shot lists (drafts) | Sonnet | `wave1/store-drafts.md` |
  | Blind review — server | Opus, separate session, code-only export | `wave2/blind-server.md` |
  | Blind review — iOS | Opus, separate session, code-only export | `wave2/blind-ios.md` |

- [x] **P3 — done 2026-11-18** (judge: 88 findings → 54; Captain's rulings in §6, ship criteria in §7; the deferred-items sheet built — 59 rows; the owner's rulings page is out, veto window open). Wave 3 judge (Opus): merge, dedupe, rank → **Wave 4:** the orchestrator sorts each finding into real / documented-and-accepted / needs-ruling against the ADRs, then the Captain rules and writes the fix list and §6. The deferred-items sheet (§5) is built here. Owner veto page.
- [ ] **P4 — Wave 5 fix lanes** (TDD, worktrees; Opus implements, Sonnet verifies; iOS through the Mac). Provisional lanes, replaced by the Captain's fix list: **THROTTLE** (server traffic limits — the [item 20](../ROADMAP.md) lane, promoted), **DEPLOY** (deploy config as code, recovery runbook), **FIRSTRUN** (#19), **RELEASE** (release-only iOS changes, build bump).
- [ ] **P5 — Wave 6:** the Captain's ship / no-ship verdict (advisor consulted first).
- [ ] **P6 — Wave 7, owner's hands** (§4).

## 4. Owner's hands

Only the owner can do these; each is a box on the final checklist.

- [ ] Meteosource: the plan's call limit and whether its terms allow a public app.
- [ ] Railway: the service settings (health check, restart policy, replicas) and whether Postgres backups are on.
- [ ] Privacy and support pages live on the Time it website (text drafted by an agent, approved by the owner).
- [ ] The phone checks: #19 fresh install (ruling 3) and the push live checks the Captain keeps (ruling 6).
- [ ] Screen recordings for App Review, from the shot list.
- [ ] App Store Connect: metadata, screenshots, App Privacy answers, age rating.
- [ ] Archive, upload, and sync the assigned build number; submit.

Still open from build 11, outside this phase: answer 12 from the current screenshot; the Instruments lane ([PR-011](../../post-release/items/PR-011-opening-hold-instruments.yaml)); the Figma Color/Typography token writes ([ROADMAP item 19](../ROADMAP.md)).

## 5. The deferred-items sheet (ruling 2)

**Built 2026-11-18:** [`docs/post-release/backlog.csv`](../../post-release/backlog.csv) — 59 rows, with an `Issue` column. Rows still without an issue wait for the owner's batch approval (asked on the rulings page).

One spreadsheet of everything deferred past 1.0, for the owner's post-launch review: the existing [post-release backlog](../../post-release/README.md), extended to cover the ship phase's own deferrals, the [ROADMAP Deferred table](../ROADMAP.md) and the open GitHub issues classed post-release. Every row carries its GitHub issue link. Rows whose item has no issue yet get one, created in **one batch after the Captain's list is final and shown to the owner first** (each new issue carries a `triage:` label or a ROADMAP row, per the ROADMAP issue rule). Rows for items that already have a ROADMAP row link to it and do not restate its status.

## 6. The Captain's ledger

Ruled 2026-11-18 by the Release Captain on the judge's 54 merged findings (88 raw findings from nine lanes). **Counts:** fix in 1.0 — 31 · after 1.0 — 10 · documented choice confirmed — 4 · sent to the owner — 7 · refuted — 2. Finding IDs (`J-nn`) resolve in the local ledger (`wave3/judged-list.md`, `wave4/captain-rulings.md`); reasons here name a class, never a mechanism. The owner vetoes after the fact — a veto is recorded in the last column.

| # | Finding | Ruling | Lane | Reason | Owner veto |
|---|---|---|---|---|---|
| R-01 | J-01 | FIX-1.0 | THROTTLE | closes a paid-quota exposure | |
| R-02 | J-02 | FIX-1.0 | THROTTLE | closes a paid-quota exposure | |
| R-03 | J-03 | FIX-1.0 | RELEASE | store-rejection risk; owner-ordered | |
| R-04 | J-04 | FIX-1.0 | RELEASE | store-rejection risk | |
| R-05 | J-05 | FIX-1.0 | THROTTLE | service-availability hardening | |
| R-06 | J-06 | FIX-1.0 | THROTTLE | stability and storage hardening | |
| R-07 | J-07 | FIX-1.0 | DEPLOY | crash-path hardening | |
| R-08 | J-08 | FIX-1.0 | DEPLOY | notification reliability | |
| R-09 | J-09 | FIX-1.0 | THROTTLE | notification reliability | |
| R-10 | J-10 | ACCEPT | — | documented choice confirmed | |
| R-11 | J-11 | FIX-1.0 | THROTTLE | owner-ruled resilience item | |
| R-12 | J-12 | FIX-1.0 | THROTTLE | stability hardening | |
| R-13 | J-13 | FIX-1.0 | THROTTLE | provider-cost control | |
| R-14 | J-14 | FIX-1.0 | DEPLOY | operational visibility | |
| R-15 | J-15 | FIX-1.0 | THROTTLE + RELEASE | privacy-declaration accuracy | |
| R-16 | J-16 | ESCALATE-OWNER | — | privacy wording is the owner's | |
| R-17 | J-17 | FIX-1.0 | RELEASE | first-run reliability | |
| R-18 | J-18 | FIX-1.0 | RELEASE | data-loss prevention | |
| R-19 | J-19 | FIX-1.0 | FIRSTRUN | first-run reliability | |
| R-20 | J-20 | FIX-1.0 | RELEASE | copy fix | |
| R-21 | J-21 | DEFER-POST | — | design change, after 1.0 | |
| R-22 | J-22 | DEFER-POST | — | design change, after 1.0 | |
| R-23 | J-23 | FIX-1.0 | RELEASE | first-run reliability | |
| R-24 | J-24 | DEFER-POST | — | design change, after 1.0 | |
| R-25 | J-25 | FIX-1.0 | THROTTLE | abuse hardening | |
| R-26 | J-26 | ESCALATE-OWNER | — | irreversible choice is the owner's | |
| R-27 | J-27 | FIX-1.0 | DEPLOY | recovery-path hardening | |
| R-28 | J-28 | ESCALATE-OWNER | — | recovery choice with a cost is the owner's | |
| R-29 | J-29 | FIX-1.0 | DEPLOY | deploy reproducibility | |
| R-30 | J-30 | ESCALATE-OWNER | — | legal question is the owner's | |
| R-31 | J-31 | ACCEPT | — | documented choice confirmed | |
| R-32 | J-32 | ACCEPT | — | documented; checked at archive | |
| R-33 | J-33 | ACCEPT | — | documented choice confirmed | |
| R-34 | J-34 | FIX-1.0 | THROTTLE | input hardening | |
| R-35 | J-35 | FIX-1.0 | DEPLOY | log hygiene | |
| R-36 | J-36 | FIX-1.0 | THROTTLE | edge hardening | |
| R-37 | J-37 | FIX-1.0 | THROTTLE | error-mapping fix | |
| R-38 | J-38 | FIX-1.0 | THROTTLE | notification reliability | |
| R-39 | J-39 | DEFER-POST | — | product question for after 1.0 | |
| R-40 | J-40 | DEFER-POST | — | hardening after 1.0 | |
| R-41 | J-41 | DEFER-POST | — | cleanup after 1.0 | |
| R-42 | J-42 | FIX-1.0 | RELEASE | store-review hygiene | |
| R-43 | J-43 | FIX-1.0 | RELEASE | documentation accuracy | |
| R-44 | J-44 | ESCALATE-OWNER | — | legal answer is the owner's | |
| R-45 | J-45 | ESCALATE-OWNER | — | copy choice is the owner's | |
| R-46 | J-46 | ESCALATE-OWNER | — | store setting is the owner's | |
| R-47 | J-47 | FIX-1.0 | DEPLOY | deploy hygiene | |
| R-48 | J-48 | DEFER-POST | — | tooling after 1.0 | |
| R-49 | J-49 | DEFER-POST | — | polish after 1.0, checked during release | |
| R-50 | J-50 | DEFER-POST | — | accessibility polish after 1.0 | |
| R-51 | J-51 | DEFER-POST | — | edge case after 1.0 | |
| R-52 | J-52 | CLOSE | — | refuted | |
| R-53 | J-53 | CLOSE | — | refuted | |
| R-54 | J-54 | FIX-1.0 | FIRSTRUN | first-run reliability; owner phone check required | |

**Fix lanes and order.** Server, strictly serial: **THROTTLE T1 → THROTTLE T2 → DEPLOY D2**; **DEPLOY D1** in parallel, merged only after the owner reads the Railway settings back. iOS, one verifier on the Mac at a time: **baseline suites + LIFECYCLE (a coverage lane the Captain ordered) → FIRSTRUN → RELEASE → final suite run**. Server fixes go live when they merge, so every server item is tested against what build 11 actually sends.

## 7. Ship criteria (the Captain's, public summary)

A ship verdict in P5 needs every box. The checkable detail of each is in the local ledger (`wave4/captain-rulings.md`, "Ship criteria").

- [ ] **S-1** Every fix lane merged; server and iOS suites green on the release commits; each fix ruling mapped to a merged commit.
- [ ] **S-2** Production redeployed from the final server commit; the owner's phone loads a forecast.
- [ ] **S-3** The owner's own device record passes the new input rules before THROTTLE T2 merges.
- [ ] **S-4** The switch-gated limits are turned on only after their live checks pass (otherwise they stay in observe mode and the Captain rules the residual).
- [ ] **S-5** The provider budgets fit the owner's Meteosource plan, and its terms allow a public app.
- [ ] **S-6** #19 on a real phone, on the build to be submitted (internal TestFlight), from a deleted app each time: allow; deny; allow → force-quit → relaunch with no Activity. **Fixed criterion (owner ruling 3).**
- [ ] **S-7** The push live checks the Captain kept (digest, toggle-off, one-alert-then-silence, dormant Activity) pass on that build after the server merges.
- [ ] **S-8** The owner's hands (§4) are done.
- [ ] **S-9** The archived build's push entitlement reads production (owner, at archive).
- [ ] **S-10** No blocking owner question open.
- [ ] **S-11** The LIFECYCLE lane has reported and its findings are ruled.
- [ ] **S-12** The deferred-items sheet (§5) holds every deferral, each with an issue or a ROADMAP row.
- [ ] **S-13** This ledger carries every ruling and no owner veto is open.
- [ ] **S-14** After upload, the App Store Connect build number is synced into the project.
