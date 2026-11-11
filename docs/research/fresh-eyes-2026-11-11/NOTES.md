# Fresh-eyes tester record — 2026-11-11 (blind Opus 5.5 agent, build-8 simulator app)

> Evidence record for [the spec request](../issues/current/spec-request-fresh-eyes-ux.md). **Weather data in this run was fake** (see the request §2) — notes 18, 21, 22, 31 and the numbers in 19/23 are fixture artefacts. Screenshots: this folder, `<nn>-<what>.jpg`.

# Time It — fresh-eyes UX notes (2026-11-11)

Format: where / what I did / what rubbed (type) / severity 1-3 / shot

1. **First launch** — fresh install, app opens straight to a system location prompt over a blank sky-gradient screen reading "NO LOCATION". No welcome, no hint of what the app does before I'm asked for location. The prompt's purpose string ("fetch a local weather forecast") is the first time I learn it's weather-related. Friction / untested-first-impression. Sev 2. `01-first-launch-location-prompt.jpg`

2. **Home after denying location** — tapped "Don't Allow". Home shows "NO LOCATION" + "Add Activity" + "Time It checks weather conditions for any activity you create." Clean, calm, and the one-line explanation is good (delight: the empty state finally tells me what the app is). But nothing says location was denied or offers to pick a place from here — I'd have to guess the gear holds it. Friction. Sev 2. `02-denied-empty-home.jpg`

3. **Settings after denying location** — Home row reads "Using current location" even though I just refused location access and the header says "NO LOCATION". Contradictory/misleading. The footer copy ("…or asks you to pick one") is a nice explainer but long and buried at the bottom under "About". Friction. Sev 2. `03-settings-denied-says-current-location.jpg`

4. **Set Location city search** — Settings > Set home location. Search field isn't auto-focused (one extra tap). Search returns at most ONE result: "Springfield" → only Springfield MO (no IL/MA), "Paris" → only Paris FR, partial "San" → "No places found — try a different search." Single letter "A" → "Eastern Macedonia and Thrace, Greece". No type-ahead feel; anyone with an ambiguous city name can't pick theirs. Friction / untested angle. Sev 3. `04-city-search-single-result.jpg`
   (Tester note: Mac-side press-and-hold accent popups garbled some typing in Simulator — not the app's fault.)

5. **Settings after picking Dubai** — Home now "Dubai", a new "Use current location" row appears (no icon, misaligned vs the iconed "Set home location" row above — looks unfinished). Good: picking a city returns straight to Settings with it applied. Minor vibe. Sev 1.

6. **Notifications toggle (no activities yet, location denied)** — tapped it twice; it stays off. No system permission prompt, no message why. Feels broken. Footer "Perfect window alerts" is jargon I don't understand yet. Friction. Sev 3 (will re-test once I have an activity). `05-settings-notif-toggle-wont-turn-on.jpg`

7. **Units** — Wind speed offers only km/h and Knots. No mph; no temperature unit (°C/°F) at all. A US user will be lost. Untested angle. Sev 2.

8. **"Use current location" with location denied** — tapping it silently discards my chosen Dubai and goes back to "Using current location", with no prompt to re-enable location and no warning that current location is unavailable. Home header goes back to "NO LOCATION". Easy way to wipe your setting by accident. Friction. Sev 2.

9. **New Activity wizard, step 1 (Name)** — Clear 4-step pill bar (Name / Metrics / Range / Review), orange accent feels friendly (delight). But: "Next Step" stays greyed after typing a name with no hint that an icon is ALSO required — I only discovered it by experimenting. Icon categories are collapsed accordions, so no icon is visible until you open one. "Beach & Water" has only water-sport glyphs (surf, sail, swim, row, fish, volleyball) — nothing for a plain beach/sun day. Friction. Sev 2. `06-wizard-name-icon.jpg`

10. **Wizard step 2 (Metrics)** — Delight: tapping a metric expands an inline range slider with a red→green→red gradient and live "15–32 °C" readout; feels tactile and quick. Rubs:
   - "Did you know? If 'Priority' is selected… it will be considered more in the calculation." The word "Priority" doesn't appear until you pick a metric, and "considered more" is vague — I can't tell if Priority means "must pass" or "weighted higher". Confusion. Sev 2.
   - Priority is pre-checked on every metric, so by default everything is a hard requirement; easy to over-constrain without realising. Sev 2.
   - "Show only" checkbox: unclear until you tick it (it hides the slider and unticks Priority). Label could say "Just show it, don't judge". Square checkboxes feel web-ish, not iOS. Sev 1.
   - The slider is twitchy: a ~40px drag moved max temp from 32 to 41 °C; no way to type a value or nudge by 1. Sev 2.
   - Moon Phase gets a ✓ but no settings and no explanation of what it does for the rating. Dust Alert uses the same sun glyph as UV Index. Sev 1.
   - Progress pills: "Review" shows a ✓ as soon as I picked one metric, before I'd visited Range or Review — odd "done" state. Sev 1.
   `07-wizard-metrics.jpg`

11. **Wizard step 3 ("Range")** — It's actually a time-of-day window (From/To hour wheels), but the step is called "Range" right after I set temperature *ranges* — I expected more sliders. No helper text ("When do you usually do this?"), no "All day" option, and the default 6am–10am is pre-filled with no explanation. The wheels don't wrap (11pm is a hard stop), and a flick spins far. Good: inline red "Start and end can't be the same." with Next disabled. Confusion. Sev 2. `08-wizard-range-time.jpg`

12. **Wizard step 4 (Review)** — Preview card shows a solid green bar "Today · 9am–5pm" — reads as if today is already a perfect beach day, but it's just a mock of my window. Only 3 metric chips (Temperature, Wind Speed, Dust Alert) appear; UV Index and Moon Phase, which I ticked, are missing with no explanation (looks like only Priority metrics show). I wondered if my selections were lost. Confusion. Sev 2. `09-wizard-review.jpg`

13. **Home right after saving my first activity (location denied)** — Now I finally get a proper "No location yet — Time It needs a location to rate your activities. Enable access or pick a city." with Enable Location / Place your own location. Good copy, but it should have appeared *before* I spent 3 minutes building an activity (and on the empty home earlier). Above it sit TWO grey skeleton cards for my ONE activity, frozen, so the screen looks perpetually loading. No sign my "Beach day" was saved (name not shown anywhere). Friction. Sev 3. `10-no-location-after-save.jpg`

14. **Home with a city picked — first real card** — Delight: the screen comes alive instantly — big "DUBAI 28°", wind/humidity, sky gradient, and a compact card: score ring "84", an hourly strip for 9am–5pm, and a row of 7 weekday dots. Picking a city from the empty state was the fastest path to value in the whole app. Rubs: no words anywhere tell me whether today is good — no "Perfect"/"Good" label, no legend for green/orange/red, no idea what 84 is out of or why 1pm is orange. Friday's red dot has no reason. The past 9am segment is just pale grey with no "now" marker. Confusion. Sev 3. `11-home-first-card.jpg`

15. **Notification banner** — "Get a morning digest + Perfect window alerts · Turn on notifications" appears on Home — good timing (after first activity), clearer than the Settings toggle footer. Sev — (positive).

16. **Card → detail** — Tapped Friday's red dot on the Home card; the detail opened on *Wednesday* (today), not Friday — I had to tap Friday again. Friction. Sev 2. `12-detail-today.jpg`

17. **Detail screen layout** — Delight: day picker + score ring with a word ("Perfect" / "No Window") + hour chips + one card per metric with my band drawn on a mini slider and the value coloured green/red. On Friday I could instantly see *why*: Wind 30 km/h in red vs my 25 limit. This is the best screen in the app. Rubs below.

18. **"Perfect" on a mostly-red day** — Thursday and Tuesday show a green dot on the week row and "72 · Perfect", yet the hour chips are 9am green and 10am–4pm ALL red (40 °C, over my 36 limit). As a user I'd read "Perfect beach day Thursday" and get cooked. The verdict seems to be "best window exists" even if it's one hour — that needs saying ("Perfect 9–10am only"). Trust issue. Sev 3. `13-detail-tuesday-perfect-but-mostly-red.jpg`

19. **Score vs verdict mismatch** — Friday: ring "61" in red + "No Window". Wednesday "84 Perfect", Thursday "72 Perfect". 61 sounds like a passing grade but means no window; 72 means perfect. I can't build a mental model of the number. Confusion. Sev 2.

20. **Metric cards: which hour?** — Cards show one value (Thu 40 °C, Wind 11 km/h) but nothing says if that's now, the day's peak, the best window, or an average. Tapping an hour chip does nothing, so I can't inspect 1pm's orange. Untested angle / friction. Sev 2.

21. **Moon Phase data looks wrong** — Wed "new moon", Thu "first quarter", Fri "full moon", Sat "last quarter", Tue "full moon". The moon can't go new→full in two days; this cycles daily. Also lowercase ("new moon") unlike every other title-cased label. Anyone who picks Moon Phase (stargazers!) will stop trusting the app. Bug/trust. Sev 3.

22. **Forecast plausibility** — Thursday & Tuesday 40 °C in Dubai in mid-November while Wed/Fri/Sat are 30–31 °C. May be real provider data, but worth a sanity check — it drives the red hours. Sev 1 (flag for team).

23. **−/+ on the hour strip** — "+" slides my whole window one hour later (10am–6pm) — I expected it to extend the window. After shifting, the ring keeps saying "72 · Perfect" even though every visible hour is now red, until I spot and tap a small "Score 10am – 6pm" pill; then it flips to red "72 · No Window". Two-step "preview then score" is surprising, and the stale "Perfect" in between is misleading. The number 72 with zero good hours confirms the score isn't "how good is it". A little ↶ reset arrow is nice but tiny. Confusion. Sev 2. `14-detail-shifted-window-72-no-window.jpg`

24. **Editing an activity** — Detail bottom has small "Range" and "Metrics" round buttons (only found by scrolling to the very bottom). They reopen the 4-step wizard as "Edit Activity"; tapping the "Review" pill jumps straight there (nice), Save updates the detail live (temp now green under a 44° limit) — delight. Rubs: the "Did you know?" tip comes back every time; there's no way to rename/change icon except via the "Name" pill; **Delete Activity is hidden inside Edit → Review**, which I only found by accident. Sev 2.

25. **Detail scrolled** — When scrolled, the "Beach day" title and back button float over a blurred copy of the score ring/hour chips; the ring numeral peeks out beside the back chevron. Looks a bit muddy. Vibe. Sev 1. `15-detail-scrolled-header-overlap.jpg`

26. **Card chevron** — The chevron on the Home card collapses/expands the weekday dots row (down = expanded, right = collapsed). A right-pointing chevron on iOS means "go to detail", so I expected navigation. Score also jumped 84→94 after I loosened the temp limit, without the card saying anything changed. Sev 1.

27. **"Turn on notifications" banner** — only opens the Settings sheet; it doesn't trigger the permission prompt itself. Then in Settings, **tapping the Notifications switch never flips it** (tried 4+ times, on and off states). Only a sideways *slide* of the knob worked — that then showed the iOS prompt and turned it on. (Could be Simulator click handling on iOS 26 switches; worth checking on device, since other controls respond to taps fine.) After enabling: no confirmation of what I'll get or when the "morning digest" arrives. Friction. Sev 3. `16-notifications-on.jpg`

28. **Header vs detail temperature** — Home header says 28° (no unit) while today's detail Temperature card says 31 °C. Probably "now" vs something else, but unlabelled numbers that disagree erode trust. Sev 1.

29. **Second activity "Stars" (overnight 8pm–2am)** — "Night" icon category has exactly one icon (a moon — same glyph as the Moon Phase metric). Even after picking a night icon, the time step still defaults to 6am–10am. Setting 8pm → 2am works and isn't rejected (good), but nothing says "overnight, ends next morning". Sev 1–2.

30. **Overnight Review preview is garbled** — preview reads "Tonight · 8pm–2am" but the bar's axis runs "12am … 2am" with green only at the far right, so the 8pm–midnight part is missing. The metric chip says "☁ 20%" though I set Cloud Cover ≤ 40% (the Beach day preview showed metric *names* instead — inconsistent). Looks like mock data leaking into a preview. Confusion. Sev 2. `17-overnight-review-preview.jpg`

31. **Home with two cards** — Stars shows "100 · all green" for every night, which feels plausible-but-too-good; nothing hints it's just cloud cover being judged. Each card remembers its own expanded/collapsed state (new card arrives expanded, old one collapsed) — looks inconsistent side by side. No long-press menu, no swipe actions, no reordering; a horizontal swipe on a card just opens it. With many activities, managing them will be painful. Sev 2.

32. **Swipe-back** — Edge-swipe from the left on the detail screen didn't go back (tried twice, slow and fast); only the round ← button works. If this reproduces on device it breaks a core iOS habit. Sev 2 (verify on hardware).

33. **Stars detail** — Single Cloud Cover card floating alone on a big empty page, hour chips left-aligned with a gap before a disabled "+". For a stargazing activity the app can't use Moon Phase as a condition (it's display-only), which is exactly what a stargazer would want to judge on. Untested angle. Sev 1. `18-stars-detail.jpg`

34. **Dark appearance** — Overall good: cards go charcoal, green/orange read well, the blue sky header still feels like the app. Delight. Rubs: switching appearance while on the Stars detail re-rendered the hour strip as "10 11 12 1 2 3 4" all dimmed — wrong hours for an 8pm–2am window — until I left and re-entered (then correct "7 8 9 10 11 12 1"). Glitch. Sev 1–2. `19-dark-stars-hour-strip-shifted.jpg`, `20-dark-stars-detail.jpg`. Dark "Show only" checkbox outline is low-contrast. Sev 1.

35. **Cancel in Edit Activity** — dragged a slider then hit Cancel: changes silently discarded, no "Discard changes?" confirm. Fine for edits, but the same Cancel on a half-built *new* activity throws away a 4-step wizard without asking. Sev 2.

36. **Largest text (XXXL and Accessibility-XXXL)** — Text scales nearly everywhere (delight: wizard, Settings, card titles all grow and wrap cleanly). Rubs:
   - Home header becomes a sticky block (city, temp, time, wind, humidity stacked) eating ~40% of the screen; cards scroll *under* it, so at AX sizes you see about one and a half cards. Sev 2. `22-ax5-home.jpg`
   - Card title "Beach day" wraps to two lines while the score ring numeral and hour labels stay tiny (ring "94", hour digits "9 10" collide into "910"). The word "Score" becomes the biggest thing on the card — a label outranking the data. Sev 2. `21-xxxl-home.jpg`
   - Detail: hour chips, slider range labels (15/44) and the "−/+" buttons do not scale at all — unreadable for exactly the people using big text. Sev 2. `23-ax5-detail.jpg`
   - Wizard: step pills (Name/Metrics/Range/Review) stay tiny while "Next Step" is huge. Sev 1. `24-ax5-wizard.jpg`

37. **Returning user (relaunch)** — App comes back instantly with Dubai, both cards, and the collapse/expand states kept. No skeleton flash, no location re-prompt. Delight. Rubs: no "updated 10:43" / pull-to-refresh hint, so I can't tell if I'm looking at fresh or cached ratings; the notification banner is gone (fine, I enabled it). Sev 1. `25-relaunch-immediate.jpg`

38. **Deleting an activity** — Edit → Review → Delete Activity → "Delete this activity?" popover → Delete. It returns straight to Home with the card gone. A confirm is good. But it's 4 taps deep, and there's no Undo. Sev 1.

---
## Top 5 to fix first
1. **"Perfect" verdict on mostly-bad days** (#18, #19, #23). The week dots and "Perfect" label go green when only one hour qualifies, and the score number doesn't line up with the verdict (61 = no window, 72 = Perfect, 72 with zero good hours). Show the window ("Perfect 9–10am") and explain or rename the score. This is the app's core promise.
2. **Moon Phase changes every day** (#21). It goes new → first quarter → full → last quarter on consecutive days. It's obviously wrong data, and the people who'd pick it (stargazers) will spot it at once.
3. **Location-denied first run** (#1, #2, #3, #8, #13). There's no welcome. After "Don't Allow" the app doesn't explain anything, Settings says "Using current location" anyway, and the real "No location yet / pick a city" screen only appears after I've built an activity, sitting next to frozen skeleton cards. Show the pick-a-city prompt on the empty home.
4. **Notifications switch ignores taps** (#6, #27). Taps never flipped it; only sliding the knob worked. Turning it on gives no confirmation of what I'll get or when. The "Turn on notifications" banner only opens Settings. (Check on a real device too.)
5. **The wizard and Home don't explain themselves** (#9, #10, #11, #12, #14). The icon is required but nothing says so. "Priority" and "Show only" aren't explained. The "Range" step is really a time-of-day window. Review hides non-priority metrics. The Home card has no legend or verdict words. A few one-line hints would fix most of this.

Runners-up: city search only ever returns one result (#4). There's no °F or mph (#7). Text doesn't scale on hour chips or slider labels, and the sticky header grows huge at accessibility sizes (#36). Edge swipe-back didn't work (#32). Tapping a day dot opens the detail on today instead of that day (#16).

## What works well
The detail screen (one card per metric, my limit drawn on a mini slider, red value shows the reason). The inline gradient sliders in the wizard. Picking a city fills Home with live data straight away. Dark mode is solid. Relaunch is instant and keeps everything. Delete asks for confirmation.
