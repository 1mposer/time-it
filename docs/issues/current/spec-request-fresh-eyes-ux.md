# Specification request — fresh-eyes UX faults (pre-release, build 8)

> Created 2026-11-11. This is a **request for an implementation spec**, not the spec. Owner page with the ranked findings and screens: https://claude.ai/artifact/KiAUy221FYmRAafcUGJMGV. Evidence record (all 38 notes + screens): [`docs/research/fresh-eyes-2026-11-11/`](../../research/fresh-eyes-2026-11-11/NOTES.md). Status home once the spec exists: [ROADMAP](../ROADMAP.md) (no row yet).

## §1 What was done

- A **blind Opus 5.5 agent** used the app as a first-time user for ~25 minutes on the iPhone 17 Pro simulator (iOS 26.5), driven through the computer-use MCP. It had no docs, no source, no feature list — only the app's name and a notes file. Jev (TypeSafe System One) grounded tap targets from device screenshots and gave second opinions on screen state; it is a judgment model, not an agent.
- Build: `owner-tweaks` `899566a` (= `main`, build 8 code), **Debug** configuration, fresh install, location set to Dubai, notifications allowed during the run.
- Covered: first launch with location **denied**, Settings and the city search, two activities through the wizard (a 9am–5pm beach day and an overnight 8pm–2am stargazing), the detail screen, editing, notifications, dark appearance, XXXL and Accessibility-XXXL text, relaunch as a returning user, delete.
- Not covered: real forecast data (§2), hardware, iOS 17, pull-to-refresh, the feedback sheet, push arrival.

## §2 Caveat — the weather data was fake

The Debug build dials `localhost:3000`. That port was serving a `fake-server.js` left running by an unrelated session, not this repo's server. Live Meteosource was queried separately and returns `new_moon` for the whole week. Struck as fixture artefacts: the daily-cycling moon phase, 40 °C November days, "100 every night" on the stargazing card, and the specific score numbers. **Every flow, control and copy finding stands** — none depends on the values. A re-run against the real backend (Release → Railway, or a local server with a `DATABASE_URL`) is the first follow-up.

## §3 What broke

Numbers in brackets are notes in the evidence record.

**Fix first**

1. **A green "Perfect" on a day that is mostly red** [18, 19, 23]. The verdict is the best qualifying Window; the score is the whole day's mean; they are independent by design ([ADR-0011](../../adr/0011-day-score.md)). A new user reads "Perfect" as the whole day and cannot build a model of the number. After shifting the Range the ring kept "Perfect" until the span was scored.
2. **Location denied is never explained** [1, 2, 3, 8, 13]. After "Don't Allow" the home stays "NO LOCATION" with no explanation; Settings says "Using current location" anyway; "Use current location" silently discards a chosen city; the real "No location yet — pick a city" prompt appears only after a whole activity is built, beside two frozen skeleton cards for one activity.
3. **Notifications** [6, 27]. Tapping the switch never flipped it (only sliding the knob did, which then raised the iOS prompt) — possibly a simulator mouse artefact, verify on a phone. The "Turn on notifications" banner only opens Settings. After enabling, nothing says what arrives or when.
4. **The wizard does not explain itself** [9, 10, 11, 12]. Next stays disabled with no hint that an icon is required; Priority is pre-checked on every metric and "considered more" is vague; "Show only" is unexplained; the "Range" step is a time of day right after setting temperature ranges, with a silent 6–10am default; Review hides non-Priority metrics.
5. **The home card has no verdict word or legend** [14, 16, 26]. Ring, strip and dots, no words; tapping Friday's dot opened the detail on today (build 7 shipped a day-jump — tap target or regression); the chevron collapses the dot row where iOS reads it as "open".

**Runners-up**

- City search returns at most one result ("Springfield" → MO only; "San" → nothing) [4].
- Accessibility sizes: hour chips, slider range labels, −/+ and the ring numeral do not scale; the sticky header takes ~40% of the screen; "9 10" collides into "910" [36]. The Score caption and Range line were already on the open-calls list; the chips and labels are new.
- Edge swipe-back does nothing on the pushed detail; only the round back button pops [32]. A custom back button that hides the system one also disables the interactive pop — likely real on hardware.
- Overnight Review preview: "Tonight · 8pm–2am" over an axis that starts at 12am, so the 8pm–midnight half is missing; the chip reads 20% for a 40% limit [30]. Related to the known "Today" label item ([FIGMA.md §11](../../design/FIGMA.md)).
- Switching to dark while on the overnight detail re-rendered the hour strip as 10 11 12 1 2 3 4, all dimmed, until leaving and re-entering [34].
- No °F, no mph [7]. Cancel on a half-built new activity has no confirm [35]. Delete is four taps deep with no undo [24, 38]. Scrolled detail header floats over a blurred ring [25]. Per-card expanded/collapsed state looks inconsistent side by side [31].

**Works well** [10, 14, 17, 34, 37, 38]: the detail's per-metric cards with the limit drawn on a mini slider and the failing value in red; the gradient sliders; city pick filling home instantly; dark mode; instant relaunch; delete confirmation.

## §4 Recon — start with the implicit state machines

After reading this request, **finding and mapping out all the implicit state machines behind these faults is the place to start.** Nearly every fault above is a state the code already holds but never named, so two screens disagree about it or a transition has no copy. Map each as states × inputs → what every surface shows, from the code as it exists, before proposing a single fix. At minimum:

- **Location × home × forecast × activities** → which of empty home / "NO LOCATION" header / skeleton cards / "No location yet" prompt / Settings "Using current location" is shown. Inputs: authorization status (not determined / denied / allowed), home mode (current / city), fix arrived, forecast loaded / failed, activity count (0 / ≥1). Faults 2 and the skeleton cards live here.
- **Notification permission × Settings switch × home banner** → switch state, banner visibility, whether the iOS prompt fires, what confirms. Fault 3.
- **Wizard step validity** → Next enabled, the pills' ✓ marks, what Review shows. Inputs: name, icon, metrics chosen, Priority / Show only per metric, time From/To (same-day, overnight, equal). Fault 4 and the Review-hides-metrics and early-✓ oddities.
- **Detail Range shift** → preview vs scored, ring numeral, verdict word, week dot. Inputs: −/+, "Score …" pill, reset. Fault 1's stale "Perfect".
- **Card** → expanded / collapsed per card, chevron direction, dot tap target vs day-jump. Fault 5.
- **Appearance switch while a screen is live** → which views rebuild and from what. The hour-strip glitch.

Record each map in the spec (a table or a short Mermaid state diagram), name the states, and derive the tests from the transitions — each fix is then a transition that gains copy, a guard, or a surface, not a patch on a screen.

## §5 Scope and constraints for the spec

- **No engine change.** The verdict/score independence rule stays ([ADR-0011](../../adr/0011-day-score.md)); the fix is naming the Window beside the verdict, not changing either.
- **Figma-first** for any visual change ([ADR-0008](../../adr/0008-figma-first-ui-gate.md)); copy-only hints may ship without a frame if the owner rules so.
- **Overlap with item 13** (onboarding v2): the missing welcome is item 13's; the spec must say for each of faults 2 and 4 whether it lands standalone (build 9) or inside item 13 — the owner rules.
- **Verify on hardware first:** the notifications switch and the edge swipe-back may be simulator driving artefacts.
- **Client mirrors:** any change touching threshold or window semantics reads [ADR-0007](../../adr/0007-client-side-mirrors.md) first.
- Owner rulings land on the owner page as a/b/c per fault; the spec carries a ruling slot per fault.

## §6 Expected deliverable

An `implement-spec-*.md` in this folder, house format: goal, the state maps from §4, per-fault change with its transition and copy, tests (unit + XCUI, one pin per transition), ROADMAP row, and the re-run against the real backend as its first acceptance box.
