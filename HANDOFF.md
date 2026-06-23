# Buddy — Next Session Handoff

_Last updated: 2026-06-22._

## Start here

- Branch: `main`
- Latest local/remote commit: `2127325 chore: bump version [skip ci]`
- Current app version on `main`: `0.2.29`
- Important merged PR: #33 — recovery-file protection for accidental empty-state overwrites.
- New workflow: `.github/workflows/release-mac.yml` publishes Mac releases after version bumps once `AUTO_RELEASE_MAC=true` and signing secrets are configured.

## What just happened

A user restart/update made the current task list appear lost. Investigation found the tasks still existed in both:

- `~/Library/Application Support/fyi.whale.buddy/buddy-state.json`
- WebKit localStorage for `fyi.whale.buddy`

PR #33 added a native recovery file and boot-time merge so an accidental empty same-day state should not permanently overwrite real task data.

## Verified commands from this session

```bash
cargo check
node --check /private/tmp/buddy-app-script-main.js
```

Both passed before PR #33 was merged.

## User-facing review instructions

After cutting a new build, test this exact scenario:

1. Install/open the new Buddy build.
2. Confirm a non-empty today list is saved.
3. Simulate or force a stale/empty same-day state in the primary store.
4. Relaunch Buddy.
5. Confirm today’s real list is restored from `buddy-state.recovery.json`.
6. Confirm intentional delete/erase does not resurrect old tasks.

## Next 3–5 tasks

1. Add the GitHub release secrets listed in `RELEASE-UPDATER.md`, then set `AUTO_RELEASE_MAC=true`.
2. Run **Release Mac app** manually once, or merge a small update to trigger the version bump + release chain.
3. Verify the in-app updater moves `/Applications/Buddy.app` beyond `0.2.21`.
4. Run an on-device recovery simulation against the built app.
5. Inspect local branch `feat/sync-live` before doing any more sync work; it contains unmerged live-sync progress.

## Blockers / cautions

- Do not edit `AGENTS.md` or `CLAUDE.md`; they are managed elsewhere.
- Do not commit `.env`, private exports, or build artifacts.
- The recovery fix is on `main`, but not shipped to installed users until a release is cut.
