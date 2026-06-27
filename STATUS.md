# Buddy — Status & Handoff

_Last updated: 2026-06-26 (evening). Current branch: `main`. Latest **released** version: **`0.2.39`**. `main` is at **`0.2.43`** with a batch of merged-but-UNRELEASED work — **`AUTO_RELEASE_MAC` is OFF on purpose** (see release state below)._

Buddy is a shipped, public, self-updating macOS menu-bar focus app for ADHD.
Repo: `github.com/whale/buddy`.

## Session summary — 2026-06-26 (evening) — data-loss fix shipped + Done-tab/UX overhaul (batched, unreleased) + token-system spec

**Released 0.2.39 (PR #44): overnight task-loss fix.** Root cause traced from the user's on-disk
state: "Restart Buddy" stashed the list in a RAM-only var → dismissing the morning / relaunching
lost it, and three backup layers all failed (recovery file overwritten because leftover tombstones
made an empty-today look "recoverable"; `.bak` only healed an *unparseable* primary, not a valid-empty
one; the empty-over-full guard lived only in the sync path). Six safety-only fixes: Restart now
persists its stash + tombstones what it clears; Rust recovery-file ratchet; `load()` heals from `.bak`
+ won't overwrite a fuller `.bak`; `.bak` added as a boot-reconcile source; the **live midnight
rollover** now carries unfinished forward + wakes deferred (shared `rolloverAndCarry()` with boot —
previously only boot did, so leaving Buddy open across midnight dropped the working set); smokeTest
cases for all of it. The user's 4 lost tasks were recovered from the `.bak`. smokeTest 24/24.

**Merged but NOT released** (all in `main`; `AUTO_RELEASE_MAC` flipped OFF to batch them):
- **#45** weather stroke 2→1.4; **Skip/Buddy! hover fixed** (an inline `style=color` was defeating the `:hover` rule; Buddy! now *darkens* on red, not lightens); RULE 2 gained an every-color+interactive-state clause.
- **#46** Done tab now shows skipped/undone past tasks with a **↩ restore-to-today** arrow; removed the side-drawer restore row (morning restore untouched).
- **#47** Done tab shows **one week + "Load more"**; dropped the vestigial `historyDays` setting.
- **#48** the "Donezo." label now **rotates through 25 phrases** (deterministic per task id; Title Case + "!").
- **#49** added **`styleguide.html`** (tokens / components / state matrix / discrepancy audit).
- **#50** interaction change: **complete via a checkmark icon** in the hover action column (was tap-to-cycle), **edit by clicking the task text** (pencil removed; goes editable on mousedown so one click works), **removed the "now"/focused state**, solid action icons, weather icon **44→50px** (Figma node 17:78).

**⚠️ Release state — READ BEFORE MERGING ANYTHING:** latest published = **0.2.39**. Everything after it
is merged into `main` (~0.2.43) but **unreleased** by design — the user wants to review the batch first.
`AUTO_RELEASE_MAC=false` is the guard (merging won't publish). To cut the single release after review:
`gh variable set AUTO_RELEASE_MAC --body true` → `gh workflow run "Release Mac app"` → confirm `gh release list`.
Gotcha: `gh pr merge --squash` drops a `[skip release]` PR-title tag (uses the commit msg), so the **var**
is the real guard, not the tag. (Memory: `buddy-release-squash-gotcha`.)

**Not built yet — the design-token system** (designer-approved; visual spec in the styleguide's
"⚐ Proposals" section on the **unmerged** `feat/styleguide-proposals` branch; full spec in memory
`buddy-token-system-todo`): OKLCH hover `--red-hover: oklch(from var(--red) calc(l-.05) calc(c+.05) h)`
(darker *and* more saturated — a black veil goes muddy), type scale 16→15 / 13→14, icon weights
≤20px→1.8 / weather→1.4, and de-inlining every render-time `style="color:…"` into utility classes.
This is the next PR.

**Verified:** every PR via `__buddy.smokeTest()` + an lvl0/lvl1/lvl2 visual sweep; the single-click
edit confirmed with a real mouse click. **NOT verified:** none of the post-0.2.39 work has been in a
**native build or on device** — only the browser preview. The lone smokeTest "hit targets" failure is a
known headless artifact (30px hover icons under a parked Playwright mouse), not a regression.

## Session summary — 2026-06-26

Shipped a **critical click-blocking fix** as **0.2.38** (PR #42, merged → auto-release).

### The bug (regression introduced 2026-06-25 in `bef4a7d`, shipped in 0.2.37)
The Fade+Drift refactor changed the *closed* settings sheet from `translateY(100%)`
(fully off-screen) to `translateY(22px); opacity:0` (invisible, in place) but **forgot
`pointer-events:none`** — the same line it correctly added to `#drawer` and `#morning`.
Result: an invisible `z-20` `#settings` sheet blanketed the whole list panel (Card 2)
and **swallowed every click** — the Future/Done history toggle **and** task rows. So in
0.2.37 you couldn't complete tasks or switch to the Done view; the disc/gear/pin in the
header (Card 1) still worked because they sit outside the sheet. User reported it as
"my dones are gone" + "the toggle doesn't work."

### The fix (4 lines, `dist/index.html`)
- `pointer-events:none` on `.sheet[data-open="false"]` (normal **and** reduced-motion variants).
- History toggle buttons: `min-height:38px` (inline style — was ~22px) + `px-5`,
  `grid place-items-center`. NOTE: a brand-new arbitrary Tailwind class (`min-h-[38px]`)
  does **not** work here — this dist uses a **precompiled** Tailwind stylesheet, so only
  classes present at build time exist. Use inline style or existing utilities.

### Verified (browser, served `dist/` via Playwright real clicks)
- Real click on closed-sheet build **timed out** (blocked by `#settings`) → after fix it **lands**.
- Closed sheet computes `pointer-events:none`; toggle pill is 38px tall; realistic tap zone **15/15**.
- `smokeTest`: no new failures (the lone pre-existing hit-target flag fails identically on `main`,
  an artifact of running the audit via Playwright vs `pnpm ui:smoke`).

### Not verified / open
- **0.2.38 release**: was `in_progress` at wrap. Confirm it **published** (DMG + tarball + latest.json)
  and that installing it actually restores clicking in the running app.
- The 0.2.37 on-device items still pending (live weather fetch, 30pt top padding, Fade+Drift feel).

## Session summary — 2026-06-25

A long build session. Shipped **6 public releases** (0.2.32 → 0.2.37). The auto-release pipeline is now fully working end to end.

### Completed & shipped (all on `main`, released in 0.2.37)
- **Restart-to-fresh:** "Restart Buddy" stashes the current plan and shows a blank morning with a "Restore your last list" row.
- **Fade+Drift motion (app-wide):** unified show/hide style (fade + small drift + slight scale, ease-out, `--t-drift` = .48s) on the drawer, morning leave, settings/history sheets, and update banner. Micro-interactions (row add, Donezo, crossfade, confetti) left as short ease-out fades. Started as a morning→drawer handoff animation, then unified per user pick of "Fade + Drift".
- **Font → Geist** (self-hosted variable woff2, SIL OFL; Inter removed).
- **Weather date header** (per Figma): number left, weekday/month stacked, weather icon right, 32/26/32 spacing, baseline-aligned via `.tbt` (text-box-trim). Live weather: IP (ipwho.is) → Open-Meteo (no key) → 13-icon **Lucide outline** set (`WX_ICONS`/`wxKey`), day/night aware, cached 1h, fails silently. Applied to morning + drawer headers.
- **History:** store ~1 year (`pruneHistory`, RETENTION_DAYS=365), show a fixed **14-day** Done window for everyone (`HISTORY_DAYS=14`). Removed the per-user "days of history" slider.
- **Settings:** "Give Buddy room" pin label (was "Reserve space when pinned"); done-task count beside Export (`#exportCount`); Quit/Restart as matching pill buttons; removed the green auto "Update available" indicator AND the manual "Check for Updates" (the banner is the only update path); removed "Improve weather location" (see below).
- **Notch top padding:** window top inset `MENUBAR` const (currently **30pt**) so the drawer's top gap matches the bottom on notch Macs. Tuned by eye.
- **Release workflow protocol:** "ship it" → public signed release; "just land it" → `[skip release]` in the commit skips bump+release (added to `.github/workflows/version-bump.yml`).

### Verified this session
- `pnpm ui:smoke` passes (incl. the hit-target audit, now skips `pointer-events:none`/`opacity:0`).
- **v0.2.37 published** — signed, notarized, with DMG + `Buddy.app.tar.gz` + `latest.json` (version 0.2.37). The full auto-pipeline (version-bump → release-mac) works; `AUTO_RELEASE_MAC=true` and all 9 signing secrets present.
- The in-app updater works end to end (user updated across multiple releases).
- Browser-verified: header layout/baseline, weather-icon mapping (injected codes), settings layout, drawer drift states, export count, Done 14-day window.

### Not verified / open
- **Live weather fetch** (ipwho.is → Open-Meteo) only verified with *injected* weather codes — the real network fetch + correct local conditions need confirming in the running app. Fails silently if it doesn't work.
- **Native feel** of Fade+Drift and the **30pt top padding** are eyeball estimates — confirm on-device; both are one-token/number tweaks (`--t-drift`, `MENUBAR`).
- **Precise weather location** deferred: a Tauri/WKWebView app can't reach macOS location via `navigator.geolocation` (returns PERMISSION_DENIED with no prompt). Would need native CoreLocation (Rust) if revisited. IP-based already follows travel.

### Gotcha worth remembering
- **Apple notarization 403 "agreement missing/expired"** blocked two release builds. Apple periodically re-issues the Developer Program agreement; the account holder must re-accept at developer.apple.com/account, then re-run `gh workflow run release-mac.yml`. Not a code/credentials problem.


## Session summary — 2026-06-23

### Completed
- Investigated a real morning data-loss report: Buddy opened Tuesday, June 23 with an empty morning even though Monday, June 22 had six tasks.
- Confirmed the tasks were still present in `buddy-state.json` history and in `buddy-state.recovery.json`; the running old installed app was overwriting the repaired primary file with an empty same-day state.
- Repaired the user’s local Buddy data while Buddy was closed. Restored today’s list to:
  - Wimp Newsletter
  - Review icon builder
  - Experts page
  - Navigation
  - Musou Tshirts
  - Robin Site
- Updated `dist/index.html` recovery behavior:
  - different-day recovery merges preserve an older live list as history instead of dropping it
  - empty, unplanned mornings can auto-restore yesterday’s unfinished list
  - empty today views show a “Restore [weekday]’s list” row when unfinished history is available
- Fixed the red settings theme: the “Reserve space when pinned” switch now uses a deep Buddy red on the red panel instead of black.
- Removed the confusing backup app from `/Applications`: `Buddy-Old.app` was moved to Trash.
- Fixed hit targets and click alignment:
  - top chrome buttons now have 44×44 minimum hit targets
  - chrome SVGs and row action SVGs no longer steal pointer hit tests from their parent buttons
  - Skip, reserve switch, and dev restart controls now meet the same target standard
- Added a repeatable UI guardrail:
  - new script: `pnpm ui:smoke`
  - new file: `scripts/buddy-ui-smoke.spec.js`
  - Buddy’s internal `window.__buddy.smokeTest()` now includes a visible-control hit-target audit
- Added a later launch-page todo: use `https://joi.software/` as inspiration for Buddy’s launch page. Do not work on it now.
- Rebuilt and installed the local fixed app to `/Applications/Buddy.app`.

### Verified this session
- `pnpm ui:smoke` passed. This checks Buddy’s internal smoke test plus the new hit-target audit.
- Playwright recovery/smoke test passed during the data-loss fix.
- Playwright full sync test passed after the recovery merge change.
- `pnpm build` compiled and produced:
  - `/Users/whale/Projects/buddy/src-tauri/target/release/bundle/macos/Buddy.app`
  - `/Users/whale/Projects/buddy/src-tauri/target/release/bundle/dmg/Buddy_0.2.31_aarch64.dmg`
- `pnpm build` still exits non-zero at the updater signing step because `TAURI_SIGNING_PRIVATE_KEY` is not set in this shell. The app bundle itself was produced before that failure.
- Installed local app was relaunched and verified running from `/Applications/Buddy.app/Contents/MacOS/buddy`.
- Local state file still contained all six restored tasks after relaunch.

### Not verified / still needs release work
- Changes are not committed yet. Working tree intentionally contains edits to `dist/index.html`, `package.json`, `src-tauri/Cargo.lock`, `STATUS.md`, `HANDOFF.md`, and new `scripts/buddy-ui-smoke.spec.js`.
- No signed/notarized public release was cut. Installed local `/Applications/Buddy.app` is fixed for this machine only.
- Updater artifact signing is blocked locally by missing `TAURI_SIGNING_PRIVATE_KEY`.
- System Settings may still show a stale “Buddy-Old” Accessibility row until the user removes it with the minus button. `/Applications/Buddy-Old.app` is no longer present.

## Session summary — 2026-06-22

### Completed
- Investigated a report that Buddy “lost” the current task list after an update/restart.
- Confirmed the user’s data was not lost:
  - primary durable file: `~/Library/Application Support/fyi.whale.buddy/buddy-state.json`
  - WebKit localStorage cache also contained the same task list.
- Found installed `/Applications/Buddy.app` was still `0.2.21` while `main` had advanced to `0.2.29`, so release/update state may have been confusing.
- Added a stronger recovery layer in PR #33:
  - native app now keeps `buddy-state.recovery.json`
  - recovery file only updates when a save contains real task/delete information
  - boot now merges browser cache + primary state file + recovery state file
  - real deletes remain respected through tombstones/`erasedAt`
- Merged PR #33 into `main` and pulled the version-bump automation commit.

### Verified this session
- `cargo check` passed on the recovery change.
- Extracted app script passed `node --check`.
- PR #33 was mergeable and merged into `main`.
- Local `main` is clean and matches `origin/main` at `2127325`.

### Not verified / still needs owner or release work
- The recovery behavior has not been verified in a built `.app` by simulating an accidental empty-state overwrite.
- No new signed/notarized release was cut after PR #33, so installed users do not have the recovery-file safeguard yet.
- Installed `/Applications/Buddy.app` was observed as `0.2.21`; confirm after the next release/update that it actually advances.
- GitHub Actions/version bump ran, but release artifacts were not built or published in this session.
- Automatic release workflow has been added but is gated until GitHub signing secrets and `AUTO_RELEASE_MAC=true` are configured.

## Current implementation state

### Mac app
- Durable state file exists and is the primary source of truth:
  `~/Library/Application Support/fyi.whale.buddy/buddy-state.json`.
- New recovery file path after PR #33:
  `~/Library/Application Support/fyi.whale.buddy/buddy-state.recovery.json`.
- Auto-updater is wired to GitHub Releases via `RELEASE-UPDATER.md`.
- Released version is **`0.2.37`** (signed + notarized + published). Auto-release pipeline is live and verified.

### iOS companion
- Main now includes the iOS parity work from PR #32.
- Separate local branch `feat/sync-live` still exists and contains later sync/live work that is not on `main`.

### Sync
- The earlier sync architecture remains: client-side merge with a dumb compare-and-swap store.
- Local branch `feat/sync-live` should be reviewed before starting new sync work; it may contain unmerged live Supabase/iOS sync progress.

## Next recommended milestone

Confirm the 0.2.37 native polish on-device (Fade+Drift feel, 30pt top padding, real weather fetch). Tune the one token/number per item if needed and ship a follow-up. Then the app is in a solid resting state.

## Next likely work
1. **On-device confirm of 0.2.37:** does the weather icon show your real local conditions? Does the top gap match top/bottom? Does Fade+Drift feel right on each panel? Tune `MENUBAR` and `--t-drift` (in `dist/index.html`) if needed → ship.
2. **Workflow reminder:** say "ship it" for a public release, "just land it" for repo-only (`[skip release]`). Releases are fully automatic on merge to `main`.
3. Optional: decouple the Done view further or add an "always show everything" mode (currently fixed 14-day display, ~1yr storage).
4. Optional: precise weather location via native CoreLocation (Rust) — only if IP location proves wrong (e.g. on VPN).
5. Review local branch `feat/sync-live` before doing more sync work (unmerged live Supabase/iOS sync).
6. Later launch-page concept: `https://joi.software/` as inspiration ("The daily planner to keep distracted minds on track" — simple product landing, iOS CTA, calm timeline/to-do/habit story). Not now.

## Useful commands

```bash
cargo check --manifest-path src-tauri/Cargo.toml
pnpm ui:smoke
python3 - <<'PY'
from pathlib import Path
s=Path('dist/index.html').read_text()
Path('/tmp/buddy-app-script.js').write_text(s[s.index('<script>')+8:s.rindex('</script>')])
PY
node --check /tmp/buddy-app-script.js
```

For release steps, use `RELEASE-UPDATER.md`.
