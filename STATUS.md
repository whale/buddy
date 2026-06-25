# Buddy — Status & Handoff

_Last updated: 2026-06-23. Current branch: `main`. Latest local commit: `8d227e7` (`chore: bump version [skip ci]`). Working tree has uncommitted session changes. Main app version: `0.2.31`. Public signed release status was not verified this session._

Buddy is a shipped, public, self-updating macOS menu-bar focus app for ADHD.
Repo: `github.com/whale/buddy`.


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
- `main` version is `0.2.31`; public signed release status was not verified in the 2026-06-23 session.

### iOS companion
- Main now includes the iOS parity work from PR #32.
- Separate local branch `feat/sync-live` still exists and contains later sync/live work that is not on `main`.

### Sync
- The earlier sync architecture remains: client-side merge with a dumb compare-and-swap store.
- Local branch `feat/sync-live` should be reviewed before starting new sync work; it may contain unmerged live Supabase/iOS sync progress.

## Next recommended milestone

Commit the 2026-06-23 local fixes, then cut and verify a signed macOS release that includes the recovery, restore, red-toggle, and hit-target guardrail changes.

Recommended release verification:
1. Build signed/notarized Buddy from `main`.
2. Seed `buddy-state.json` with a task list.
3. Force a stale/empty same-day primary/cache condition.
4. Relaunch the built app and confirm recovery restores the task list.
5. Publish release artifacts and verify `/Applications/Buddy.app` updates past `0.2.21`.

## Next likely work
1. Review and commit the 2026-06-23 working tree changes after confirming the live app feels right.
2. Cut the next signed Mac release from `main` (`0.2.31` or the next bumped version) using `RELEASE-UPDATER.md`.
3. Before each install/release, run `pnpm ui:smoke` to catch interaction and hit-target regressions.
4. Add GitHub release secrets and set `AUTO_RELEASE_MAC=true` so future main updates publish releases automatically.
5. Review local branch `feat/sync-live` before doing more sync work.
6. Continue QR pairing / user-facing sync setup after the recovery release is safely shipped.
7. Later launch-page concept: use `https://joi.software/` as inspiration for Buddy’s launch page. Current reference notes: Joi positions itself as “The daily planner to keep distracted minds on track,” with a simple product-focused landing page, iOS download CTA, Apple ecosystem framing, and a calm timeline/calendar/to-do/habit story. Do not work on this now.

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
