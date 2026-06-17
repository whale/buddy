# Buddy — Status & Handoff

_Last updated: 2026-06-16. Branch: `main` (clean). Latest release: **v0.2.15**. main version: 0.2.17._

Buddy is a **shipped, public, self-updating** macOS menu-bar focus app for ADHD.
Repo: **github.com/whale/buddy** (PUBLIC, MIT). Download: **github.com/whale/buddy/releases/latest**.

## ✅ What's live (all shipped this session)

- **Native Mac app** — Developer-ID signed (Wimp Decaf Coffee Company Inc. `9QDAAYWU9X`) + notarized + **universal** (arm64 + x86_64), macOS 13+.
- **Auto-updater** — banner auto-checks on launch; Settings → Check for Updates; updates pull from GitHub Releases via a `latest.json` manifest. Update signing key at `~/.tauri/buddy-updater.key` (private — never commit).
- **Offline** — Tailwind + Inter bundled locally (no CDN).
- **"Donezo" completed-task flow** — complete → confetti → ~2s savor → the row **glides (FLIP) to the top** as a bold **"Donezo."** row; also files under **Calendar → Done → Today**; hover **↩** to restore (capped at 6 active). Done items don't count toward the red escalation.
- **Red escalation** — 5 active = text red (lvl1), 6 = whole drawer red (lvl2). Donezo/done text uses the adaptive `--ink`/`--ink-dim` tokens so it stays legible on red.
- **Tray menu** — Show/Hide · Settings… · Report a bug · Quit.
- **Docs** — tester-facing `README.md`, `CLAUDE.md` (design + verify-every-build rules), `RELEASE-UPDATER.md` (build/sign/notarize/publish runbook).
- **Smoke test** — `window.__buddy.smokeTest()` (8 core checks incl. red-state legibility). **Required before every build** (CLAUDE.md Rule 2).

## Verified this session
- Auto-updater end-to-end (0.2.11 → … → 0.2.15 via the in-app updater).
- Donezo flow, undo, red recalc, sort-to-top, calendar, offline styling, lvl0/lvl1/lvl2 legibility — via browser smoke test + screenshots.
- v0.2.15 published, notarization **Accepted**, repo public.

## ⚠️ Not verified — needs the owner on-device
- **White-seam flash** on edge reveal — attempted fix (resize window before sliding the drawer). If still flashing, escalate to the deeper fix: keep the window full-width and make it click-through (`setIgnoreCursorEvents`) when hidden.
- **Tray → Settings…** opening the drawer + settings sheet.

## Known quirks
- `main` version (0.2.17) drifts **ahead** of the latest release (v0.2.15) — the auto-bump GitHub Action fires on every merge, including docs. The next build from main = whatever main's version is.
- The **DMG container isn't stapled** (the `.app` inside is). Fine for online installs; staple before relying on offline first-launch.
- Apple's **timestamp service** had a ~1.5h outage this session → 6 consecutive `codesign` failures ("timestamp service is not available"). If it recurs, it's external — just retry later.

## Next likely work (the "share it widely" polish)
1. **Landing page** (GitHub Pages): hero + screenshots + a big Download button — the designer-shareable face.
2. **Staple the DMG** for offline first-launch + a **stable "always-latest" download** asset name (current DMG name is versioned).
3. **Friendly first-run hint** (it's a menu-bar app — where it went) + confirm the white-seam + tray Settings on-device.
4. Optional delight: more parrot variants / a bigger flourish when all three are done.

## How to run (dev)
```
cd dist && python3 -m http.server 4500     # web app → http://localhost:4500
pnpm tauri dev                             # native Mac app
```
Pre-build gate: `await window.__buddy.smokeTest()` must be `{ ok: true }`, plus a visual lvl0/lvl1/lvl2 red-state sweep (CLAUDE.md Rule 2).
