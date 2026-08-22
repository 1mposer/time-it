# Research note — onboarding tester evidence + the 2026-08-22 grill record

> Created 2026-08-22 by the senior-auditor session, from the owner's grilling session (the successor-roadmap grill). This is the **single home** for the tester evidence and the grill's decisions of record ([ADR-0009](../adr/0009-tiered-doc-truth.md) — link here, don't restate). Plan of action produced: [`docs/issues/ROADMAP.md`](../issues/ROADMAP.md) (reset 2026-08-22). §1 is evidence — append observations, never rewrite them; §2–§4 are rulings.

## 1. Tester evidence (verbatim, owner-corrected — 4 live TestFlight internal testers)

1. Testers froze at the dashboard staring at an empty card saying **"Nothing in your range"**, touched nothing, gave up and left. Some stared at the activity templates ("set your own range") believing those were the only activities the app has. They treated the app as something to **watch, not touch**.
2. The owner's dad downloaded it, texted "[you] should add running as one of the activities" — blind to the fact he could create it himself — closed the app and never opened it again. He believed the activity list comes from the developer, like a catalog.
3. Nobody understands the words **"threshold"** and **"range"** — neither should ever appear on screen.
4. The emotional beat of the app today is a red failure card about activities the user never chose.

## 2. Persona (owner ruling — a chosen design lens, not an evidence claim)

**Highly active hobbyists with technophobia** — they distrust new tools; they need to **WIN first, not create first**. The owner's ruling (grill Q7): *"We will design all screens around this persona; we should always assume that the user is non-technical and is a technophobe. Designing around the outlier is what makes a good product for everyone. This is our lens."* The observed behaviors in §1 are the evidence; "technophobia" is the deliberately chosen lens applied to all future design — the two are recorded separately on purpose.

## 3. Success metric — the "dad test" — and how it is measured

A new user reaches a real verdict about their own hobby in **under two minutes, unassisted**, and opens the app again the next day.

**Measurement (grill Q9 — watched sessions, no analytics):** when the onboarding-v2 build reaches testers, each gets a **fresh install** with the owner watching (in person or video call), saying nothing: stopwatch to first verdict, hesitations noted; next-day return checked by asking. Observations are appended below in §5. Analytics stay deferred (condition: cohort > ~5 — [ROADMAP §Deferred](../issues/ROADMAP.md)).

## 4. Grill decisions of record (2026-08-22 — locked; relitigate only with the owner)

- **Q2 — objective:** the roadmap carries both loops, ordered — the dad test (activation) is the headline objective and explicit prerequisite; the old finish line (*a real user acts on a push and reports whether reality matched*) stays after it, unfinished, not re-scoped away.
- **Q3 — location ask:** after hobby pick + personalization, right before the verdict reveal, with one plain sentence of why; refusal falls into the city picker as a normal step; **the refusal path is a first-class Figma frame**.
- **Q4 — personalization:** **three core one-tap questions**, prefilled from the template — (1) "When do you usually [run]?" → the mandatory **Range** (born ranged, non-dormant — locked contract), (2)+(3) two comfort questions → the hobby's two most important thresholds — **plus an optional fine-tune offer**; if entered, a clear, always-visible button backs out and ditches fine-tuning, returning to the path to the verdict. No keyboard anywhere in the question flow. Fine-tune's destination is decided inside the design pass (ROADMAP item 12).
- **Q5 — second activity:** one optional **"Add another?" after the first verdict**, before the dashboard — skippable in one tap; never an authoring loop before the win.
- **Q6 — vocabulary + Figma workflow:** "range"/"threshold" never appear on the **new** screens; the rework lives on a **new dedicated Figma page** built fresh from owner-supplied Mobbin references — existing pages (§7/§8) are never edited. This phase designs+builds **onboarding only**; the new screens are the reference standard for future flows; the shipped "range" surfaces are parked as a named Deferred row (not dropped). The Add-sheet wizard's deprecation is an owner **expectation**, recorded, not a locked kill.
- **Q7 — persona:** §2 above.
- **Q8 — sequencing:** **hard-hold every external TestFlight step** (privacy-policy URL → review → public link) until onboarding v2 ships; internal testers are known and reachable, and there is no public link yet. Item 8's server acceptance boxes continue in parallel.
- **Q9 — measurement:** §3 above.
- **Phase scope (ruled inside Q6b):** this phase is **design AND build** — "done" means the internal testers are running the new onboarding.

## 5. Watched-session observations (append-only — item 14)

*(none yet — filled when the onboarding-v2 build reaches testers)*
