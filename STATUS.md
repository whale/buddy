# Buddy — Status & Handoff

_Last updated: 2026-06-14. Branch: `fix/build-frontend-dist` (commit 46bbd2c, not yet merged)._

A macOS menu-bar focus app for ADHD: each morning pick your top three; a right-edge drawer holds them all day; mark one "now", check things off, glance at recent history. Repo: **github.com/whale/buddy** (private).

## ⏳ Current focus: first beta DMG (in progress, paused on restart)

We are building Buddy's first **signed + notarized universal DMG** so testers can download it from GitHub and run it with no scary warnings.

**Where we paused:** the build reached Apple's **notarization** step and was waiting on Apple when the owner restarted the Mac. The restart stops the local build, but everything heavy is cached, so resuming is quick.

**To resume (next session):** say "resume the Buddy build". It re-runs:
```
cd ~/Projects/buddy && source "$HOME/.cargo/env" && set -a && source .env && set +a && pnpm tauri build --target universal-apple-darwin --bundles dmg
```
(Stop any `tauri dev`/cargo first to free the build lock. Run in background.)

**After the DMG is produced** at `src-tauri/target/universal-apple-darwin/release/bundle/dmg/Buddy_<version>_universal.dmg`:
1. Verify: `xcrun stapler validate <dmg>` and `spctl -a -vvv -t install <dmg>` → must say **"Notarized Developer ID"**.
2. Open a PR for `fix/build-frontend-dist` and merge to `main` (branch-first rule).
3. Upload the DMG to a **private GitHub Release** (`gh release create`) → shareable tester link.

**Resolved this session:**
- `tauri build` refused `frontendDist: "../"` (it would bundle node_modules/src-tauri/target). Fixed by moving the web app into `dist/` and pointing `tauri.conf.json` there (commit 46bbd2c). Confirmed working — build now reaches signing.
- Codesign failed with `errSecInternalComponent` (background process couldn't reach the keychain). Fixed by the owner clicking **"Always Allow"** once on the keychain prompt — persists across restarts.

**Credentials:** `.env` (gitignored, local only) holds the 4 Apple vars — issuer ID, Key ID, the `.p8` key path, and the Developer ID signing identity. The actual values live only in `.env`; never print them in tracked files or commit them.

## How to run (dev)

**Web app (fastest to iterate):**
```
cd ~/Projects/buddy/dist && python3 -m http.server 4500   # open http://localhost:4500
```
(Note: the web app moved from the repo root into `dist/` this session.)

**Native Mac app (Tauri):**
```
cd ~/Projects/buddy && source "$HOME/.cargo/env" && pnpm tauri dev
```
To clear app data and see a fresh morning: quit, `rm -rf ~/Library/WebKit/buddy`, relaunch.

## What's shipped (merged to main before this session)

Edge-reveal hide/show on the right screen edge; macOS-correct soft drop shadow; Quit + version in Settings; calendar-icon history with Future/Past tabs, days-of-history setting, sleep-till-tomorrow and resume-from-yesterday; CSS-variable theming for the 5-text / 6-bg escalation states; live morning planner; compact morning sizing; "Report a bug" menu item (Buddy-only screenshot + logs → email); opt-in "Reserve space when pinned" (Accessibility window-nudging, off by default, skips system overlays); left-click opens the tray menu; auto version-bump GitHub Action.

## Not verified yet / deferred

- **The DMG itself** — not yet built/verified end-to-end (that's the resume task above).
- **On-device testing in the signed build:** reserve-space nudging, report-bug auto-attach in Apple Mail (needs the signed build), compact morning. Owner to test once the DMG exists.
- **Before a wider public release** (not needed for closed beta): bundle Tailwind locally + tighten CSP; friendly first-run Accessibility-permission screen.

## Key files

`dist/index.html` (whole web app), `dist/assets/` (parrot gifs + vendored html2canvas), `src-tauri/` (Tauri shell, signing config, entitlements), `RELEASE.md` + `BETA-SETUP.md` (distribution guides), `PLAN.md` (full spec), `README.md`, `README-MAC.md`.
