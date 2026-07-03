# Buddy parity review — Mac ⇄ iOS (2026-07-02)

Full content + visual + motion sweep of every screen. Tags: **[V]** visual · **[C]** content/feature ·
**[M]** motion. Screens verified in the sim against the Mac reference (`comparison.html`).
Mac = source of truth (`dist/index.html`).

## Correctly app-specific (NOT gaps — leave out of iOS)
"Give Buddy room" (reserve-space windowing), Quit Buddy, the in-app update banner (iOS updates via
TestFlight/App Store). All Mac-only; correctly absent.

---

## P1 — real gaps, should fix
1. **[C] The pin icon does nothing on iOS.** Mac `pinBtn` = "Pin open" + reserve-space — a
   desktop-window concept with no iPhone equivalent (dist:307). On iOS it's dead chrome
   (`ChromeButton("pin"){}`, TodayView:105). → Remove it (same call as "Give Buddy room").
2. **[C] History can't reach older days.** Mac pages Done/Skipped a week at a time via
   "Load more" (dist:1118, 1670–1681); the slider was deprecated. iOS shows a fixed
   `settings.historyDays` window with no way to load older history. → Add "Load more"
   (or show all within the retention bound).

## P2
3. **[C] Row actions are invisible / interaction model differs.** Mac reveals check · sleep ·
   remove on hover and edits on click-the-text (dist:1488–1500). iOS hides sleep/remove/edit
   behind a long-press and completes on a whole-row tap — no visible affordance that those
   actions exist. → Add a discoverable affordance (swipe actions, or a trailing control).
4. **[M] Motion is much thinner than the Mac.** Mac: item enter (slide+fade), done→Donezo FLIP
   glide, history crossfade, ~200ms red "wash" on escalation, staggered group entrances,
   Fade+Drift panels (dist:172–208). iOS has only a 0.2s background-color fade + a sheet move.
   The app reads static next to the Mac's calm motion. (Not visible in screenshots.)
5. **[C] Confetti is off-brand.** Mac = 100 **party-parrots (🦜)** bursting from bottom-right on a
   specific arc (dist:210–224). iOS = mixed emojis 👍🏼🦜✨🎉⭐️ arcing up-left
   (CelebrationView:15). → parrots-only, match the origin/arc.
6. **[C] Morning "Restore your last list" row missing.** Mac's empty morning offers a restore
   row from the restart stash / most-recent day (dist:1510–1519). iOS morning has none.

## P3 — subtle / polish
7. **[V] Chrome glyphs are SF Symbols, not Lucide.** pin/calendar/gearshape shapes differ from
   the Mac's Lucide (pin most). Accepted stand-in; bundling the Lucide SVGs would match exactly.
8. **[V] Settings slider is the stock iOS Slider** (fat track/thumb) vs the Mac's thin 6px track +
   18px solid thumb (dist:64–68). Cosmetic.
9. **[C] Future-tab rows aren't editable.** Mac parked rows are click-to-edit (dist:1704–1719);
   iOS shows text + `+`/`×` only.
10. **[C] Dead "focused/now" state in the store.** Mac removed it; iOS `BuddyStore.cycle` + MockData
    still model `.focused` (inert visually since taps use `complete`). Cleanup only.
11. **[V/C] Weather is a static moon.** No live Open-Meteo fetch / WMO→glyph / day-night (dist:543–589).
12. **[C] Reduced-motion** is thorough on Mac (dist:232–246); iOS only gates confetti.

---

## Screen-by-screen verdict
- **Daily lvl0/1/2** — visually matched (structure, Geist, date block, rows, escalation, dividers).
  Gaps are behavioral: pin (#1), row-action discoverability (#3), motion (#4).
- **Morning** — matched (done rows on top, sizing, scroll, footer). Gap: restore row (#6).
- **History** — matched across Future/Done/Skipped (segmented, selected icon, done-words, +/×).
  Gaps: Load more (#2), Future edit (#9).
- **Settings** — matched to the Mac's row set (Celebrate · Export · Report a bug · version).
  Gap: slider styling (#8).
- **Celebration** — needs parrots + arc (#5).
