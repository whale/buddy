# Buddy — Status & Handoff

_Last updated: 2026-07-08. Branch `main`. Latest **released Mac** version: **`0.3.17`** (cut LOCALLY — `pnpm tauri build` + `gh release create`, `.env` creds). iOS is on **TestFlight `0.1.0 (13)`** (`cd ios && set -a && source ../.env && set +a && fastlane beta`). `AUTO_RELEASE_MAC` stays **OFF**. **🔴 Mac⇄iPhone sync is UNSOLVED — "Sent to today!" reverts and today items get OVERWRITTEN (data loss). Do this first next session.** See the 2026-07-08 summary below._

## Session summary — 2026-07-08 — morning-window rebuild, sync convergence attempt (STILL BROKEN), many releases

Very long session, Mac `0.3.4 → 0.3.17` + iOS TestFlight `0.1.0 (12)→(13)`. Every fix was verified where possible by running the app (`pnpm tauri dev` + `screencapture`); AppleScript keystrokes/Quartz are blocked in this harness, so tiling/drag and cross-device sync need the USER to confirm.

**Shipped + verified (high confidence):**
- **Morning is a real window** (0.3.12): decorated, resizable, shadow, min-size 432×600, on the SAME transparent drawer window via objc2 (`set_morning_mode`/`morning_window_chrome`). See memory `buddy-morning-real-window`.
- **Morning goes behind other apps** (0.3.13): `setLevel(0)` for morning, `3` for drawer (`set_always_on_top(false)` doesn't reset the level).
- **Morning opens full-screen + is tileable** (0.3.17): retired the buggy geometry-memory (its save raced the native re-chrome → off-screen/tiny windows); strip `CanJoinAllSpaces|FullScreenAuxiliary` during morning so Rectangle/Magnet/green-button treat it as normal (`collectionBehavior=Default`). Verified: 3456×2174 full frame + behaviour=0.
- **App icon** = proper macOS squircle (0.3.10), regenerated from `ios/.../icon-1024.png` via `pnpm tauri icon` (may need a Finder icon-cache clear to SEE it). Memory `buddy-native-only-visual-bugs`.
- **⌘⌥⌃M** always brings morning forward (global shortcut raises the window first) (0.3.14).
- **Updater banner** now reveals the drawer so it's visible (0.3.15) — but "verified" was overstated (it was already visible with the drawer open; no manual "Check for Updates" button exists). Memory `buddy-updater-banner-in-drawer`.
- **"Sent to today!" on Mac** (0.3.11) — verified in-browser.

**🔴 STILL BROKEN — sync convergence (do FIRST next session):**
- On Mac 0.3.17 + iPhone 13 (both have the parity code), sending a Future item to today **flashes "Sent to today!" then reverts**, AND the today items already there get **OVERWRITTEN / lost — DATA LOSS.** Slice 1 (align iPhone model + order-independent content-key, 0.3.16) was INSUFFICIENT exactly as the adversarial review warned: the merge is still **non-deterministic** (always-local-primary via per-pass `savedAt`; array-order/clamp survivor divergence). **Fix = the deterministic/symmetric merge (Slice 2) on BOTH platforms + unknown-field pass-through.** Full detail in memory `buddy-sync-convergence`.

**Other open Buddy issues reported 2026-07-08:**
- **Future items editable but broken** — clicking a Future row's text makes it contentEditable but you can't edit; user wants Future rows NOT editable. Remove the `mousedown→contentEditable` + blur handler in `renderFuture` (`dist/index.html` ~1977).
- **Future tab +/× icons right-aligned wrong** — should line up with the history panel's `×` close button (top-right gutter). Fix the `pr-[72px]`/absolute-right offsets in `renderFuture`/`buildSentFutureRow`.

**Deferred (deliberate):**
- **Two-window split for morning** — the REAL architecture fix (dedicated opaque decorated window; drawer stays its own). Ends the morning-window regression treadmill + gives reliable frame memory (macOS autosave). Adversarial-reviewed, ranked plan in memory `buddy-morning-real-window` context / the review transcript.
- **Sync Slice 2** (deterministic merge + unknown-field pass-through) — also the version-skew-safety the user wants (ship Mac/iPhone on different versions).
- **iPhone drops `doneWord` + `historyDays` on sync** (pre-existing minor data loss).

**Next session:** (1) FIX sync — Slice 2 deterministic merge (the revert + overwrite/data-loss); (2) remove Future-item editability + fix +/× alignment; (3) then the two-window morning split.

---


## Session summary — 2026-07-05 — merge cap+dedupe fix, sync-UI tweak, 0.3.3 shipped via CI

- **Merge cap + dedupe fix (the known bug).** Cross-device merge unioned both devices' active lists and never re-clamped, so Mac(6)+iPhone(new) → 8 rows with same-title dupes (seen live: two "Check on Anthropic bill"). New `clampActiveItems()` runs after every same-day merge on **both** platforms (`dist/index.html` + `ios/.../BuddyMerge.swift`): keep all done items, drop same-title active dupes (newer device wins), cap active at `HARD_CAP`. Deterministic → devices converge, no ping-pong. Tests: Mac `mergeTest` **18/18** (+3), iOS `BuddyTests` **51/51** (+2).
- **Sync-settings tweak.** "Synced HH:MM" moved to the right of Unlink/Resync, one type step down (15→14px). Stays legible on the lvl2 red sheet via the existing `.lvl2 #settings [class*="text-black"]` override.
- **Shipped as Mac 0.3.3 (via CI).** `feat/ios-sync-live` (the whole iOS companion + live sync, 42 commits) merged to main (PR #62, squash) → bump bot → **`gh workflow run "Release Mac app"`** built + published v0.3.3 with DMG + `Buddy.app.tar.gz` + `latest.json`; `releases/latest` resolves to v0.3.3. **Correction to prior belief:** CI *can* cut the signed release from main via manual dispatch — local notarization only needed for code not yet on main (like 0.3.2). See memory `buddy-0-3-2-release`.
- **Still open:** iPhone TestFlight distribution to the 2 friends (public link needs Apple beta review — user will do later). Confirm 0.3.3 on-device.

---


## Session summary — 2026-07-04 — Mac⇄iOS polish, staged sync UI, adaptive row fitting

Long session refining the synced Mac + iPhone apps against live testing. Branch `feat/ios-sync-live`.

**Shipped / done + verified:**
- **Mac 0.3.2 released** (signed+notarized, local build from the branch): Done-page **jitter fix** (poll no longer re-renders on no-change), **grey day headers** (not chrome→no red at lvl1), **Skipped tab removed** (Future · Done), **staged sync UI** (setup → pairing/QR → linked with **Unlink / Resync**; Resync mints a fresh syncKey = clean bucket), **pairing-QR redraws** on every Settings open.
- **iOS through TestFlight `0.1.0 (11)`**: sync-settings + date-baseline alignment (killed a stray `+12` hack), one 32pt gutter everywhere (close ✕ / weather / row icons), Future `+`/`×` always shown, Done-tab **revert** icon, **rollover carries all 6** (was 5), Skipped removed, **tap-to-edit focus fix** (deferred focus — kept text + cursor lands), bottom bar hides while editing.
- **Adaptive row fitting — one engine both platforms** (`RowFit` iOS, `fitWrap` Mac): largest uniform font where every row's real wrapped text fits → compress padding then font → floor (Mac 15 / iOS main 16 / morning 22→16) → scroll only as last resort; clip-safe by construction. **Fixed the iOS morning scroll** (was a ScrollView + fixed 120pt rows). Verified 6 multi-line tasks fit on Mac drawer, iOS main, iOS morning.
- **Tests:** iOS **49/49**, Mac browser smoke **35/35**.

**KNOWN BUG (unfixed — do first next session):** the **sync merge can exceed the 6-task cap and creates duplicates**. The `HARD_CAP` is only enforced on manual Add; `mergeWire`/`mergeHistory` union both devices' active lists and never re-clamp, so Mac(6)+iPhone(different) → 8 rows with dup titles (seen live: two "Check on Anthropic bill"). **Fix:** after a merge, clamp active list to 6 + dedupe by title. Contained change in the merge logic (dist `mergeWire` + iOS `BuddySync`), NOT the fit code.

**Also parked:** installed-app vs dev-build **localStorage split** — pairing/config lives per-origin (`WebKit/buddy` dev vs `WebKit/fyi.whale.buddy` installed), so updating the installed app showed "Off" until re-paired (backend URL/key are in `.supabase-buddy.secret` / `SYNC-HANDOFF.md`). Not a bug, but worth a note in onboarding.

**Next session:** (1) fix the merge cap+dedupe bug; (2) cut **Mac 0.3.3** so the installed app gets adaptive fit; (3) confirm TestFlight `0.1.0 (11)` feels right on the real phone.

---

_Historical: 2026-06-30. Branch `main`. Released **`0.3.1`** — history split into three tabs (Future · Done · Skipped) + Future turned into a manual holding pen. Signed/notarized, published via a manual `Release Mac app` dispatch (the in-app updater delivers it). `AUTO_RELEASE_MAC` stays **OFF** — a manual `gh workflow run "Release Mac app"` publishes anyway (workflow_dispatch bypasses the gate); no need to flip the var. Open work: the de-inline-styles / token-system follow-up (memory `buddy-token-system-todo`)._

Buddy is a shipped, public, self-updating macOS menu-bar focus app for ADHD.
Repo: `github.com/whale/buddy`.

## Session summary — 2026-07-02 — iOS visual parity (branch `fix/ios-visual-parity`, pushed, no PR)

Rebuilt the **iPhone** app UI to match the Mac drawer's design language (it had drifted:
system font, one card, native iOS nav/list/form chrome). Bundled **Geist** (static OTFs) +
a `Font.geist()` helper; rebuilt **TodayView** as two floating Geist cards (chrome row +
numeral-left date block; Donezo-on-top / active / Add rows; clean text rows with
tap=complete, long-press=edit/sleep/remove; escalation lvl0/1/2 via theme tokens); rebuilt
**Settings** and **History** as custom Buddy sheets (no native Form/List — the 👍🏼…🦜 slider,
the [Future|Done|Skipped] segmented history); restyled **MorningView**. Added store methods
`restoreHistoryTask` / `wakeDeferredTask`. Added a DEBUG `-uiFixture` screenshot harness for
deterministic captures. **All 37 iOS unit tests pass.** Review artifact:
`ios/_review/comparison.html`. Latest commit on the branch: `62328c4`. **Not merged; no PR.**
Known deltas + follow-ups are listed in comparison.html and `ios/_review/PROGRESS.md`.
## Session summary — 2026-07-01 — done-word shuffle bag (PR #60, open, not released)

**The bug (tester report).** A tester completed several tasks and the celebration labels (Donezo!, Ticked Off!, …) came out patterned, not random — Donezo / Ticked Off / Donezo / Ticked Off.

**Root cause.** The done word was derived from a **hash of the task's `id`**. For sequential ids — history rows (`h-DATE-0, -1, -2`) and the `n1/n2` fallback — the hash marched straight down the 25-word list, so neighbouring completions got neighbouring words. (Random-UUID ids actually spread fine; the bug only bit when ids were sequential.)

**The fix (PR #60, branch `fix/done-word-shuffle`).** Replaced id-hashing with a **shuffle bag**: every word is handed out once before any repeat, then the bag refills and reshuffles. The word is picked **once at completion** and stored on the item (`it.doneWord`) → genuinely spread out AND stable across re-renders. Persist the word per-item + the bag; survives sync (items pass through `mergeItems` whole). **Backfill at boot** heals already-completed tasks so an existing list re-shuffles immediately. Legacy hash kept only as a fallback for past-day history rows with no stored word. All in `dist/index.html`.

**Verified (browser, port 8899).** `smokeTest` — all completion + done-word assertions pass; the lone failure ("hit targets") fails identically on the **unmodified baseline** (headless hover-button quirk, not this change — confirmed by stashing the edits and re-running). Shuffle bag: 55 consecutive completions → first 25 all distinct, next 25 all distinct, order scrambled. lvl2 red state screenshotted — 4 done rows, words varied and legible in light-on-red (no hardcoded-dark regression). **Not on-device-verified** (browser only).

**Not released.** `AUTO_RELEASE_MAC` stays OFF; PR #60 is open, awaiting merge into the next batched release.

## Session summary — 2026-06-30 (later) — Future/Done/Skipped tabs + Future holding pen (shipped 0.3.1)

**The problem.** The **Done** tab showed both completed *and* skipped past tasks (each past day's `done:true` *and* `done:false` items), so skipped work polluted the "done" list — no clean view of what was actually finished.

**The change (PR #58, released 0.3.1).**
- **Three history tabs** — `Future · Done · Skipped` (was `Future · Done`). `renderPast` now filters to `done:true` only; new `renderSkipped` renders past `done:false` tasks; shared `histLoadMore()` helper. Third segment added to the tab pill (`px-5`→`px-4` so three fit).
- **Future is now a manual holding pen.** Removed the `wakeDeferred()` auto-return path entirely (the call in `rolloverAndCarry` + the function). Parked tasks no longer come back on rollover — pulled in with **+**, removed with **×**, edited by clicking the text (mousedown→contenteditable, empty deletes), mirroring the live list. Flat list, newest-parked on top (dropped the now-meaningless "Tomorrow/Monday" wake-date grouping). Added `addDeferredToToday()`.
- **Cap rule everywhere:** every **+** (Future *and* Skipped) hides at `HARD_CAP` (6 active / full red), so a day can't overflow.
- Renamed the list-row **"Sleep till tomorrow" → "Move to Future"**; removed dead `EDIT_SM` icon; `deleteDeferred` now persists.

**Verified.** Browser `smokeTest` **39/39** (updated for the new model — old "rollover wakes deferred" assertion became "holding pen: parked tasks do NOT auto-return"; added Done-vs-Skipped separation + Future-`+` assertions). Full visual sweep of all three tabs at **lvl0 / lvl1 / lvl2** — all adaptive-token legible, `+` correctly hidden on full-red. Click-to-edit on Future verified (editable-on-click, save-on-blur, empty-deletes). Release **v0.3.1** published with DMG + `Buddy.app.tar.gz` + `latest.json`; workflow succeeded. **Note:** the auto-bump bot ticked `0.3.0` → **0.3.1** on merge (it always +1's the patch), so the feature shipped as 0.3.1.

**Alpha-tester onboarding (asked at end of session).** Buddy is already distributable to a tester with **zero extra setup** — signed + notarized (opens cleanly on other Macs, no Gatekeeper block) and the repo is public with a working auto-updater. To onboard one tester: (1) send the direct DMG link `https://github.com/whale/buddy/releases/download/v0.3.1/Buddy_0.3.1_universal.dmg`; (2) tell them it's a menu-bar + right-edge app (so they know where it went); (3) "just text me" is a fine feedback loop for n=1. Requirement: **macOS 13 (Ventura)+**. First run may show a one-time "downloaded from the Internet — Open?" dialog (normal; notarized, so no hard block).

## Session summary — 2026-06-30 — full-screen-Spaces fix + reliable updater (shipped 0.2.47, on-device verified)

**The bug.** User was stranded on `0.2.39` (no update banner), and on launch Buddy would "flash up
then hide behind other windows," with the tray "Show / Hide" doing nothing. They work with apps in
**native full-screen**.

**Two wrong guesses first (the lesson).** Assumed z-order / focus loss; shipped `set_focus` +
`alwaysOnTop` juggling (released as 0.2.46) — wrong premise, didn't help. Turning point: *ran the real
app and inspected the live window* (`CGWindowListCopyWindowInfo` via a throwaway Swift script) — the
window was already at floating **layer 5**, so it could never be "behind" a normal window. **Inspect
live runtime state before designing a fix.**

**Real root cause + fix (0.2.47, PR #55).** The window is `alwaysOnTop:true` by config, but a floating
window **can't draw over an app in native full-screen mode** unless its `NSWindow.collectionBehavior`
opts in. Fix: `collectionBehavior |= CanJoinAllSpaces | FullScreenAuxiliary` at launch
(`allow_over_fullscreen` in `src-tauri/src/lib.rs`, via new `objc2` / `objc2-app-kit` deps). Verified
live: behaviour == **257**. Reverted the mis-aimed `nativeFit` always-on-top block from 0.2.46.

**Second bug, exposed by the first — the updater stranding (same PR).** The in-app updater checked
**once** ~2.5s after launch and **swallowed errors silently** → one miss = stuck a full version behind
with no signal (how 0.2.39 missed 0.2.46). Now checks at launch, **every 3h, and on window focus**
(throttled 1/min, stops once a banner shows), and `trace()`s failures into the bug-report logs.

**Delivery gotcha.** The updater was itself the broken link, so it couldn't deliver its own fix — had
to install the signed build **directly** (drag the DMG) once. After 0.2.47, normal in-app updates resume.

**Verified:** full-screen behaviour confirmed by the user in their real setup; `over-fullscreen
behaviour set: NSWindowCollectionBehavior(257)` in the launch log; browser `smokeTest` **35/35**;
installed `0.2.47` is **signed + notarized** (`spctl` → "accepted, Notarized Developer ID") and running
on-device. Full writeup in `JOURNAL.md` (PR #56, `[skip release]`). **Releases 0.2.46 & 0.2.47 both
published; `AUTO_RELEASE_MAC` flipped back OFF.**

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
