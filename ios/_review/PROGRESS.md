# iOS Visual Parity — overnight run (started 2026-07-01 ~22:40)

**Goal:** make the iOS app LOOK like the Mac daily drawer. Mac (`dist/index.html`)
is the source of truth. Branch: `fix/ios-visual-parity` off `main`.

## Capability proven before starting
- iOS: `xcodegen generate` → `xcodebuild -sdk iphonesimulator` → boot sim → install →
  launch → `xcrun simctl io booted screenshot`. Works. (`_review/ios-*.png`)
- Mac: serve `dist/` on :8899 → Playwright at 340×760 → `__buddy.inject(blob)` →
  screenshot. Works.

## The gap (why it looked "very very different")
1. **Font**: iOS used system SF; Mac uses **Geist**. → bundling Geist OTFs.
2. **Structure**: Mac = two floating rounded cards (r=24) w/ panel shadow; chrome
   icons + date INSIDE card 1; list = card 2. iOS = plain header + one card (r=16) +
   native iOS nav toolbar.
3. **Date**: Mac numeral LEFT @62 medium, weekday 24 medium, month 18 dim. iOS numeral
   RIGHT @56 bold, system.
4. **Rows**: Mac clean text at rest (actions on hover); iOS shows a check circle +
   number badge always. Mac add row "Add +" 18px gap.
5. **Donezo**: Mac "Donezo." 15 semibold + struck title inkDim. iOS close but off.
6. **History/Settings**: Mac = custom in-card sheets; iOS = native List/Form + nav bar.

## Mac reference values (from dist/index.html)
- Tokens: --red #e5484d; ink #000 / dim rgba(0,0,0,.45); lvl2 card=red, ink=#fff,
  dim=rgba(255,255,255,.6); line #d9d9d9 / lvl2 rgba(255,255,255,.30).
- Card: w-400, radius 24, bcard panel shadow (0 1 4 /.04, 0 6 16 /.06, 0 14 34 /.09).
- Drawer: p-2 (8px) around, gap-2 (8px) between cards.
- Header row: px-8 py-6; chrome-btn 39px round, icons 14–17px; "Buddy" 18px ink/60.
- Date block: pl-8 pr-[26px] py-8; numeral 62px medium tracking-[-1.24px]; weekday
  24px medium -0.48; month 18px dim -0.36; weather 50px box. gap-3 between num & stack.
- Active row: font-medium tracking-[-0.48] line-1.2; size --fs clamp(13,h*.30,24);
  padding --vpad(10–30) / --px(20–32). Morning list: fs22 vpad30 px32.
- Add row: "Add" + "+" gap-[18px], medium, --fs, addtxt color rgba(0,0,0,.20).
- Donezo row: pad 16 (drawer)/18(morning); tag 15 semibold color ink; title 15
  line-through ink-dim. History groups: header 18 medium; rows tag/title 18px.
- Icons right padding: ICON_RIGHT 1.25rem (20px).

## Log
- [done] Proved capture on both sides.
- [done] Bundled Geist-Regular/Medium/SemiBold/Bold OTFs (PostScript = Geist-<Weight>).
- [done] Font wiring (UIAppFonts) + `Font.geist()` helper + GeistFontCheck guard.
- [done] Deterministic screenshot harness: `-uiFixture <name>` → seeds state + opens surface.
- [done] TodayView rebuilt → two Geist cards, chrome row, numeral-left date, clean rows,
  Donezo-on-top, Add row, escalation lvl0/1/2 all verified in the sim.
- [done] SettingsView rebuilt → custom Buddy sheet (✕ header, 👍🏼…🦜 slider, dividers, pills).
- [done] HistoryView rebuilt → [Future|Done|Skipped] segmented sheet, Geist day groups.
- [done] MorningView rebuilt → centered Geist planner, bordered card, Skip/Buddy! footer.
- [done] Added store methods restoreHistoryTask / wakeDeferredTask (mirror Mac).
- [done] All 37 iOS unit tests pass (`xcodebuild test`).
- [done] Mac references captured; `comparison.html` built (open it to review).

## Status: DONE for the night — all 5 surfaces ported and matching.
Screens: daily lvl0/1/2, morning, history, settings. See comparison.html.

## Known deltas / recommended follow-ups (see comparison.html for the full list)
- Done words are fixed "Donezo." (Mac rotates a word list) — easy port.
- Row interaction: tap=complete, long-press=edit/sleep/remove (no hover on iPhone) — confirm feel.
- Mac removed the focused/"now" state; iOS store still models it (3 tests) — small functional PR to align.
- Weather is a static moon glyph; live fetch not ported.
- Morning lists active only; Mac also shows done rows there.

## How to regenerate any screenshot
    cd ios && xcodebuild ... build   # (see buildcmd below)
    xcrun simctl install booted /tmp/buddy-dd/Build/Products/Debug-iphonesimulator/Buddy.app
    /tmp/buddy-shot.sh <fixture> out.png    # fixture: lvl0 lvl1 lvl2 empty morning history settings
