# Buddy — Status & Handoff

_Last updated: 2026-06-22. Current branch: `main`. Latest local/remote commit: `2127325` (`chore: bump version [skip ci]`). Main app version: `0.2.29`. Latest shipped public release still appears to be v0.2.21 unless a new release is cut._

Buddy is a shipped, public, self-updating macOS menu-bar focus app for ADHD.
Repo: `github.com/whale/buddy`.

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
- `main` version is `0.2.29`; latest confirmed shipped release in docs is v0.2.21.

### iOS companion
- Main now includes the iOS parity work from PR #32.
- Separate local branch `feat/sync-live` still exists and contains later sync/live work that is not on `main`.

### Sync
- The earlier sync architecture remains: client-side merge with a dumb compare-and-swap store.
- Local branch `feat/sync-live` should be reviewed before starting new sync work; it may contain unmerged live Supabase/iOS sync progress.

## Next recommended milestone

Cut and verify a new macOS release that includes PR #33, then run an on-device recovery test before broadly trusting the update path.

Recommended release verification:
1. Build signed/notarized Buddy from `main`.
2. Seed `buddy-state.json` with a task list.
3. Force a stale/empty same-day primary/cache condition.
4. Relaunch the built app and confirm recovery restores the task list.
5. Publish release artifacts and verify `/Applications/Buddy.app` updates past `0.2.21`.

## Next likely work
1. Cut the next Mac release from `main` (`0.2.29` or the next bumped version) using `RELEASE-UPDATER.md`.
2. On-device test the new recovery-file behavior in the built app.
3. Review local branch `feat/sync-live` and decide whether to PR sync/live work or rebase/split it.
4. Add GitHub release secrets and set `AUTO_RELEASE_MAC=true` so future main updates publish releases automatically.
5. Continue QR pairing / user-facing sync setup after the recovery release is safely shipped.
6. Deploy dormant bug-report intake if needed (`BUG-REPORTS.md`).

## Useful commands

```bash
cargo check --manifest-path src-tauri/Cargo.toml
python3 - <<'PY'
from pathlib import Path
s=Path('dist/index.html').read_text()
Path('/tmp/buddy-app-script.js').write_text(s[s.index('<script>')+8:s.rindex('</script>')])
PY
node --check /tmp/buddy-app-script.js
```

For release steps, use `RELEASE-UPDATER.md`.
