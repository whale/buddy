# Buddy — Journal

Non-obvious learnings, gotchas, and decisions worth not re-learning the hard way.
Newest first.

---

## 2026-06-30 — "Flash then hide" was full-screen Spaces, not z-order (+ the updater stranding bug)

**Symptom.** After a release, the installed app stayed a version behind (no update
check mark). Worse, on launch Buddy would "flash up momentarily then hide behind
other windows," and clicking the tray "Show / Hide Buddy" did nothing.

**Two wrong guesses first (the lesson).** I assumed the window was losing z-order /
not staying frontmost, and shipped fixes around `set_focus` and `alwaysOnTop`. They
didn't work because the premise was wrong. The turning point was *running the real
app and inspecting the live window* (`CGWindowListCopyWindowInfo` via a tiny Swift
script) instead of theorizing: the window was already at floating **layer 5**, so it
literally could not be "behind" a normal window. **Inspect live state before
designing a fix — two iterations were wasted guessing.**

**Real root cause.** The window is `"alwaysOnTop": true` by config (in
`tauri.conf.json`). A floating window **cannot draw over an app in native
full-screen mode** unless its `NSWindow.collectionBehavior` opts in. The user works
in full-screen, so morning rendered on the *desktop* Space, got covered by the
full-screen browser, and "Show / Hide" re-showed it on a Space they weren't looking
at — looking like nothing happened.

**Fix.** Set `collectionBehavior |= CanJoinAllSpaces | FullScreenAuxiliary` at launch
(`allow_over_fullscreen` in `src-tauri/src/lib.rs`, via `objc2-app-kit`). Verified
live: behaviour value == **257** (1 = CanJoinAllSpaces, 256 = FullScreenAuxiliary).
Confirmed visually by the user in their real full-screen setup.

**Second bug, exposed by the first.** The reason the fix (and the prior release)
never *reached* the Mac: the in-app updater checked **once**, ~2.5s after launch, and
**swallowed errors silently**. One failed/missed check = stranded a full version
behind with no banner and no signal. Now it checks at launch, every 3h, and on window
focus (throttled to 1/min, stops once a banner shows), and `trace()`s failures so a
missed update appears in the bug-report logs.

**Delivery gotcha.** Because the updater itself was the broken link, you can't use it
to deliver its own fix — had to install the signed build directly (drag the DMG over)
once. After that, normal in-app updates resume.

**Takeaways.**
- A menu-bar / accessory app that must appear over full-screen apps needs
  `CanJoinAllSpaces | FullScreenAuxiliary`, not just `alwaysOnTop`.
- "Hidden behind a window" with an always-on-top window almost always means
  **Spaces / full-screen**, not z-order.
- Verify the *delivery path*, not just the fix — a silent once-only updater can mask
  every shipped fix.
