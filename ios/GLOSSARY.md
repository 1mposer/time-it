# iOS design glossary

Plain-language definitions for the terms used in the wizard redesign (July 2026 Figma work).
Backend/domain terms (**Activity**, **Threshold**, **Window**, **Rating**, **Pursuit**…) are owned by
[`docs/CONTEXT.md`](../docs/CONTEXT.md) — this file only covers the iOS design & Figma vocabulary layered on top.

Tags: **(shipped)** = in the built #5a/#5b app · **(ship scope — unbuilt)** = in the spec 14 minimal cut ([ROADMAP](../docs/issues/ROADMAP.md) ship item 6) · **(deferred)** = post-ship design wave ([ROADMAP §Deferred](../docs/issues/ROADMAP.md)).

---

## Cards & templates

**Template** *(REMOVED 2026-09-01 — historical term)*
Was: a curated, pre-filled Activity starting point (Cycling, Fishing Lite, Running, Stargazing) living only inside the app (`SeedTemplates.swift`). The whole template flow — catalog, first-launch seeding, template-copy path, showcase — was removed in the 2026-09-01 interim polish round (owner ruling): the "+" into the wizard is the only way to create an Activity. The old values survive in git history and as test/preview fixtures (`PreviewFixtures`, `Fixtures`); the onboarding-v2 design may resurrect the *concept* as its hobby-pick prefills ([ROADMAP item 12](../docs/issues/ROADMAP.md)).

**First launch** *(shipped 2026-09-01)*
The store starts **empty**; the dashboard shows the approved **Add-Activity hero** (one dashed card — ⊕, "Add Activity", two-line invitation; press eases the blue dark→light) and no weather rows. Tapping it opens the wizard directly. A persisted empty list is a user choice, not a first launch — nothing ever re-seeds.

**Launch purge** *(shipped 2026-09-01)*
One-time cleanup on load for installs that predate the template removal: a **dormant** Activity descending from the retired seed catalog (`templateOrigin != nil`, or an id in `ActivityStore.legacySeedIds` — cycling, fishing-lite, running, stargazing) is dropped. Anything the user confirmed (windowed) or authored from scratch survives. Idempotent.

**Dormant card** *(shipped 2026-09-01 — replaces the showcase card, legacy edge only)*
The dashboard rendering of a **dormant** Activity (`window == nil` — stored, visible, never evaluated, excluded from every request body and device snapshot): icon + label + "Set your range →" into the editor. After the launch purge this state is only reachable by legacy from-scratch dormant rows — the wizard always saves a ranged Activity.

**Ghost add-card** *(shipped — wizard-direct since 2026-09-01)*
The "+" card at the end of the dashboard. Opens the wizard directly (the Add sheet / template chooser is gone).

**Live card / Activity card** *(shipped — main look since 2026-09-01; spec 14 anatomy 2026-08-14)*
The dashboard card of a live authored Activity, the **main look** for ALL states (owner ruling 2026-09-01): blue "Range · 6 – 10am" chip in the header, per-hour gradient slice on the day axis with **two** axis labels (the ends only), metric chips on every state. A rated day carries the "Today · 6–8pm" best-stretch sublabel; a rating-null day carries **no sublabel and no phrase by default** — the solid-red range slice alone is the verdict ("Nothing in your range." appears only with the Show-phrases toggle on, or under Differentiate Without Color). No rating word anywhere — color carries quality.

---

## The wizard

**Wizard** *(shipped — the 4-tab editor; the only add path since 2026-09-01)*
The authoring surface: a gated 4-tab flow (Name & Icon → Metrics → Range → Review) reached directly from any "+" (hero or ghost add-card) and from a card's gear. The old 5-screen wizard concept's unbuilt screens are demoted to a deferred power-user path ([ROADMAP §Deferred](../docs/issues/ROADMAP.md)).

**Add sheet / Template path / Showcase path** *(REMOVED 2026-09-01 — historical terms)*
The template-chooser entry sheet and the journeys that started from a Template or a showcase card died with the template flow. Every creation journey is now the custom path.

**Custom path** *(shipped)*
The one creation journey: "+" → the wizard, from scratch.

**Range screen** *(deferred)*
Wizard step where the user picks From / To (whole hours only). Picking From later than To makes the range **wrapped** (overnight).

**Metrics screen** *(deferred)*
One screen doing double duty: pick which metrics the card shows, and expand a metric's row to set its threshold. A metric can be **show-only** (displayed but never judged — the backend's "show-but-don't-judge").

**Review screen** *(deferred)*
Final wizard step: summary of everything chosen, rename field, Save. Saving is what turns the draft into a real Activity (and triggers the first/next rating request).

**Wizard-born** *(shipped 2026-09-01)*
The rule that every Activity is created through the wizard — which is what guarantees every Activity has a range *the user personally confirmed*. True since the template removal: the wizard is the only creation path and always saves a ranged Activity.

---

## Time & ranges

**Range** *(domain term — owned by [`docs/CONTEXT.md`](../docs/CONTEXT.md) since 2026-08-11)*
The From/To slice the app checks **every day** for an Activity — full definition in **CONTEXT.md → Range**. Kept here: it is mandatory in the wizard as a **client rule only**; the server still accepts window-less activities (the deferred surprise feature depends on that).

**Range-first** *(locked direction 2026-07-20)*
The product direction: the app's core promise is "you pick a range, we check it daily." No "any time" option in the wizard.

**Suggested range** *(shipped — single fallback since 2026-09-01)*
The prefill the wizard's Range tab opens with: the Activity's own range when editing, else **6–10am** (the per-Template prefill table died with the templates). Purely a starting value — it never becomes real without the user confirming it (touching a wheel, or the warn-then-proceed path) and saving.

**Wrapped / overnight range** *(shipped)*
A range whose From is later than its To (22:00 → 02:00), meaning it crosses midnight. The one and only thing that makes an Activity nocturnal.

**Diurnal** *(shipped)*
Fancy word for a **daytime activity** — its range stays inside one calendar day. Rated per day; cards say "Today" / "Tomorrow".

**Nocturnal** *(shipped)*
A **night activity** — its range wraps midnight. Rated per *night* (an evening plus the next morning count as one unit); cards say "Tonight". Stargazing is the canonical example.

**Variant** *(deferred affordance)*
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
