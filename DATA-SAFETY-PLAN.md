# Buddy — Data Safety: Diagnosis, Fix & Test Plan

_Written 2026-06-18. Triggered by a reported data-loss incident. Based on reading
the live on-disk stores, the persistence code in `dist/index.html`, and two
adversarial reviews._

---

## TL;DR

- **No real data was permanently lost.** The June 17 tasks are safely archived in
  history inside the current live store. Today (the 18th) shows blank because the
  day rolled over and the morning flow moved them to history instead of carrying
  them into the active list.
- **But the incident exposed four genuine problems**, one of them scary
  (storage fragmented across multiple webview origins — a future origin change
  could strand everyone's data).
- **The fix is in two layers:** (1) a tiny "stop the bleeding" code change, then
  (2) make a real file on disk the source of truth so loss becomes effectively
  impossible. Cloud sync is a _separate, later_ decision — do not block data
  safety on it.

---

## What actually happened (evidence-based)

I read the three on-disk WebKit localStorage databases for Buddy. The current
live store (`fyi.whale.buddy`, modified today) contains:

- `today`: date `2026-06-18`, `morningDone: true`, **items: [] (empty)**
- `history`: 6 days including **2026-06-17 with the real tasks** — `Ghost Nav
  Proto` ✓, `Wimp Newsletter`, `Review Liam's Wimp stuff` ✓, `Expert page for
  Ghost`, plus some `Thing` test rows.

Reconstructed sequence:

1. You had real tasks on the **17th**.
2. You restarted on the **18th**. Stored date (17th) ≠ today (18th) → **rollover
   fired** (`maybeRollover`, `dist/index.html:563`). It archived the 17th into
   `history` (done/undone preserved) and set today to empty + `morningDone:false`.
3. The **morning planner showed** (because `morningDone` was now false). Its
   subtle "Add undone" affordance was the only path back to your tasks.
4. You clicked through / unpinned. `morningDone` flipped to true; today stayed
   empty because the tasks were never re-added to the active list.
5. Result: **active view blank, real work safe in history** — but it read as
   "everything's gone."

The unpin click did **not** delete anything. Unpin only toggles a flag, resizes,
and saves (`dist/index.html:689`). It was the trigger that revealed the
already-empty active list, not the cause.

---

## The four real problems

### P1 — Rollover silently empties your working set (UX + trust)
For an ADHD focus app, the single worst thing is "the three things I was working
on vanished from where I look." Rollover archives them correctly, but the
"carry yesterday's unfinished forward" moment (`toggleUndone`,
`dist/index.html:1098`) is a small, easy-to-miss button. **This is the bug you
actually felt.**

### P2 — Storage fragmented across webview origins (latent catastrophe)
Buddy's data lives in browser `localStorage`, which is bound to the webview's
**origin**. On disk I found **three separate stores**:
- `~/Library/WebKit/fyi.whale.buddy/...` (current, today)
- `~/Library/WebKit/buddy/...qmEF...` (orphaned dev data, Jun 14)
- `~/Library/WebKit/buddy/...rt2Ye...` (orphaned dev data, Jun 14)

When the origin changes (a dev port change, dev→prod, or any Tauri config
change), the app opens a **different, possibly empty** store and the old data is
**stranded** (not deleted — just unreachable). A production origin change would
strand every user's data at once. This is the most dangerous finding.

### P3 — Demo/seed data contaminates real history
`seedDemoHistory` (`dist/index.html:593`) runs whenever history is _empty_, not
only on genuine first run. The current store's older history days (`Reply to the
team`, `Water the plants`, `Plan the week`…) are **fake seed rows mixed into your
real history**. After any wipe it also re-seeds and the next save persists the
fake data over the empty real store, masking and cementing loss.

### P4 — A stack of latent durability defects (code-level)
From the adversarial review, all confirmed against the code:
- **All-or-nothing validation**: one malformed field in `today` discards _all_
  slices including valid history (`dist/index.html:543`).
- **Backup never restored**: `buddy.v1.bak` is written but only ever read by a
  test hook — and it stores the _failing_ raw, not a known-good snapshot.
- **No synchronous persist anywhere**: every mutation relies on a 250ms debounce
  whose only flush is JS `beforeunload`/`visibilitychange`, unreliable in a
  Tauri webview on quit/hide.
- **Silent quota fallback**: if `localStorage.setItem` throws, writes silently
  divert to an in-memory store that dies on reload — invisible loss.
- **Single key, single overwrite, no atomic write, no read-back verify.**

---

## The fix — two layers (durability), plus a design fix

### Layer 0 — Design fix for P1 (your call, designer decision)
Make the day hand-off impossible to miss and impossible to lose your set. Options
(pick the feel you want):
- **A. Auto-carry unfinished** into today's active list on rollover, and _show_
  it ("3 carried over from yesterday — keep or clear?"). Zero clicks to keep your
  work visible.
- **B. Keep the planner, but make "Carry yesterday forward" the primary, large
  action** (not the small "Add undone" pill), with a count.
- **C. Hybrid:** auto-carry into the planner pre-filled, you trim to three.

_Recommendation: C_ — matches the "pick your top three" ritual while never
hiding yesterday's work.

### Layer 1 — Stop the bleeding (small diff, no backend)
1. **Granular per-slice validation** — validate `today`, `history`, `deferred`,
   `settings` independently; a bad slice falls back to its own default and is
   logged + surfaced, never discarding the others. (Removes the `today` gate at
   `:543`; the code already validates slices granularly two lines below.)
2. **Demo seed only on true first run** — seed only when there was _no stored
   blob at all_, never merely because history is empty. Then **purge the existing
   seed rows** from your real history once.
3. **Synchronous rollover commit** — `writeNow()` immediately after archiving in
   `maybeRollover`, so the archive can't live only in memory / re-roll.
4. **Real backup + restore** — write `buddy.v1.bak` only from _validated,
   known-good_ state; on load failure, recover from it before any fresh boot;
   tell the user "recovered from backup."
5. **Surface write failures** — if `setItem` throws, show a banner instead of
   silently using memory.

### Layer 2 — Make a file the source of truth (kills P2 + makes loss ~impossible)
6. **Persist to a real JSON file** via the Tauri FS plugin
   (`~/Library/Application Support/fyi.whale.buddy/buddy.json`), written
   atomically (temp file + rename). This file is **origin-independent**, so it
   ends P2 entirely — an origin change can't strand it. localStorage becomes a
   fast cache; the file is the record.
7. **Load order**: read localStorage → validate per slice → for any bad/empty
   slice, fall back to the file → only default if both fail.
8. **Rust-side flush** on window-close / app-quit / `buddy://hide`, so the latest
   state always reaches the file regardless of JS unload events.

_Per the adversarial review, Layer 2's atomic file makes the verified-write +
3-slot ring buffer redundant — skip them. The file + granular validation +
sync rollover is the whole spine._

### Layer 3 — Nice-to-haves (only if cheap)
- Bound history growth (cap or roll old months into the file).
- Gate `__buddy.inject/clear/suppressSave/seedDemoHistory` behind a dev flag in
  production builds.

---

## Test plan (both gates required, per CLAUDE.md Rule 2)

1. **Extend `__buddy.smokeTest()`** with durability assertions:
   - A malformed `today` slice does **not** wipe history (granular validation).
   - Rollover archives yesterday **and** is persisted synchronously (kill the app
     immediately after rollover → data survives).
   - Demo seed does **not** fire when a real (even empty-today) blob exists.
   - File fallback: clear localStorage, confirm the app reloads from `buddy.json`.
2. **Origin-change test (manual):** change the dev origin/port, relaunch, confirm
   data still loads (from the file).
3. **Quota test:** stuff localStorage near full, confirm a write failure surfaces
   a banner rather than silently dropping.
4. **Visual red-state sweep** (lvl0/lvl1/lvl2) unchanged — confirm the new
   recovery banner is legible in all three.
5. Both `ok:true` AND a clean visual sweep before any `pnpm tauri build`.

---

## Sequencing

1. **Now:** nothing to recover — your data is in history. (Optional: I can purge
   the fake seed rows so history is 100% real.)
2. **Branch + Layer 1** (stop the bleeding) — small, ships the same day.
3. **Layer 2** (file source of truth) — the real durability win + ends P2.
4. **Layer 0 design fix** for rollover — once you pick A/B/C.
5. Cloud sync is **out of scope here** — see `IOS-COMPANION-PLAN.md`.
