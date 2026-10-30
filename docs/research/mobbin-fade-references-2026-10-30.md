# Header-colour melt references (Mobbin, iOS) — research, 2026-10-30

Source for ruling 5b of the depth pass ([FIGMA.md §12](../design/FIGMA.md), [ROADMAP item 17](../issues/ROADMAP.md)). Evidence only; design values live in Figma/code. Links go to Mobbin (no local copies of the screenshots are kept).

All heights below are eyeballed from the ~299x640 preview of a ~852pt-tall screen (1 preview px ~ 1.3pt). Treat as +/-15%. Mobbin shows still screenshots only, so motion claims are marked unverified.

## Summary
1. Pattern: the colour is a tall, soft wash that is strongest behind the hero number/header and thins out over roughly 40-60% of the screen, usually ending as the first card or list begins (cards sit on the tail of the fade, not below it).
2. Best 3 references: [Klarna home](https://mobbin.com/screens/9719ecff-3e15-438d-bc78-4a2797daaac2) (lavender into white, cards overlap the fade), [Revolut home](https://mobbin.com/screens/5be4e584-20cf-45a5-aade-d505997121b7) (saturated blue melting into a pale page), [Apple Weather](https://mobbin.com/screens/f7e0b42a-b5ea-4e48-9fb4-0ab3f04d7064) (whole-screen backdrop, translucent cards float on it).
3. Direction of melt: colour thins out downward into the ground colour; the ground never visibly "washes over" the band. Cards that overlap the tail carry the join.
4. Motion: no still can prove it; the only visible hints are soft off-centre blobs (Gentler Streak, Klarna's uneven tint), which are what an ambient drift would animate.
5. Recommendation: make the band ~35-40% of screen height as one long eased gradient (solid for ~90-110pt behind the numeral, then ~250-300pt of fade), start the first card inside the lower third of the fade, and animate a slow drift of a soft off-centre colour blob (not the whole gradient) over 20-40s.

## Chosen screens
| # | App | Screen | Link | What the fade does |
|---|---|---|---|---|
| 01 | Apple Weather | Home, Los Angeles 24 | https://mobbin.com/screens/f7e0b42a-b5ea-4e48-9fb4-0ab3f04d7064 | No band and no edge: the whole screen is one sky-photo backdrop. Numeral sits in the top ~30%, cards start at ~40% and are translucent, so the colour shows through them. Fade is effectively the full height. |
| 02 | Klarna | Home, Main account | https://mobbin.com/screens/9719ecff-3e15-438d-bc78-4a2797daaac2 | Lavender top (~10% solid) thins to white by ~65% of screen height. A white card overlaps the fade at ~45%; section title "Gift cards" is on near-white. Smooth, no visible band edge. |
| 03 | Klarna | Home, Membership cards | https://mobbin.com/screens/f102e3e3-a610-4931-9a8b-d8b787c26995 | Stronger lavender tint, fade reaches ~55% where the "Stores for you" heading is on white. Cards (translucent white) sit inside the tint. |
| 04 | Klarna | Home, pink/blue tint variant | https://mobbin.com/screens/5f04c098-4408-4ed9-83dc-c78d51085e07 | Two-hue wash (blue upper-right, pink lower-left) dissolving to white by ~45%. The uneven, off-centre hues are the part an ambient animation would drift. Motion itself unverified. |
| 05 | Future Pro | Home, This Week | https://mobbin.com/screens/02505ebf-b373-4f73-8a3a-d10d9ca3f409 | Very pale lilac-grey ground, slightly deeper at the top and easing to near-white by ~50%. Low contrast, long. Cards are opaque white-ish on top of it. Colour is subtle rather than a hero band. |
| 06 | Future Pro | Profile, beach photo | https://mobbin.com/screens/1f8965ab-02b5-4c9f-ac67-b3c07806824c | Photo band ~22% tall dissolves into the lilac-grey ground by ~30%; the photo fades out, ground does not cover it. Good example of the right direction of melt. |
| 07 | Jomo | Home, sky | https://mobbin.com/screens/864c37e0-bfb5-41a8-b6f1-ce21ceb3fdbf | Saturated blue sky ~45% solid behind the header, melting to near-white by ~75%. A white card overlaps the tail at ~47%; the button below sits on near-white. Long, eased. |
| 08 | Gentler Streak | Steps | https://mobbin.com/screens/671c6729-2af9-47e5-a225-a168b3987fc0 | Warm orange/yellow radial glow (hue = activity level, like your temperature hue) behind the big numeral, ~35% solid core, fading radially to white by ~58%. Closest match to a warm band behind a hero number. |
| 09 | Revolut | Home, blue | https://mobbin.com/screens/5be4e584-20cf-45a5-aade-d505997121b7 | Saturated blue top ~25%, fade to pale lavender by ~55%. Quick-action buttons sit on the tail; the transaction card starts at ~58%, white, over the end of the fade. |
| 10 | Bevel | Strain | https://mobbin.com/screens/d99b3093-5eca-4cc4-aadd-36a6de950dd1 | Peach/lilac dusk image fills the top ~35% and melts into light grey by ~45%; the ring sits across the fade and cards start just below. Image, not flat gradient. |
| 11 | (Not Boring) Weather | Clouds | https://mobbin.com/screens/9e430fd1-4712-4268-82ed-c2cc68d8a012 | Not a header-to-ground melt: a grey vignette that is darker at the edges and white in the middle. Included because it is the owner's named reference; its liveliness comes from 3D objects, which a still cannot show. |
| 12 | The Weather Channel | Home | https://mobbin.com/screens/2a9e8135-5669-4923-a97b-48fed3144d5e | Counter-example: photo band ~40% tall ends at a hard rounded sheet edge, no melt. This is the look to avoid. |

## Patterns (plain English)
1. **Long wash, cards on the tail (Klarna, Revolut, Jomo).** A solid colour for roughly the top 10-25% (the numeral area), then a long gentle fade finishing at 55-75% of the screen. The first card or quick-action row starts while the colour is still half there, around 45-58%. This is the most common recipe and the closest to what you describe.
2. **Glow behind the number (Gentler Streak, Bevel).** The colour is a soft blob or image centred on the hero, not a flat band across the full width. It fades in every direction, so there is no band edge at all. Reads as "alive" because the blob has an off-centre shape that can drift.
3. **Whole-screen backdrop (Apple Weather, Future Pro).** No band; the colour is the page. Cards are translucent (Apple) or sit over a very low-contrast ground (Future Pro). The fade length is the full screen.
- Direction of melt: in every good example the colour thins out into the ground; none shows the ground colour rising over the band. The apparent "ground washing over" look appears only in the Weather Channel hard edge.
- Which feel alive: Gentler Streak and Klarna's tint variants (uneven, off-centre hues), plus Apple Weather (photo backdrop). Not verifiable from stills; see below.
- Recommendation for this app: one long, eased fade (not linear) of about 250-300pt after ~100pt solid, so the band reaches roughly the middle of the screen; let the first white card start about a third of the way into the fade so the colour is visible behind its top edge; keep the temperature hue as a soft off-centre glow and drift it very slowly. Keep numerals' contrast checked at the solid part only.

## Not found / could not verify
- No motion evidence: Mobbin returned still screenshots (no video was returned for these screens), so I cannot say any of these screens animate. Apple Weather, Klarna and Future Pro are not confirmed as animated by anything I saw.
- Percent heights and "eased vs linear" are judged by eye from previews, not measured from pixels or specs. I could not tell from stills whether the curve is a true ease or several stops.
- The Klarna "pink/blue tint" and the 02/03 lavender variants may be the same screen at different scroll or time-of-day states; I did not verify what drives the change.
- Not Boring Weather results were all 3D/object screens; none showed a header-to-ground melt.
- Apple Weather appears here only as a photo-backdrop variant; I found no Apple Weather screen with a flat temperature-colour band.
- Future Pro's visible fade is faint; I did not find a screen where its colour is a strong band.
- I did not run searches for "ambient animated gradient", Copilot Money (the one Copilot screen was an in-demo overlay with a hard white fade, not used), Headspace (no gradient headers found), or the sections/flows endpoints; they would not add static fade evidence for iOS.
