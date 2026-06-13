# Buddy — Status & Handoff

_Last updated: 2026-06-12. Branch: `main` (PR #3 merged)._

A macOS menu-bar focus app for ADHD: each morning pick your top three; a right-edge drawer holds them all day; mark one "now", check things off, glance at the last 7 days. Repo: **github.com/whale/buddy** (private).

## How to run

**Web app (fastest to iterate):**
```
cd ~/Projects/buddy && python3 -m http.server 4500   # open http://localhost:4500
```
**Native Mac app (Tauri):**
```
cd ~/Projects/buddy && source "$HOME/.cargo/env" && pnpm tauri dev
```
(Rust 1.96 + `time` pinned to 0.3.47 via committed `Cargo.lock`. First compile ~minutes, then fast.)

To clear app data and see a fresh morning: quit, `rm -rf ~/Library/WebKit/buddy`, relaunch.

## What works (verified)

- **Web app, complete & self-tested:** morning → top 3, drawer with now/done/neutral cycle, pencil-edit, ×-remove, 5/6 red escalation (no 7th), Last-7-days history (slide-up) with pull-forward (+) and undo, daily rollover + persistence + corruption guard.
- **Native Mac app compiles and runs** as a transparent, frameless, always-on-top **420px right-edge drawer** below the menu bar. Menu-bar tray icon + backtick global shortcut wired.
- **Morning takes over full-screen and persists** (keyed off a `morningDone` flag; survives the tauri-dev double-boot). Dismiss only via "Skip today" or by picking three.
- **Add bug fixed** (was an id collision after reload).
- **Celebration is a slider** 👍🏼→🦜 (one floaty thumb → ~200 parrots, staccato, bursts up-left). Auto-uses any parrot gifs in `assets/` (4 real ones present).
- **Settings**: full-width rows in month-style text, Export / Erase / dev Restart.
- Selected state = darker bg (no box); focus-on-red = 15% black; history kept forever.

## Not done / deferred

- **Edge-reveal (hide/show on hover the right edge)** — attempted as a 14px sliver, but it was invisible/un-findable, so **reverted** to the always-visible drawer. Needs an **interactive** redo (Claude changes one thing → owner hovers and reports → repeat), not a blind one-shot.
- **Reserved space when pinned** (apps can't go behind it) — no public macOS API; the only route is the **Accessibility API** (a mini window-manager). A real, separate build; pinned currently floats on top.
- **Temporary diagnostic instrumentation still in the code** — a Rust `trace` command + `T()` calls + window-event logging (used to diagnose the morning bug). **Remove these** as a cleanup pass.

## Next likely work

1. Remove the diagnostic `trace`/`T()`/window-event logging (cleanup).
2. Build **edge-reveal** interactively (sliver → hover-expand) with the owner testing each step; make the hidden state a clearly visible, hoverable handle.
3. Native polish: notch/dock insets, the morning→drawer transition feel, menu-bar icon reflecting the current "now".
4. Decide whether to pursue **reserved-space** (Accessibility-API window-nudging) or leave pinned as always-on-top.
5. Open design calls from `PLAN.md` §12 (settings-gear placement, a bigger flourish when all three are done).

## Key files
`index.html` (whole web app), `src-tauri/` (Tauri shell), `PLAN.md` (full spec), `README.md`, `README-MAC.md` (native run steps), `MORNING-REPORT.md` (overnight-build snapshot — historical).
