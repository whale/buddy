# Buddy — Next Session Handoff

_Last updated: 2026-06-26._

## Start here

- Branch: `main` (clean, in sync with `origin/main`).
- Latest commit: merge of **PR #42** (toggle click fix).
- Released app version: **`0.2.38`** — ⚠️ auto-release was **building** at wrap. First thing next session: confirm it published (`gh release view`) and that installing it restores clicking.
- Working tree is clean. The auto-release pipeline is live: merging to `main` cuts a signed release automatically.

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
