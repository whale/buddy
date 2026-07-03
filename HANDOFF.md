# Buddy — Next Session Handoff

_Last updated: 2026-07-02 (iOS visual-parity session)._

## ⚠️ Active branch right now: `feat/ios-sync-live` (Mac⇄iOS sync — in progress)

Off `fix/ios-visual-parity`. Building live sync. **P0 (backend + CAS SQL 7/7) and P1
(iOS live adapter, 3 live tests ran & passed) are DONE & verified.** Full plan + progress
+ resume commands: `ios/_review/SYNC-PLAN.md` (read the "PROGRESS — resume here" block first).
Next: P2 wire auto-sync into BuddyStore → P3 Settings opt-in → P4 Mac side → P5 round-trip.
Needs local Supabase running (`orb start && supabase start`). A **hosted** Supabase is only
needed later (P7) to sync a *physical* iPhone; everything through P5 verifies on localhost.
The visual-parity work (below) is its own branch/PR #61 — sync stacks on it, rebase if #61 changes.

---

## `fix/ios-visual-parity` (iOS visual work, PR #61 — draft)

This session rebuilt the **iPhone** UI to visually match the Mac drawer (it had drifted
badly — system font, single card, native iOS chrome). Branch is **committed + pushed**,
**no PR yet** (waiting on the user's review). All 37 iOS unit tests pass. The Mac app,
PR #60, and `main` are untouched.

- **Review it:** open `ios/_review/comparison.html` (Mac vs iPhone, every screen, side by side).
- **What's done:** Geist font bundled; TodayView (two Geist cards, chrome row, numeral-left
  date, clean rows, escalation lvl0/1/2); Settings + History rebuilt as custom Buddy sheets;
  MorningView restyled. Details in `ios/_review/PROGRESS.md` + memory `buddy-ios-visual-parity`.
- **Regenerate any shot:** build, install to sim, then
  `xcrun simctl launch booted fyi.whale.buddy -uiFixture <lvl0|lvl1|lvl2|empty|morning|history|settings>`
  → `xcrun simctl io booted screenshot out.png`.
- **Next decision for the user:** eyeball comparison.html → if good, open the PR. Known
  deltas (fixed "Donezo." vs rotating words; tap-to-complete vs swipe; static moon weather;
  focused/"now" state still in the store) are listed at the bottom of comparison.html.

---

## Start here (Mac app — resumes when back on `main`)

- Branch: `main`, clean.
- **Released = `0.3.1`** (Latest) — Future/Done/Skipped tabs + Future manual holding pen. Signed/notarized, published via manual `Release Mac app` dispatch. **Not yet on-device-verified** — confirm via Settings → Check for Updates (the in-app updater should offer 0.3.1).
- `AUTO_RELEASE_MAC` is **OFF** — but a manual `gh workflow run "Release Mac app"` publishes anyway (a `workflow_dispatch` bypasses the OFF gate and builds+publishes whatever version is on `main`). No need to flip the var. Note: the auto-bump bot **+1's the patch on every merge to `main`**, so set the version expecting the bump (or add `[skip release]` to freeze it).
- **Open work:** the design-token / de-inline-styles follow-up (memory `buddy-token-system-todo`).
- Also unmerged: `feat/styleguide-proposals` (styleguide Proposals/discrepancy spec) — merge or drop.
- **First alpha tester:** onboarding is just "send the DMG link" — see the STATUS.md "Alpha-tester onboarding" note. No feedback tooling built yet (fine for n=1).

## Next 3–5 tasks

1. **On-device verify 0.3.1** — Settings → Check for Updates → install → confirm the three tabs (Future/Done/Skipped) and the Future holding pen (+/×/click-edit) work in the real app. Much of this session was browser-verified only.
2. **Send the first alpha tester the DMG link** (`…/releases/download/v0.3.1/Buddy_0.3.1_universal.dmg`) — see STATUS.md onboarding note. If it grows past one tester, add a lightweight feedback loop (GitHub issue template or a form).
3. **Build the design-token system** as the next PR (branch off `main`). Spec: memory `buddy-token-system-todo` + the styleguide's "⚐ Proposals" section (on **unmerged** `feat/styleguide-proposals`). OKLCH hover (`--red-hover: oklch(from var(--red) calc(l-.05) calc(c+.05) h)`), type scale 16→15 / 13→14, icon weights ≤20→1.8 / weather 1.4, de-inline all `style="color:…"`. Verify all three colour states.
4. **Decide on `feat/styleguide-proposals`** — merge it or fold its content into task 3's PR.
5. **Prune stale local branches** (`feat/sync-*`, `worktree-agent-*`, `feat/styleguide`, `docs/session-wrap-*`, and this `docs/wrap-0.3.1-tabs` after merge).

## What just happened (2026-06-30, later)

Shipped **0.3.1** (PR #58): split the history drawer into **three tabs — Future · Done · Skipped**,
and reshaped **Future into a manual holding pen**. The Done tab had been conflating completed *and*
skipped past tasks; now Done = completed only, Skipped = past undone (each with a **+** to add back to
today), Future = a backlog you pull from by hand (no auto-return; **+** add, **×** remove, click-to-edit).
Every **+** respects `HARD_CAP` (hidden on full-red). Verified: `smokeTest` **39/39**, visual sweep at
lvl0/1/2, click-to-edit. Released via manual `Release Mac app` dispatch (auto-bump made it 0.3.1, not
0.3.0). Then answered "how do I get an alpha tester" — the answer is basically *send the DMG link*
(signed+notarized+public repo+auto-updater = zero extra setup; needs macOS 13+).

## What just happened (2026-06-30)

Shipped **0.2.47** (PR #55): the **full-screen-Spaces fix** + a **reliable updater**. The user was
stranded on 0.2.39 and saw morning "flash then hide behind other windows" with a dead tray Show/Hide.
After **two wrong guesses** (z-order/focus, released as 0.2.46), inspecting the live window
(`CGWindowList` → already floating layer 5) revealed the real cause: a floating window can't draw over a
**native full-screen** app without `collectionBehavior |= CanJoinAllSpaces | FullScreenAuxiliary`
(set at launch via `objc2-app-kit`; verified == 257). The reason fixes never *arrived*: the updater
checked **once** and **failed silently** — now checks at launch + every 3h + on focus, and logs
failures. Had to install the signed build **directly** once (the updater couldn't deliver its own fix).
Verified on-device: `spctl` → notarized, running 0.2.47. Lesson (in `JOURNAL.md`): inspect live runtime
state before theorizing a fix.

## What just happened (2026-06-26 evening)

Shipped **0.2.39** (PR #44) — the **overnight task-loss fix** (Restart stashed the list in RAM only;
3 backup layers had holes; 6 safety-only fixes; recovered the user's 4 lost tasks from the `.bak`).
Then merged a **batch of UX work, intentionally unreleased** (`AUTO_RELEASE_MAC` off): hover fix +
weather stroke (#45), Done-tab restore-from-skipped + drawer-restore removed (#46), Done tab
one-week + Load more (#47), 25 rotating done-words (#48), `styleguide.html` (#49), and the big
**interaction change** (#50): complete via a **checkmark icon**, **edit by clicking the text**, the
**"now"/focused state removed**, solid icons, weather icon 50px. Full detail + the locked token-system
spec in STATUS.md (2026-06-26 evening entry). Everything browser-verified only; not yet in a native build.

## What just happened (2026-06-26)

Fixed a **critical regression** shipped in 0.2.37: an invisible *closed* Settings sheet
(`opacity:0`, no `pointer-events:none`) was covering the whole list panel and eating every
click — the Future/Done toggle AND task rows. Plus the toggle buttons were only ~22px tall.
Fix = `pointer-events:none` on the closed sheet + 38px toggle buttons (`dist/index.html`,
4 lines). Verified via Playwright real clicks against served `dist/`. Shipped as 0.2.38.
Full detail in STATUS.md (2026-06-26 entry). Key gotcha learned: **new arbitrary Tailwind
classes don't work in this dist** (precompiled stylesheet) — use inline styles / existing utilities.

## What just happened (2026-06-25)

A large feature/polish session — shipped 0.2.32 → **0.2.37**. See STATUS.md for the full list. Highlights:

- **Restart-to-fresh** ("Restore your last list"), **Fade+Drift** motion app-wide (`--t-drift`), **Geist** font, **weather date header** (IP → Open-Meteo → Lucide icons), **history** (store ~1yr / show fixed 14 days, slider removed), Settings cleanup ("Give Buddy room" pin label, Export count, Quit/Restart pills, removed Check-for-Updates), **notch top-padding** fix (`MENUBAR` const).
- **Release pipeline proven:** `AUTO_RELEASE_MAC=true` + all 9 signing secrets present; merge-to-main auto-publishes. Workflow protocol: "ship it" = release, "just land it" = `[skip release]`.
- **Apple gotcha:** notarization 403 "agreement missing/expired" blocked a build — account holder re-accepted the Developer Program agreement at developer.apple.com/account, then re-ran the workflow. Not a code problem.

## Needs on-device confirmation (the only open items)

These are eyeball/feel estimates verified only in the browser — confirm in the running 0.2.37 app, each a one-token tweak:

- **Live weather:** does the icon show your *actual* local conditions? (verified only with injected codes)
- **Top padding:** `MENUBAR=30` in `dist/index.html` — does the top gap match the bottom?
- **Fade+Drift feel:** `--t-drift` (.48s) — right amount of drift on each panel?

## Verified commands from this session

```bash
pnpm ui:smoke   # passes (internal smoke + hit-target audit)
```

Release pipeline (GitHub Actions) verified end to end: version-bump → release-mac → published v0.2.37 with DMG + Buddy.app.tar.gz + latest.json.

## User-facing review instructions (for 0.2.37)

1. Quit Buddy from its Settings, reopen — the update banner appears; click **Install**.
2. Open the calendar/history → **Done**: you should see ~2 weeks of completed tasks (not just 2 days).
3. Open/close the **drawer**, hit **Buddy!/Skip** in the morning, open **Settings** — all should Fade+Drift (calm fade + slight drift).
4. Check the date header **weather icon** — does it match your real local conditions?
5. Check the **top gap** above the first panel matches the gap below the last one.
6. Settings: confirm **"Give Buddy room"**, **Export · <count>**, **Quit/Restart** pills, and no "Check for Updates".

## Next 3–5 tasks

1. **Confirm 0.2.38 published and works on-device** — install it, verify the Future/Done toggle switches AND that completing tasks works again (both were broken in 0.2.37).
2. Get on-device feedback on the 0.2.37 items still pending (weather, top padding, Fade+Drift feel). Tune `MENUBAR` and `--t-drift` in `dist/index.html` if needed, then "ship it".
3. Confirm the real weather fetch works in the app (only injected-code tested).
4. **iOS Buddy** — SwiftUI app + sync engine are built & unit-tested (`ios/`); the unbuilt frontier is live network wiring (Supabase), QR pairing UI (render + camera scan), and one real two-device round-trip. See `IOS-COMPANION-PLAN.md` "Sync build order" step 5.
5. Run `pnpm ui:smoke` before every change (it's the gate). When testing click/hit-target behavior, serve `dist/` and use **real** clicks (Playwright `browser_click`), not `.click()` — only real clicks catch pointer-events overlay bugs like #42.

## Blockers / cautions

- Do not edit `AGENTS.md` or `CLAUDE.md`; they are managed elsewhere.
- Do not commit `.env`, private exports, app data files, or generated build artifacts.
- **Releases are automatic** on merge to `main` (`AUTO_RELEASE_MAC=true`). To land code WITHOUT a release, put `[skip release]` in the commit message.
- If a release fails at notarization with a 403 "agreement" error, the account holder must re-accept Apple's Developer Program agreement, then re-run `gh workflow run release-mac.yml`.
- Local `pnpm build` still fails at updater signing (no `TAURI_SIGNING_PRIVATE_KEY` locally) — that's expected; CI does the signed build.
