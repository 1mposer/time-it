# iOS design glossary

Plain-language definitions for the terms used in the wizard redesign (July 2026 Figma work).
Backend/domain terms (**Activity**, **Threshold**, **Window**, **Rating**, **Pursuit**…) are owned by
[`docs/CONTEXT.md`](../docs/CONTEXT.md) — this file only covers the iOS design & Figma vocabulary layered on top.

Tags: **(shipped)** = in the built #5a/#5b app · **(ship scope — unbuilt)** = in the spec 14 minimal cut ([ROADMAP](../docs/issues/ROADMAP.md) ship item 6) · **(deferred)** = post-ship design wave ([ROADMAP §Deferred](../docs/issues/ROADMAP.md)).

---

## Cards & templates

**Template** *(shipped)*
A curated, pre-filled Activity starting point (Cycling, Fishing Lite, Running, Stargazing) that lives **only inside the app** (`SeedTemplates.swift`) — the server has never heard of it. Adding from a Template *copies* it; from that moment it's the user's own Activity, indistinguishable from one made from scratch.

**Seed / first-launch seeds** *(shipped — changes under spec 14)*
The two Templates (Cycling, Fishing Lite) auto-inserted on first launch (`SeedTemplates.firstLaunchSeeds`). Today they land as **real, active** whole-day Activities (#5b). Under the spec 14 minimal cut they land **dormant** instead (`window == nil`) and render as the **showcase**. Either way the store is never empty on first launch; under spec 14 nothing rates until a range is confirmed.

**Showcase card** *(ship scope — unbuilt)*
The dashboard rendering of a **dormant** Activity — a seeded template card showing "Set your range →" instead of weather. It **is** a stored Activity (spec 14 §1: `window == nil` — stored, visible, never evaluated): it lives in the store but is excluded from every request body and device snapshot until its range is confirmed. *(Ruled 2026-08-12 — supersedes this file's earlier not-an-Activity overlay model.)*

**Showcase card button** *(ship scope — unbuilt)*
The "Set your range →" call-to-action on a showcase card — the only door out of dormancy. Minimal cut: opens the existing editor with the Range prefill loaded (spec 14 header). Full scope *(deferred)*: jumps straight into the wizard's Range screen (the shortest path: 3 screens).

**Dismissed template** *(ship scope — unbuilt)*
A showcase card the user hid with "✕ not for me" — its dormant Activity is removed and the dismissal is remembered in preferences so it stays gone. Deleting the **last** Activity re-seeds the dormant showcase *(ruled 2026-08-12, recorded in spec 14 §6)* — the no-activities dashboard is always the showcase, never a bare void; dismissals survive the re-seed.

**Ghost add-card** *(shipped)*
The "+" card at the end of the dashboard that opens the Add flow.

**Live card / Activity card** *(shipped)*
The dashboard card of a live authored Activity: rating dot, range chip, metric chips. What a showcase card becomes once its range is confirmed.

---

## The wizard

**Wizard** *(deferred)*
The **5-screen** Add flow replacing the single #5b editor screen: Add sheet → Name + Icon → Range → Metrics → Review. Screen 1 (the Add sheet) is shipped; screens 2–5 are the deferred build ([ROADMAP §Deferred](../docs/issues/ROADMAP.md)). No journey visits all 5 — see paths below.

**Add sheet** *(shipped — becomes wizard screen 1)*
The entry screen listing Templates plus "Start from scratch".

**Template path** *(deferred)*
Journey that starts from a Template. Skips Name + Icon (renaming lives on the Review screen). 4 screens.

**Custom path** *(deferred)*
Journey that starts from scratch. The only path that sees Name + Icon. 5 screens.

**Showcase path** *(deferred)*
Journey that starts from a **showcase card button**. Skips the Add sheet *and* Name + Icon: Range → Metrics → Review. 3 screens.

**Range screen** *(deferred)*
Wizard step where the user picks From / To (whole hours only). Picking From later than To makes the range **wrapped** (overnight).

**Metrics screen** *(deferred)*
One screen doing double duty: pick which metrics the card shows, and expand a metric's row to set its threshold. A metric can be **show-only** (displayed but never judged — the backend's "show-but-don't-judge").

**Review screen** *(deferred)*
Final wizard step: summary of everything chosen, rename field, Save. Saving is what turns the draft into a real Activity (and triggers the first/next rating request).

**Wizard-born** *(deferred)*
The rule that every Activity is created through the wizard — which is what guarantees every Activity has a range *the user personally confirmed*.

---

## Time & ranges

**Range** *(domain term — owned by [`docs/CONTEXT.md`](../docs/CONTEXT.md) since 2026-08-11)*
The From/To slice the app checks **every day** for an Activity — full definition in **CONTEXT.md → Range**. Kept here: it is mandatory in the wizard as a **client rule only**; the server still accepts window-less activities (the deferred surprise feature depends on that).

**Range-first** *(locked direction 2026-07-20)*
The product direction: the app's core promise is "you pick a range, we check it daily." No "any time" option in the wizard.

**Suggested range** *(ship scope — unbuilt)*
The per-Template prefill the Range step opens with (minimal cut: the existing editor; full prefill table: spec 14 §6). Purely a starting value — it never becomes real without the user confirming it.

**Wrapped / overnight range** *(shipped)*
A range whose From is later than its To (22:00 → 02:00), meaning it crosses midnight. The one and only thing that makes an Activity nocturnal.

**Diurnal** *(shipped)*
Fancy word for a **daytime activity** — its range stays inside one calendar day. Rated per day; cards say "Today" / "Tomorrow".

**Nocturnal** *(shipped)*
A **night activity** — its range wraps midnight. Rated per *night* (an evening plus the next morning count as one unit); cards say "Tonight". Stargazing is the shipped example.

**Variant** *(planned affordance)*
The same real-world pursuit authored more than once with different ranges — "Cycling — Morning 9–11" and "Cycling — Evening 16–19". Each variant is a full, independent Activity with its own card and rating. (The backend already supports this; the glossary term for the shared real-world thing is **Pursuit** in `docs/CONTEXT.md`.)

---

**Header temp encoding** *(deferred)*
The header's gradient is a **temperature signal**, not fixed branding: cool → blue, mid → yellow, hot → salmon, driven by the current hour's temp. The three identity colors are reserved for this — never used as button/accent colors. Bands come from the **band profile**. Spec: [`docs/design/FIGMA.md`](../docs/design/FIGMA.md) §4.

**Band profile** *(deferred)*
The region-calibrated temperature bands that pick the header gradient, keyed by the **forecast location's country** (not device locale). Band values + extension rule: [`docs/design/FIGMA.md`](../docs/design/FIGMA.md) §4.

## Figma vocabulary

**Logical screen**
A step in the user flow. The wizard has 5. This is the number you *design*.

**Drawn frame**
An actual Figma frame on the canvas. One logical screen usually needs several drawn frames to show its different states — the wizard's 5 logical screens = **9 drawn frames** (inventory: [FIGMA.md §2](../docs/design/FIGMA.md)). This is the number you *draw*.

**State variant**
A drawn frame showing a screen in one specific state: the Range screen same-day vs wrapped vs invalid; the Metrics screen template-prefilled vs custom-empty; the Review screen diurnal vs nocturnal.

---

## Deferred (post-release)

**"Let us find it" / find-mode** *(deferred)*
The dropped wizard branch: "tell us a duration, we search the whole day." Cut because it forced engine, schema, and push-spec changes. Its spirit survives as the surprise notification.

**Surprise notification** *(deferred)*
Future push feature: the server re-checks an Activity's thresholds with the range **ignored**, and pushes when conditions are Perfect *outside* the user's range ("Perfect Cycling at 4pm — outside your usual window"). Needs no schema change precisely because the server keeps accepting window-less activities.
