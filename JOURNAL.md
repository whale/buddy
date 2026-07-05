# Buddy — Journal

Non-obvious learnings, gotchas, and decisions worth not re-learning the hard way.
Newest first.

---

## 2026-07-01 — "random" celebration words weren't random (deterministic hash of sequential ids)

**The bug.** A tester's completed tasks showed patterned done-words (Donezo / Ticked Off /
Donezo / Ticked Off) instead of random ones. The word was `DONE_WORDS[hash(id) % 25]` — a
*deterministic* pick, chosen so the word stays stable across re-renders (a good goal). But
the input was the task **id**, and ids are often **sequential** (history rows `h-DATE-0/1/2`,
the `n1/n2` fallback). A rolling hash of near-identical strings increments in lockstep, so
`% 25` **marched down the word list** — neighbouring tasks got neighbouring words. Random
UUID ids actually spread fine; the bug only surfaced when ids were sequential, which is easy
to miss if you only test with fresh UUID tasks.

**The fix.** Don't derive randomness from a value that isn't random. Use a **shuffle bag**
(every word handed out once before any repeat, then refill) and pick **once at completion**,
storing the result on the item (`it.doneWord`). That gets you *both* properties the hash was
trying to fake: genuinely spread out (bag) AND stable across renders (stored, not recomputed).
Persist it; backfill existing done items at boot so an old list re-shuffles immediately.

**Lesson: a deterministic hash of a non-random, sequential input is not a shuffle — it's a
march.** If you want "random but stable," roll once and store the result; don't hash an id and
hope it looks random. **Verify with the real input distribution** (sequential ids), not just
the happy-path one (UUIDs) — and confirm a pre-existing test failure is pre-existing by
stashing your change and re-running (the "hit targets" smoke check failed on baseline too).

## 2026-06-30 (later) — "Done" was conflating done + skipped; Future became a manual backlog

**The design bug.** History stores each task as `{text, done}`, and the Done tab rendered
*every* past task regardless of `done` — so tasks you **skipped** showed up in "Done" as
plain (un-struck) rows. "Done" should mean *done*. Fix: split into three tabs — Done
(`done:true` only) + a new Skipped tab (`done:false`), alongside the existing Future. The
data already carried the distinction; only the *view* was over-showing. **Lesson: when a
list looks "polluted," check whether the data is mixed or just the view — here the view was
the bug, the data was fine.**

**Future: auto-return was the wrong mental model.** Deferred ("Future") tasks auto-returned
to today at the next rollover (`wakeDeferred`). The user's instinct: Future should be a
*manual* backlog you pull from — auto-refilling the day with avoided tasks fights the whole
calm-focus premise. Reshaped Future into a holding pen: no auto-return, **+** to add, **×**
to remove, click-to-edit (mirrors the live list). Kept the cap guard (**+** hidden at
`HARD_CAP`) so pulling from Future/Skipped still can't overflow the day. The `wake` date
field is now vestigial (kept only for serialization shape).

**Releasing a feature — two gotchas.** (1) The auto-bump bot **+1's the patch on every merge
to `main`**, so a deliberate `0.3.0` in the PR shipped as **0.3.1** — set the version
expecting the bump, or add `[skip release]` to freeze it. (2) A **manual**
`gh workflow run "Release Mac app"` publishes even when `AUTO_RELEASE_MAC=false` — a
`workflow_dispatch` bypasses the gate, so you don't need to flip the var for a one-off release.

**Distribution is already solved (re: "how do I get an alpha tester?").** Because the app is
signed + notarized and the repo is public with a working auto-updater, onboarding a tester is
*just send the DMG link* — no TestFlight, no per-tester provisioning. Requirement: macOS 13+.
The only real friction is telling them it's a menu-bar / right-edge app so they know where it
went. First launch may show a one-time "downloaded from the Internet — Open?" dialog (normal;
notarized, so no hard Gatekeeper block).

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
