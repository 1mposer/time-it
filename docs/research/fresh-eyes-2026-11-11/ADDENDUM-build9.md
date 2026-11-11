# Addendum: the 38 notes re-checked on build 9 with real data (2026-11-11)

> This re-checks [NOTES.md](NOTES.md) against **build 9** (main `8a2d7bf`, `CFBundleVersion` 9). The app was a **Release** simulator build, so it called the production backend (`https://time-it-production.up.railway.app`). Weather data was real Meteosource data, not the fixture used in the first run. The route matched the first run: fresh install, deny location, Settings, pick a city, Beach day (day activity), Stars (overnight 8pm–2am), detail, edit, notifications, dark mode, AX5 text, relaunch, delete. Screenshots sit beside the originals as `b9-<nn>-<what>.jpg`.

## Where the data came from

- `GET /health` returned `{"status":"ok","timestamp":"2026-11-11T17:28:31.384Z"}`.
- `POST /api/v1/rating` for Dubai (25.2048, 55.2708) returned `forecastStart` **`2026-11-11T17:00:00Z`**, `timezone` `Asia/Dubai` and 163 hours. `hours[0].moon` was **`["new moon"]`**. The moon phase reads `new moon` from Wed 11 to Mon 16 and `first quarter` from Tue 17. That is a believable lunar sequence, not the daily cycling seen in the first run.
- **Simulator:** I started on the shared `iPhone 17 Pro` (E0C39F0A…). At 21:32:17 local time, another lane's test run installed a **Debug** build over mine (`TimeIt.debug.dylib` present, different binary hash) and killed the app. Every note from #9 onward was therefore driven on a dedicated simulator, **`RERUN 17 Pro`** (F2C4BF4E-45D3-4D29-92D5-B38FB3A5F756, iOS 26.5). I installed the same Release `.app` there and set the location to Dubai. Shots b9-02…b9-08 come from the first simulator before the Debug install, while it was still running the Release process. b9-01 was re-shot on the new simulator.
- **Side effect:** turning notifications on (#27) sent a device `PUT` to the **production** backend with a simulator APNs token. One test `devices` row now exists in production.

## Verdict per note

| # | Verdict | Evidence (one line) | Shot |
|---|---|---|---|
| 1 | STILL-TRUE | A new opening splash plays, then the system location prompt appears over a "NO LOCATION" header. There is still no welcome or explanation first. | `b9-01-first-launch-location-prompt.jpg` |
| 2 | STILL-TRUE | After denying location, the empty Home shows "NO LOCATION" and Add Activity, with no "location denied / pick a city" hint. | `b9-02-denied-empty-home.jpg` |
| 3 | STILL-TRUE | With location denied, Settings → Home still says "Using current location". | `b9-03-settings-denied-says-current-location.jpg` |
| 4 | STILL-TRUE | The search field is not auto-focused. "Springfield" gives only MO. "A" gives only "Eastern Macedonia and Thrace". | `b9-04-city-search-single-result.jpg` |
| 5 | STILL-TRUE | After picking Dubai, a "Use current location" row appears with no icon, misaligned under the iconed row. | `b9-05b-settings-use-current-row-no-icon.jpg` |
| 6 | STILL-TRUE | Tapping the Notifications switch (no activities, location denied) does nothing: no prompt, no message. The footer still says "Perfect window alerts". | `b9-05-settings-notif-toggle-wont-turn-on.jpg` |
| 7 | STILL-TRUE | Units has only "Wind speed km/h". There is still no temperature unit. I did not open the picker to look for mph. | `b9-03-settings-denied-says-current-location.jpg` |
| 8 | STILL-TRUE | "Use current location" silently drops Dubai and goes back to "Using current location", with no warning while location is denied. | `b9-08-use-current-silently-wipes-city.jpg` |
| 9 | STILL-TRUE (narrowed) | Next stays disabled after typing a name, and nothing says an icon is required. Sports is now expanded by default, so icons are visible. Beach & Water still has only water-sport glyphs. | `b9-06-wizard-name-next-disabled-no-hint.jpg` |
| 10 | STILL-TRUE (narrowed) | Most of this is fixed. Priority moved to its own "What matters most?" step and is not pre-checked. "Show only", "Did you know?" and the early ✓ on the pill are gone. Dust Alert has its own glyph. Still true: the slider is twitchy (15 px of drag ≈ +3 °C), there is no typed entry, and Moon Phase is ticked with no explanation. | `b9-07-wizard-metrics.jpg` |
| 11 | STILL-TRUE (narrowed) | The step is renamed "When do you go?", which fixes the "Range" confusion. There is still no "All day" option and no helper text, and it still defaults to 6am–10am. | `b9-08-wizard-when-do-you-go.jpg` |
| 12 | FIXED-BY-BUILD-9 | The review preview is now neutral: no fake green "Today" bar and no metric chips that could look like lost selections. | `b9-09-wizard-review-created-before-save.jpg` |
| 13 | STILL-TRUE | Saving the first activity with no location shows "No location yet" under **two** frozen skeleton cards for one activity. The activity name is not shown. | `b9-10-no-location-after-save.jpg` |
| 14 | STILL-TRUE | The card has no verdict word and no legend. Today (window already passed) shows an empty ring and a grey bar with no explanation. | `b9-11-home-first-card-no-verdict-words.jpg` |
| 15 | STILL-TRUE (positive) | The "Get a morning digest + Perfect window alerts" banner appears after the first activity and city. | `b9-11-home-first-card-no-verdict-words.jpg` |
| 16 | STILL-TRUE | Tapping Friday's dot on the card opens the detail on **Wednesday** (today). | `b9-12-detail-opens-today-not-tapped-day.jpg` |
| 17 | STILL-TRUE (positive) | The detail still works well: day picker, ring plus word, hour chips, and one card per metric with the band drawn in. | `b9-13-detail-thursday-real-data-perfect.jpg` |
| 18 | **STILL-TRUE (real data)** | Not a fixture artefact. Stars tonight shows **"20 · Perfect"** and a green week dot, but only 10pm is green and 9, 11, 12 and 1 are red (cloud 64% against a ≤40 limit). It also shows in the wizard's live review preview. | `b9-13b-stars-tonight-20-perfect-mostly-red.jpg`, `b9-17-overnight-review-real-data-perfect-dot-score-20.jpg` |
| 19 | STILL-TRUE | A score of 20 sits beside the word "Perfect", while 91–93 also read Perfect, so the number and the verdict still disagree. | `b9-13b-stars-tonight-20-perfect-mostly-red.jpg` |
| 20 | STILL-TRUE | Metric cards show one value with no hour, peak or average label. Tapping an hour chip does nothing. | `b9-13-detail-thursday-real-data-perfect.jpg` |
| 21 | FIXTURE-ARTEFACT | With real data the phase holds at "new moon" for days and then moves to "first quarter", so the daily cycling was fixture data. The **lowercase label is still true** ("new moon", "first quarter"). | `b9-13-detail-thursday-real-data-perfect.jpg` |
| 22 | FIXTURE-ARTEFACT | Real Dubai temperatures are 22–29 °C. There are no 40 °C days. | — |
| 23 | STILL-TRUE | "+" shifts the whole window to 10am–6pm. The ring keeps the old verdict until you tap a separate "Score 10am – 6pm" pill. | `b9-14-detail-plus-shifts-window-score-pill.jpg` |
| 24 | STILL-TRUE | Small Range and Metrics buttons sit at the very bottom. **Delete Activity is still only inside Edit → final step.** Editing now means stepping Next ×3, because the jump-to-Review pill is gone. The "Did you know?" tip no longer returns. | `b9-24-delete-hidden-in-edit-review.jpg` |
| 25 | STILL-TRUE | When scrolled, the title and back button float over a blurred ring and hour strip, and the ring peeks out beside the chevron. | `b9-15-detail-scrolled-header-overlap-and-edit-buttons.jpg` |
| 26 | STILL-TRUE | A collapsed card shows a **right** chevron, which reads as "go to detail". | `b9-26-relaunch-settled.jpg` |
| 27 | STILL-TRUE | The banner only opens Settings. Tapping the switch never flips it. Only sliding the knob shows the iOS prompt. After allowing, there is no confirmation of what will arrive or when. | `b9-16-notifications-on-no-confirmation.jpg` |
| 28 | STILL-TRUE (narrowed) | The Home header still reads "28°" with no unit. I could not repeat the header-vs-detail mismatch, because today's window had passed and the detail showed "—". | `b9-18-home-two-cards-real-data.jpg` |
| 29 | STILL-TRUE | The Night category still has exactly one icon (the Moon Phase glyph). The time step still defaults to 6am–10am after a night icon. Nothing says "overnight, ends next morning". | `b9-08-wizard-when-do-you-go.jpg` |
| 30 | FIXED-BY-BUILD-9 | The overnight review preview axis now runs 8 → 2 with real hours. There is no mock "☁ 20%" chip. | `b9-17-overnight-review-real-data-perfect-dot-score-20.jpg` |
| 31 | FIXTURE-ARTEFACT | With real data Stars is 20 with a mixed week, not "100 all green". New cards and existing cards now both arrive expanded. I did not test long-press, swipe or reorder. | — |
| 32 | FIXED-BY-BUILD-9 | An edge-swipe from the left on the Stars detail went back to Home on the first try (simulator only; not checked on hardware). | — |
| 33 | STILL-TRUE | The Stars detail shows Cloud Cover and Moon Phase. Moon is display-only, so a stargazer still cannot judge on it. The page is sparse and "+" is disabled. | `b9-13b-stars-tonight-20-perfect-mostly-red.jpg` |
| 34 | NOT-REACHED | The app overrides the system appearance once you pick one in the app, so `simctl ui appearance dark` while on the detail changed nothing. The only control sits on Home and in Settings, so I could not repeat "switch while on detail". Entering the detail after switching to dark shows the correct 8…1 strip. The low-contrast "Show only" checkbox no longer exists. | `b9-20b-dark-stars-detail-strip-correct.jpg` |
| 35 | STILL-TRUE | In Edit I dragged the temperature max, then tapped ✕. The change was discarded silently, with no "Discard changes?" prompt. A new activity's ✕ behaves the same. | `b9-15-detail-scrolled-header-overlap-and-edit-buttons.jpg` (state after close) |
| 36 | STILL-TRUE (narrowed) | At AX5 the Home header is a sticky block about 40% tall. "Score" outranks the ring numeral, and hour digits collide ("910"). In the detail, hour chips, slider labels and −/+ do not scale. The wizard step-pill rub is gone (there is a progress bar now), but see "New on build 9". | `b9-22-ax5-home.jpg`, `b9-22b-ax5-home-scrolled-sticky-header.jpg`, `b9-23-ax5-detail.jpg` |
| 37 | STILL-TRUE | Relaunch keeps Dubai, the cards and the collapse states. There is no "updated hh:mm" and no pull-to-refresh hint. Relaunch is **no longer instant**: the opening splash plays on every cold launch. | `b9-25-relaunch-immediate.jpg`, `b9-26-relaunch-settled.jpg` |
| 38 | STILL-TRUE | Delete is Detail → Metrics → Next ×3 → Delete Activity → popover → Delete, with no Undo. | `b9-38-delete-confirm.jpg` |

**Counts:** STILL-TRUE 31 (two of them positive notes, #15 and #17) · FIXED-BY-BUILD-9 3 (#12, #30, #32) · FIXTURE-ARTEFACT 3 (#21, #22, #31) · NOT-REACHED 1 (#34).

## New on build 9

1. **Days 5 and later can rate Perfect on missing UV data (server).** From Mon 16 onward the production response carries `uV: 0` at 9am, noon and 3pm in Dubai, while days 0–4 read 1.5–6.0 at the same hours. The provider stops sending UV past its horizon, and the adapter's `uv_index ?? 0` turns that gap into a reading that passes any `max` threshold. The app shows "UV 0" in green on a sunny Tuesday. This is the same false-Perfect class as B2: missing data should fail, not pass. (`b9-13-detail-thursday-real-data-perfect.jpg` shows UV 4 on a covered day; the Tuesday UV 0 was read in the app and confirmed over the API.)
2. **The metric grid moves under your finger.** Selecting a tile can open its slider in place as a full-width row, and that re-orders the grid. My next taps landed on Humidity and Visibility instead of what I aimed at. Deselecting works only through the ✓ on an open tile. Tapping a selected, closed tile opens it rather than deselecting it. `b9-new-metric-grid-reflows-on-select.jpg`
3. **"What matters most?" step.** The step itself is clearer than the old "Priority" checkbox. But "Pressed ones matter most. The rest still show." still does not say *required* versus *nice-to-have*, and Moon Phase drops out of this step without explanation. `b9-new-what-matters-most-step.jpg`
4. **The review says "created" before Save.** "First activity created" and "Activity created" appear above a **Save Activity** button that has not been tapped yet. In Edit it reads "Your activity … is on your dashboard". `b9-09-wizard-review-created-before-save.jpg`
5. **The review preview now uses live data.** That is good, but it makes #18 visible during creation: Stars previewed as "20" with a green Perfect dot for tonight. `b9-17-overnight-review-real-data-perfect-dot-score-20.jpg`
6. **A day whose window has passed reads as a bad day.** Today's detail shows an empty ring, **red "No Window"**, and "Time passed" in small grey text. Red suggests bad weather rather than "already over". `b9-12-detail-opens-today-not-tapped-day.jpg`
7. **The opening splash plays on every cold launch.** It is about 1.5–3 s of three circles and a "Time it" wordmark with a lowercase *it*, while the rest of the app says "Time It". It replaces the instant relaunch the first run praised (#37). `b9-25-relaunch-immediate.jpg`
8. **At AX5 the wizard's Next button covers the list.** The pinned button overlaps the "Wellness" row, and that row's text shows through it. `b9-24-ax5-wizard-next-overlaps-list.jpg`
9. **Dark palette.** It is solid on Home and the detail, and the Stars strip renders correctly (`b9-20-dark-home.jpg`, `b9-20b-dark-stars-detail-strip-correct.jpg`). The new top-left Home control for switching appearance is an unlabeled half-filled circle; nothing says what it does.
10. **Process note.** Lanes running UI tests on the same named simulator (`iPhone 17 Pro`) will reinstall Debug over a Release drive. Later re-runs should use their own simulator.
