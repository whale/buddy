# Buddy — Next Session Handoff

_Last updated: 2026-06-23._

## Start here

- Branch: `main`
- Latest local commit: `8d227e7 chore: bump version [skip ci]`
- Current app version: `0.2.31`
- Working tree is intentionally dirty from the 2026-06-23 session. Review before committing.
- Installed local app has been replaced with the fixed build at `/Applications/Buddy.app`.

## What just happened

A real Tuesday morning data-loss bug was reproduced from local files. The live installed app had saved Tuesday, June 23 as an empty day while Monday, June 22’s six tasks remained in history/recovery. The old running app also overwrote an initial manual repair.

Fixes made locally:

- Recovery merge now preserves an older live list as history when a newer different-day empty state wins live.
- Empty, unplanned mornings can auto-restore yesterday’s unfinished list.
- Empty today views can show a “Restore [weekday]’s list” row.
- The user’s six tasks were restored into `~/Library/Application Support/fyi.whale.buddy/buddy-state.json` and `buddy-state.recovery.json`.
- The settings reserve switch now uses deep Buddy red on the red panel instead of black.
- Top icon hit targets were fixed: 44×44 minimum, SVGs no longer steal pointer hits, and smaller controls were brought up to target size.
- `pnpm ui:smoke` was added and passes. It runs Buddy’s internal smoke test, including the new hit-target audit.
- `Buddy-Old.app` was moved to Trash. If System Settings still lists “Buddy-Old” under Accessibility, remove the stale row manually with the minus button.
- Later todo preserved: use `https://joi.software/` as a concept reference for Buddy’s launch page, not for now.

## Verified commands from this session

```bash
pnpm ui:smoke
```

Passed.

Additional verified checks run during the session:

- Playwright recovery/smoke test passed.
- Playwright full sync test passed.
- `pnpm build` produced the `.app` and `.dmg`, then failed only at updater signing because `TAURI_SIGNING_PRIVATE_KEY` is not set locally.

Installed app check:

```text
/Applications/Buddy.app/Contents/MacOS/buddy
```

was verified running, and the restored six tasks remained in the state file after relaunch.

## User-facing review instructions

1. Open Buddy from the menu bar or right edge.
2. Confirm the six restored tasks are visible and usable.
3. In the red over-limit state, open Settings and confirm the reserve switch is deep red, not black.
4. Click around the pin, calendar, and gear icons. Their hit areas should feel centered and reliable.
5. If Accessibility still shows “Buddy-Old,” remove that stale row with the minus button.

## Next 3–5 tasks

1. Review the working tree and commit the 2026-06-23 fixes if everything feels good.
2. Run `pnpm ui:smoke` before every future install/release.
3. Configure release signing: set `TAURI_SIGNING_PRIVATE_KEY` and the GitHub release secrets in `RELEASE-UPDATER.md`.
4. Cut a signed/notarized release so installed users get the recovery and hit-target fixes.
5. After release, verify the in-app updater moves `/Applications/Buddy.app` to the new version.

## Blockers / cautions

- Do not edit `AGENTS.md` or `CLAUDE.md`; they are managed elsewhere.
- Do not commit `.env`, private exports, app data files, or generated build artifacts.
- `pnpm build` locally will keep failing at updater signing until `TAURI_SIGNING_PRIVATE_KEY` is available, even though the `.app` bundle is produced.
- The current fixes are installed locally but not shipped publicly until a signed release is cut.
