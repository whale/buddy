# Buddy — Status & Handoff

_Last updated: 2026-06-19. Branch: `feat/ios-companion` (clean). Latest **release**: v0.2.15 (users still on this — the durability fix is in `main` but NOT yet released). `main`: durability + bug-reports merged. **PR #26 OPEN** (iOS icon/schema/local-app/sync-step-1)._

Buddy is a **shipped, public, self-updating** macOS menu-bar focus app for ADHD.
Repo: **github.com/whale/buddy** (PUBLIC, MIT). Download: **github.com/whale/buddy/releases/latest**.

## 🧭 Session map — 2026-06-19 (read this first)

Four workstreams moved this session. State of each:

| Workstream | Where | Status |
|---|---|---|
| **Data durability** (file source-of-truth, granular load, single-instance, dev red-icon) | `main` (PR #23 ✅merged) | Done + verified on-device. **NOT yet in a release build** — users still run v0.2.15. |
| **Bug reports → private GitHub issue** (serverless) | `main` (PR #24 ✅merged) | Code merged + security-hardened. **DORMANT** until the 1-time deploy: do `BUG-REPORTS.md`, then set `BUG_ENDPOINT` in `dist/index.html` + ship a build. |
| **iOS companion — offline app** | `main` (PR #25 ✅merged: scaffold+README) **+ PR #26 OPEN** (icon, Supabase schema, full local app, sync-step-1) | Builds + runs (xcodebuild SUCCEEDED, rendered in Simulator). Full local parity. **Merge #26 to land it.** |
| **Mac⇄iOS sync** | PR #26 (step 1) + plan | Design done. **Step 1 (UUIDs) ✅.** Steps 2–6 NOT started — full build order in `IOS-COMPANION-PLAN.md`. |

⚠️ **Sync correctness:** an adversarial review killed the original whole-doc
last-write-wins design (silently loses data on any two-device day). The plan now
specifies a small **field-level merge** (UUIDs ✅ → per-item version + tombstones →
pure `merge()` → server merge-on-push). The `buddy_push` RPC currently in
`supabase/migrations/` is still the **interim LWW** version and MUST be replaced
with merge-on-push before sync is wired. Do not ship sync until steps 2–6 + the
loss-scenario tests pass.

🚧 **Sync needs a live DB to test:** Docker/OrbStack was off this session, so the
schema is written but **never applied/run**. Start OrbStack → `supabase start`, or
deploy a cloud project (`supabase link` + `db push`), before wiring push/pull.

## 🔒 Data durability — in review (PR #23, NOT yet merged/released)

Triggered by a real "my tasks vanished after restart" incident. Diagnosed from the
live on-disk stores: data wasn't truly deleted, but Buddy had several ways to lose
or strand it. Fix is committed on `fix/data-durability` → **github.com/whale/buddy/pull/23**.

- **Granular per-slice load** — a corrupt `today` can no longer wipe valid history.
- **Durable file mirror** `~/Library/Application Support/fyi.whale.buddy/buddy-state.json`
  (Tauri `save_state`/`load_state`, atomic temp+rename) is the **origin-independent
  source of truth**; localStorage is now just a cache. Boot keeps the **newest**
  (`savedAt`) of {localStorage, file} → survives a wiped/stale webview origin.
- **Rollover pre-fills the planner** with yesterday's unfinished tasks (commits
  synchronously); **"Add undone" hidden** (commented, easy to restore).
- **Demo seed only on a genuine first run.**
- **Single-instance guard** (`tauri-plugin-single-instance`) — 2nd launch focuses the
  existing window.
- **Dev builds are visually distinct** — red menu-bar icon + "Dev Buddy" header
  (gated on `cfg!(debug_assertions)` via a new `is_dev` command). Release unaffected.
- **Crisp Retina tray icon** (regenerated 88px; the crate forces 18pt → 22px upscaled = blurry).

**Verified ON-DEVICE:** wiped localStorage entirely, relaunched → tasks restored from
the file (`boot: file mirror is newest … recovered=true`). Single-instance blocks a
2nd launch. Red icon + "Dev Buddy" title confirmed by screenshot. Browser smoke test
8/8 + granular/rollover assertions pass. Rust builds clean.

**Not yet done:** PR #23 not merged → not in a release build yet. Layer-3 niceties
(cap history growth, gate debug `__buddy` hooks in release) deferred. See
`DATA-SAFETY-PLAN.md` and `IOS-COMPANION-PLAN.md` for the roadmap.

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

## Next likely work
1. **Merge PR #26** — lands the iOS app icon, Supabase schema, full offline iOS app, and
   sync-step-1 UUIDs (safe; local-only/inert).
2. **Sync steps 2–6** (the main remaining build) per the **Sync build order** in
   `IOS-COMPANION-PLAN.md`: local model (per-item version + tombstones + `erasedAt` +
   idempotent date-keyed rollover) → pure `merge()` (wire into Mac boot reconcile first)
   → server **merge-on-push** (replace the interim LWW RPC) + rate-limit → pull/push + QR
   pairing (scanner-pulls-first) → reproduce every loss scenario. **Start OrbStack /
   `supabase start` first** to test the schema live.
3. **Cut a release** so the durability fix reaches installed users (bump version in
   lockstep per `RELEASE-UPDATER.md`; v0.2.15 lacks the single-instance guard).
4. **Deploy bug reports** — follow `BUG-REPORTS.md`, set `BUG_ENDPOINT`, ship a build.
5. **iOS first TestFlight** — needs ASC env vars (`ASC_KEY_ID/ISSUER_ID/KEY_PATH`, reuse
   Belly's key) + the morning-screen decision (iOS currently skips it).
6. **Landing page** + **staple the DMG** + first-run hint — the older "share it widely" polish.

## How to run (dev)
```
cd dist && python3 -m http.server 4500     # web app → http://localhost:4500
pnpm tauri dev                             # native Mac app
```
Pre-build gate: `await window.__buddy.smokeTest()` must be `{ ok: true }`, plus a visual lvl0/lvl1/lvl2 red-state sweep (CLAUDE.md Rule 2).
