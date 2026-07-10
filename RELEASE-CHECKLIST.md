# Buddy — pre-ship regression checklist

Run TOP TO BOTTOM before every Mac release or TestFlight upload. Automated
gates first (cheap), then the interactive passes for whatever surface the
change touched, then sync, then the ship announcement. A change that "only
touches colors" still runs the interaction pass on its platform — the
2026-07-10 tray-tap regression came from a *scroll* fix.

## 1 · Automated gates (always, both platforms)

- [ ] `pnpm ui:smoke` — 4/4 (wraps `__buddy.smokeTest()`: add/edit/Enter/Tab,
      escalation colors incl. lvl1 red pattern, merge suite, mid-edit sync guard)
- [ ] `cd ios && xcodebuild test …BuddyTests` — unit suite (incl. token parity
      vs `design/escalation-tokens.json`, merge vectors shared with the Mac)
- [ ] `cd ios && xcodebuild test …BuddyUITests` — interaction suite on a real
      simulator: tap-to-edit stays in place · keyboard reveal · Future scrolls
      · **swipe tray actions FIRE** (not just show) · sheet pass
- [ ] `cd src-tauri && cargo check`

## 2 · Mac interactive pass (browser, `python3 -m http.server` over dist/)

Per CLAUDE.md RULE 2: every touched element in **lvl0 / lvl1 / lvl2** and in
every interactive state (rest / hover / focus / done).

- [ ] Escalation sweep: 4→5→6 active. lvl1 = ALL text red (done rows too);
      lvl2 = white on red. Check Today, Done, Future, Settings, date header.
- [ ] Sheets: calendar + settings SLIDE up (fast→slow), close DOWN (slow→fast);
      closed sheet can't block clicks (pointer-events guard).
- [ ] Editing: click text → caret in place · Enter commits (no new task, no
      complete) · Tab hops rows · empty text deletes.
- [ ] Future: + sends (row flips to "Sent to today!", no jitter), × removes,
      undo restores, + hidden at 6 active, list SCROLLS with a real wheel.
- [ ] Hover: rows darken (never lighten on light/red), post-transition color.

## 3 · Mac native spot-check (`pnpm tauri dev` — red tray icon = Dev Buddy)

- [ ] Drawer reveals from right edge; pin works; only ONE Buddy running.
- [ ] Tray → Morning… opens a real window with the planner rendered (not
      blank), closes clean, no ghost window left behind (`swift` CGWindowList
      dump if suspicious).
- [ ] Update banner path untouched? If the release changes updater/windows,
      install the previous release and take the actual update.

## 4 · iOS interactive pass (simulator, `-uiFixture` states)

- [ ] `xcrun simctl launch booted fyi.whale.buddy -uiFixture lvl1` (and lvl2):
      red states match the Mac.
- [ ] Tap a task: text does NOT move; type; Done commits.
- [ ] Edit the LOWEST row: it lifts above the keyboard, settles back after.
- [ ] Add a task: one calm insert, no font flashing.
- [ ] Future (`future-long`): scrolls; swipe reveals tray; **tap each action —
      it must fire**; sent-row undo works.
- [ ] Sheets: slide up/down with the Mac's curves; NO flash above the bottom
      bar on close; escalation colors correct while a sheet is open.

## 5 · Sync (any release, and always after touching merge/sync/store code)

- [ ] `pnpm sync:doctor` — all containers on ONE bucket, version sane.
- [ ] Settings on both devices show the SAME bucket suffix ("Synced HH:MM · abc123").
- [ ] `pnpm sync:live` — two-device harness end-to-end.
- [ ] Cross-device smoke: add a task on one device → appears on the other;
      edit mid-poll → the FULL text survives (the "Thing→Thi" class).

## 6 · Ship + announce (memory: feedback-ship-announcements)

- [ ] Versions bumped in lockstep where relevant (`package.json`,
      `src-tauri/Cargo.toml`, `tauri.conf.json`); iOS build number = fastlane's.
- [ ] Mac release run green AND `gh release view` shows the tag; TestFlight
      lane exits green only after processing (it waits — trust green).
- [ ] Tell the user, unprompted: Mac version + how it arrives (update banner),
      TestFlight "0.1.0 (NN)", Dev vs real Buddy, and the exact things to check.

## When something slips through anyway

Write the regression as a TEST first (UI test / smokeTest case / sync vector),
watch it fail, then fix — this file exists because "swipe shows but doesn't
act" had every gate green except the one that didn't exist yet.
