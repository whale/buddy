# Buddy: quieter mornings, safe keyboard access, adjustable list size

Prepared September 15, 2026. Planning baseline: `4535309`, clean checkout on entry;
Mac source version 0.4.37, iOS project version 0.4.34. These are source versions,
not a claim about installed apps or currently published releases.

## 1. Intent and execution boundaries

User requested a thorough Mac + iOS review, a complete plan for these three changes,
and overnight execution. This document authorizes implementation of that scope,
not publishing, merging to main, uploading to TestFlight, changing cloud infrastructure,
or replacing the user's installed apps. Mac main automatically releases: do NOT merge.

Work on `codex/buddy-settings-and-quiet-opening` if available; preserve any subsequent
user edits. No changes to managed AGENTS.md or CLAUDE.md. Use isolated test data,
browser contexts and simulator app storage; never pair tests to the user's sync key,
erase personal state, overwrite recovery files, or terminate the installed Buddy.

User clarification: start immediately, not at a scheduled time. The heartbeat
`buddy-overnight-settings-implementation` is PAUSED. Work is underway directly in
this task on `codex/buddy-settings-and-quiet-opening`. The morning switch is
**Mac-only**; do not add any iPhone morning controls. The list limit is shared.

### Defaults where the user has not answered

- List limit applies to ACTIVE tasks (neutral + focused), not completed history.
- Offer 3, 4, 5, 6; default 6. Mirror the control on Mac and iPhone; sync this preference.
- Mac automatic morning presentation: default on, new switch allows off.
- Morning presentation preference is device-local, not the shared `morningDone` flag.
- iPhone automatic morning is ALREADY disabled by a prior user decision. Preserve it.
  User explicitly confirmed no morning control on iOS.
- Remove plain-backtick summoning. Optional deliberate Mac shortcut, off by default:
  Command–Option–B. Show the actual shortcut and registration failure honestly.
- Lowering below current active count requires confirmation before moving excess
  items to Future. Cancellation changes neither settings nor tasks.

## 2. Review findings and evidence

This is a source/behavior-path review plus existing automated baseline checks, not
a completed native end-to-end audit. No feature code was changed during planning.

### Mac application and native window shell

`dist/index.html` owns task state, settings UI, editing, rollover, recovery, layout,
browser keys and the sync loop. `src-tauri/src/lib.rs` owns tray commands, OS-wide
shortcuts, wake/unlock observers, right-edge reveal, native storage, and separate
morning/celebration windows. These windows share application data but have separate
JavaScript instances. A setting must reach both existing and newly created windows.

**Typing interruption — strong source-level cause, not yet a native reproduction:**

- Native setup registers unmodified `Backquote` globally around lib.rs:1230.
  This can summon Buddy while typing in any other app, including non-US layouts
  where that physical key is ordinary text or part of a dead-key sequence.
- Native shortcut handler around :1132 treats every non-morning shortcut as a
  drawer toggle rather than matching an explicit allowed shortcut.
- Browser document keydown around index.html:4047 handles backtick BEFORE checking
  editing/settings. It does not exclude native mode, so an OS shortcut and a
  webview key event may both act. This can also swallow a literal backtick in text.
- The edge watcher around lib.rs:1360 reveals after roughly 500 ms at the right
  edge and unconditionally requests focus even when the morning guard is up.
  It is another possible interruption source. Do not assume every opening is a key.
- Other opening sources: tray, startup settling, wake/unlock, midnight rollover,
  explicit Morning, update banner, and focus/visibility listeners.

**Morning:** `bootFinish`, `liveRolloverCheck`, and `resumeMorningCheckInner` call
`showMorning`; manual tray Morning and Command–Option–Control–M enter via native
paths. Gating only startup would leave wake/unlock and midnight interruptions intact.
Rollover must remain active even when automatic presentation is disabled.
Current `settleNative()` deliberately flashes the drawer at launch, so it must not
be used as the automatic wake fallback when morning is off.

### iPhone application

- `BuddyStore.swift` hardcodes soft cap 5, hard cap 6, Boss threshold 5.
- `EscalationTheme.swift` independently hardcodes warning 5 / red 6.
- `TodayView.swift` disables automatic `MorningView` presentation (July 8 decision,
  comments around :159) because sync adoption disturbed editing. The full-screen
  cover remains for fixtures. `morningDone` intentionally stays untouched.
- Today, Morning, Settings, History and component previews all need a theme-call
  audit; several use `activeCount` rather than the already available
  `escalationCount` (which excludes untitled draft rows).
- `RowFit.swift` budgets active rows, completed rows, Add, Boss prompt and dividers.
  It must receive the new derived state, not become a fixed N-row grid.
- `BuddySettings.swift` has a tolerant missing-key decoder but no unknown-field
  preservation. Older iPhone binaries can strip a new setting placed there.
  Unknown TOP-LEVEL fields do survive via `extras` in both platforms.
- No cross-app global keyboard shortcut equivalent is needed on iOS. Test text
  entry with software and external keyboards; don't port Mac window controls.

### Persistence, sync and recovery

- Mac serialize/hydrate/apply, native primary + recovery files, localStorage backup,
  iOS disk persistence, sync wire encode/decode and merge all participate.
- Whole settings objects currently use the newer general save. A later unrelated
  task edit on an old device could reset a newly added settings field.
- `blobContentKey` / Swift canonical content keys explicitly include only selected
  settings. Adding a UI field alone does NOT guarantee setting-only changes sync.
- `clampActive` / `BuddyMerge.clampActive` cap merged work at 6 and move overflow to
  Future. They must receive the SAME resolved limit on both devices, never read a
  device-local global while merging two blobs.
- Existing overflow prioritizes Mac-minted IDs over iPhone-minted IDs, then later
  rows first. Keep this established deterministic policy for sync conflicts;
  do not redesign task priority as a side effect of this feature.
- Future relocation, its id invariant, sent/sentTid repair, tombstones and doneTombs
  prevent duplicates and resurrection. Preserve these guarantees.
- Rollover and restore contain slice/prefix-to-cap paths. Blindly replacing 6 with 3
  there could lose or strand unfinished work. Preserve every remainder explicitly.

### Baseline checks run during planning

- `pnpm test:merge`: 3/3 suites pass.
- `pnpm ui:smoke`: 4/4 tests pass.
- `pnpm test:edit`: 9/9 WebKit and 9/9 Chromium pass.
- `pnpm test:crossbuild`: 2/2 pass against local origin/main; this is NOT a substitute
  for testing the exact old iOS serialization behavior introduced by this change.
- `pnpm sync:validate`: 10/10, including Swift CryptoKit / browser encryption parity.
- Initial sandboxed browser launch failed on macOS process permissions; approved
  outside-sandbox rerun passed. Overnight work may also need approved native access.
- Privacy-safe event log read: historical network load/abort errors present; no
  proof those errors caused keyboard summons. Never log task text or raw keystrokes.
- Simulator enumeration succeeded outside the sandbox; no simulator was booted.
  Full iOS unit suite, new native build, native typing repro, physical-device checks,
  and live-backend regression were NOT run during planning.
- Existing Mac Settings visually inspected in an isolated browser at 452×900
  (normal theme) and 452×650 (full-list red theme). Card alignment and visible type
  are coherent and the red state is readable. Short-screen settings extend below
  the viewport; adding controls must preserve scrolling and close-button access.
  This is a limited baseline inspection, NOT final visual approval of new controls.
  Captures: `/private/tmp/buddy-plan-review-20260915/.playwright-cli/`.
  Local preview reported expected missing hosted config, a missing favicon and
  rate-limited weather lookup. No new feature code existed to cause these.

## 3. Product behavior and all derived math

Let **L** be the selected limit, **A** active slot count (including a live blank draft),
**E** active tasks with nonblank committed text, and **D** visible completed rows.

| Selected L | Normal, E | Red text, E | Red background, E | Add allowed, A | Boss prompt, D |
|---|---|---|---|---|---|
| 3 | 0–1 | 2 | 3 or more | 0–2 | 2 or more |
| 4 | 0–2 | 3 | 4 or more | 0–3 | 3 or more |
| 5 | 0–3 | 4 | 5 or more | 0–4 | 4 or more |
| 6 | 0–4 | 5 | 6 or more | 0–5 | 5 or more |

Rules:

- Warning threshold = L−1; red threshold = L; Boss threshold = L−1.
  This preserves every existing threshold at default 6. These are explicit product
  choices, not proportional percentages. At limit 3, two committed tasks warn.
- Free slots = max(0, L−A). Add, Enter/A/+, restore, undo completion, and Future→Today
  all share this check. Completion always frees a slot; done rows never consume one.
- Overflow count after title dedupe = max(0, unique active count−L). Existing done
  rows remain untouched. Temporary over-cap legacy state still renders readably.
- A pending empty edit reserves a slot but must not turn the screen red. Abandoned
  blank rows must still be cleaned safely without disrupting another webview's edit.
- Changing 6→3 with six real active tasks moves exactly 3 to Future after confirming;
  6→4 moves 2; 6→5 moves 1. With A≤L, no confirmation or movement is necessary.
- Raising the limit never silently pulls tasks out of Future. The user chooses.
- Completion history/export count, history retention, Future capacity, sync intervals,
  pinning/window width, reserve-space behavior and login launch do not scale with L.
- Celebration intensity stays 0–100 per completion. Existing particle calculation
  is max(3, round((intensity/100)^2 × CELEB.count)); its zero-intensity quiet feedback
  and reduced-motion behavior remain unchanged. No reward penalty for choosing 3.

### Layout math

Visible Today rows = active rows + visible Donezo rows + Add(if A<L) + Boss(if D≥L−1).
Morning currently hides done rows on Mac; audit the existing iOS difference without
silently widening scope. Count restore/notice rows whenever rendered. The list may
have more than L total visible rows because completed rows are not active slots.

Use actual wrapped content height, not viewport-height/L. Preserve existing fit
engines: Mac font 24→15 and padding 22→10; iOS font 24→16 and padding 16→8, with the
existing morning font configuration. Reduce padding, then font, then allow scrolling.
Budget dividers, Boss text wrapping, keyboard lift, safe areas, restore/overflow notices,
and settings card height. No fixed settings-panel height or unbounded row stretching.

### Settings copy and interaction

In Behavior: “Tasks on your list”, discrete 3 / 4 / 5 / 6 control; helper “Completed
tasks don't count.” Show the selected value clearly, allow keyboard/screen reader
operation, and use adaptive theme tokens for selected/hover/focus/disabled states.

If lowering over a full list: “Move 3 tasks to Future?” / “Your list will hold up to
3 active tasks. Nothing will be deleted.” Actions “Cancel” and “Move to Future”.
Preview the exact affected tasks locally before confirming; never send their text
to diagnostics. For an explicit local reduction, keep the focused task first, then
the earliest remaining tasks in the displayed order up to L; move the rest while
preserving their order. Commit that explicit relocation so peers adopt the same
selection; do not recompute it from a peer's different display order. Sync-union
overflow retains its existing origin-priority policy. Revalidate the preview after any concurrent state
change; require renewed confirmation if its affected task set changed.

Mac morning switch: “Show the morning planner automatically”; helper “On this Mac.
You can still open Morning from the menu bar.” Do not call it true macOS Full Screen:
the current morning is a separate screen-sized normal window, not a Space.

Mac shortcut: “Open Buddy with ⌘⌥B”, off by default, local to this Mac. Keep tray and
edge reveal available. Never silently revert to backtick if shortcut registration fails.

## 4. Implementation design

### A. Local presentation preferences

Add a small device-local preference store separate from the synchronized task blob.
Mac native storage is authoritative and shared between its webviews; browser preview
has its own local fallback. Load preferences before startup presentation and shortcut
registration. Broadcast changes to existing windows and re-read on a new window.
Persist first and surface failures rather than showing an off switch that is not durable.

Centralize automatic presentation as `maybeShowMorning(reason)`. Automatic entry
points (boot, rollover, wake/unlock) consult the preference; explicit Morning remains
available. Disabling must not mark today's plan complete, alter tasks, reset history,
turn off carry-over, change celebration, or change login launch. Re-enabling applies
to the next qualifying automatic event, without immediately interrupting typing.

Separate preferences from shared `morningDone`. Test persisted disabled preference
before an older task recovery blob is adopted; recovery must not re-enable it.
When disabled while a morning window is present, safely commit its live editor before
closing that view, then clear native/JS guards. Avoid async open/close races.

### B. Keyboard and focus safety

Delete global bare Backquote registration and browser bare-backtick interception.
Match only explicitly supported chords; one owner per event (Rust in native, guarded
browser fallback otherwise). Reject repeats, IME composition, and inappropriate
editable targets in local shortcut handling. Literal backtick, tilde and dead-key
typing must reach text inputs. Do not make a configurable shortcut recorder.

Register/unregister the optional chord when the local switch changes; handle conflicts,
failure, restart persistence and multiple-window events. Evaluate the existing manual
Morning chord separately; it is intentional and not a substitute for automatic gating.

Audit edge focus: passive hover reveal must not steal keyboard focus from another app;
explicit click/tray/chord may focus. Do not focus the drawer when morning blocks its
reveal. Verify native hover actions still work without a focus steal before changing
the existing policy. Record source-tagged show/focus requests (tray, chord, edge,
startup, morning-auto, morning-manual, updater) using event names/counts only.

### C. Shared task-limit preference and old-client compatibility

Do NOT merely add `settings.maxTasks` to the current whole-object merge. Store a
small versioned top-level `taskLimit` register, preserved by old clients' extras:
`{value: 3..6, v: positive integer, writer: stable installation id}`. New clients expose
it as one setting in the UI. Absence means 6 with revision zero; reading a legacy
blob must not count as a user edit or manufacture a newer default.

On an explicit change increment the highest observed register revision. Merge by
revision, then a shared deterministic writer/value tie-break; never by device-local
state or unrelated task savedAt. Validate value, revision bounds and writer shape.
Use the same canonical absent/default representation on both platforms. Invalid data
falls back safely to 6, not zero; integer values below/above range clamp to 3/6;
non-integers, booleans, strings and nonfinite values default to 6 on both platforms.

Resolve the register BEFORE task merge/overflow; pass its limit into clamp functions.
Include the register in both new clients' canonical change keys so setting-only changes
push. Old clients ignore that key but preserve it in extras; prove this with an old
iOS serializer fixture and exact old Mac build. A newly saved unrelated old-client
setting must not reset the limit. No schema/wire/crypto/server-floor change by default.
If round-trip or convergence fails, stop this milestone rather than shipping a reset loop.

Old apps will still offer six locally until updated. New apps must safely park overflow,
retain the register, converge without repeated writes, and explain the move. Document
this honest rollout limitation; do not promise an old binary enforces new rules.

### D. Task mutation and lossless overflow

Use shared derived helpers for limit, slots, warning and Boss threshold. Cover Add,
inline editor draft, keyboard Add, cycle-done→active, undo, history restore, previous-list
restore, restart-stash restore, Future send/unsend, automatic carry-over, sync apply,
recovery merge and test fixtures. Audit every HARD_CAP/SOFT_CAP/6/5 use semantically.

Limit change + selected overflow relocation must persist atomically as one user
mutation before peers see either half. Reuse existing relocation/invariant handling;
retain IDs, relevant extras, versions and truthful notice counts. Never slice/drop
remainder tasks. Preserve metadata when moving to Future and keep sent-link repair.
Choose the same result on Mac/iOS, including concurrent limit changes and offline edits.
Do not apply a remote limit by tearing out an active editor; use existing defer/commit
safety and reconcile afterward. Raising then undoing a reduction must not resurrect
duplicates; restoration from Future is an explicit task operation.

## 5. Work order and file map

1. **Baseline and regression fixtures.** Save original refs, run existing checks;
   add failing tests for auto-morning-off, literal typing, every L, and old-client
   register round-trips before changing production paths.
   Files: `scripts/buddy-settings.spec.js` (new), existing edit/crossbuild specs,
   `ios/Buddy/Tests/*` and screenshot harness fixtures.
2. **Quiet opening (independent of task-limit sync).** Local preferences, automatic
   morning gate, shortcut removal/opt-in and focus-source diagnostics.
   Files: `src-tauri/src/lib.rs`, `dist/index.html`, Tauri command/capability config
   only if required. iOS morning unchanged; no iOS morning switch.
3. **Shared register and pure policy.** Matching Swift/JS normalization, conflict
   resolution, content key and persistence, plus golden input/output vectors.
   Files: `dist/index.html`, `ios/Buddy/Sources/Store/BuddyStore.swift`,
   `ios/Buddy/Sources/Sync/BuddyMerge.swift`, `BuddySync.swift`, `CanonicalJSON.swift`
   as needed; a small dedicated policy type if it reduces duplicate logic.
4. **Lossless mutation coverage.** Apply resolved limit to every add/restore/rollover
   and sync path. Implement confirmed reduction and precise Future notices.
   Files: same Mac file / iOS store and merge; regression tests.
5. **Settings and derived UI parity.** Mac/iPhone discrete picker, confirmation,
   dynamic themes and Boss thresholds; preserve existing visual language.
   Files: `dist/index.html`, iOS `SettingsView`, `TodayView`, `MorningView`,
   `HistoryView`, `RowFit`, `EscalationTheme`, component previews and harness.
6. **Adversarial review and full verification.** Repository RULE 6 explicitly
   requires a second-mind review for risky native/sync work. Use a bounded skeptic
   subagent to break the actual diff before presenting it as complete; fix findings.
7. **Morning handoff.** Update this plan's checklist, STATUS.md, README keyboard and
   cap descriptions, SYNC-COMPAT.md, VALIDATION.md and RELEASE-CHECKLIST.md as needed.
   Describe local changes, tests, native observations and blockers separately.

Steps 3–5 share central files: do not run competing writers against them. Work in
small verified increments; a green quiet-opening milestone is useful even if the
shared-limit milestone hits a real compatibility blocker.

## 6. Acceptance matrix

### Pure policy and persistence

- L=3/4/5/6 × A=0..8: slots and all gates; E separately tests a blank active draft.
- 4×4 old/new limit transitions, with zero, one and many completed rows.
- D below/at/above L−1; cleared Donezo rows excluded; history/export unaffected.
- Missing, null, string, boolean, fractional, negative, large and malformed fields;
  old save, backup/recovery, restart, upgrade and erase/unlink behavior.
- Setting-only sync; reversed merge order, repeated merge fixed point, three-device
  merge ordering, simultaneous changes, stale newer savedAt, offline reconnect.
- Task IDs/text never disappear; no active/Future duplicate id; no dead sent link;
  no completion resurrection, no lost edits, no permanently reserved blank slot.
- Old Mac↔new iOS, new Mac↔old iOS and new↔new, including both save directions and
  older peers changing celebration after receiving a new limit.

### Morning and keyboard, observed natively

- Automatic morning off on fresh boot, same-day restart, next day while app is open,
  sleep/wake, lock/unlock, missed notification, and recovery. Carry-over still runs.
- On retains current behavior; manual Morning still works after off; tray/settings/
  pin and edge guard recover after dismissal. Slow native open cannot race off.
- Type ordinary prose, punctuation, backticks, tilde, held keys and composition in
  another app with pointer away from and resting at the right edge. Buddy must not
  gain focus from ordinary typing or passive edge reveal.
- Optional chord works exactly once per press; off really unregisters; conflict
  keeps it disabled with useful copy. Type literal backticks within Buddy too.
- Capture focus event source + observation, not raw keystrokes or private task text.

### Automated and build checks

- Mac: `pnpm test:merge`, `pnpm ui:smoke`, `pnpm test:edit`,
  `pnpm test:crossbuild`, new settings suite, `pnpm sync:validate`.
- Native Rust check/tests and an isolated unsigned/dev build. Do not confuse updater
  signing failure with compilation, or a successful browser check with native behavior.
- iOS regenerate Xcode project if needed; run BuddyTests and compile Debug AND Release
  against an available simulator destination. Add real UI tests for picker/confirmation,
  keyboard editing, settings during sync and relaunch persistence.
- Live sync/unlink regressions only with throwaway buckets, never user state. Reuse
  existing harness after checking its cleanup/config. No production migrations.

### Mandatory visual verification after final code changes

Rebuild latest source, render the actual app, inspect screenshots (not just take them),
fix visible defects and repeat. Mac drawer: 452×650 and 452×900; planner: representative
small laptop and large desktop usable areas. iPhone: smallest available supported size
and a large phone, keyboard shown/hidden, larger accessibility text where supported.
For EACH L inspect normal, warning and red states with Settings open and closed;
selected picker, hover/focus, switch states, confirmation, overflow notice, Boss row,
long/multiline tasks, many done rows, Future and history restore controls. Check
spacing, type, clipping, contrast, scroll reachability, hit targets and safe areas.
Observe motion/focus in a recording or sampled frames, not a still. Reduced motion
must retain usable feedback. Do not present uninspected output as polished or verified.

## 7. Completion / release gate

- [ ] Opening behavior changes implemented and separately verified.
- [ ] Both platforms agree on all limit math and lossless task operations.
- [x] Older-client round-trip and convergence tests pass.
- [x] Fresh final settings renders visually inspected on Mac and iPhone (scope below).
- [x] Adversarial review findings resolved; re-review reported no remaining blocker.
- [x] Implementation report records passed and not-run checks below.
- [x] Scheduled continuation paused immediately when user requested work now.

Public release is a separate approval. At that point coordinate Mac and iOS versions,
signed Mac artifacts and a manually uploaded, Apple-confirmed TestFlight build.
Neither a local build nor a merge alone proves both apps shipped.


## 8. Implementation checkpoint — September 16, 2026

Implemented immediately on `codex/buddy-settings-and-quiet-opening`; nothing published,
installed over the user's app, or pushed. Morning switch exists only on Mac.

### Evidence
- Browser: 20 settings/merge/cross-build tests, 4 UI smoke tests, 9 WebKit and
  9 Chromium editing tests pass. Sync validation: 10/10 checks.
- Native Mac: Rust check and isolated debug app bundle pass (existing deprecated
  NSApplication warning). Used separate identifier `fyi.whale.buddy.settingsqa`.
  Observed switches work, limit selection persists, automatic Morning stays off
  after quitting/relaunching with an unplanned list, explicit ⌘⌥B opens drawer.
  Manual Restart Buddy still opens its deliberate planner. QA app quit afterward.
- iOS: Debug suite passed: 136 unit tests (5 skipped) plus 1 passing UI test.
  Release simulator compilation passed; final results in
  `/private/tmp/buddy-ios-final-tests.log` and `/private/tmp/buddy-ios-release.log`.
  Three legacy unit tests initially inherited a three-item preference from UI tests;
  their default-six setup is now explicit rather than relying on clean app storage.
- Legacy compatibility: actual origin/main Mac page round-trip plus frozen baseline
  iPhone wire encoder; newer edits/completions survive cross-list parking and merging
  either stale peer back in does not resurrect completed work.
- Visual inspection: all four limits × normal/warning/red Settings states on Mac
  at 452×900 and iPhone 17 Pro; Mac confirmation and scroll-to-actions at 452×650;
  iPhone SE 375-point layout; actual native Mac Settings. No new collisions in these
  supported layouts. Captures: `/private/tmp/buddy-settings-qa`.

### Still owed before release approval
- Native sleep/wake, lock/unlock, midnight, shortcut conflict/unregistration, held
  key/composition, and typing in another app with pointer on the right edge.
  Source/automated coverage is not proof of every operating-system focus path.
- Live backend and real paired-device sync under prolonged reconnect; current
  verification is local merge/crypto/legacy format coverage, not a real phone pairing.
- Full accessibility-size, keyboard-visible, reduced-motion and all non-Settings
  surface visual matrix from section 6. Settings screenshots do not verify them all.
- Existing fixed-width Mac web preview clips at 340px; actual native drawer and
  supported browser QA width is 452px. No unrelated responsive redesign made.
- Coordinate updated Mac/iOS releases: old clients preserve the preference but
  still enforce their old six-item UI until updated. No release has been authorized.

Both unchecked release gates remain intentional: implementation is in place, but
complete native opening verification and the exhaustive lossless-operation matrix
are not claimed from the narrower checks above.

## 9. Follow-through verification — September 16, 2026

User requested finishing unfinished work. No production code changes were needed
in this pass; expanded regression coverage and completed these checks:

- Live backend: **4/4 two-device tests and 1/1 mutual-unlink test pass** using only
  fresh throwaway keys. New test reduces 6→3 while a peer edits offline, reconnects,
  checks all six IDs/text survive, then syncs 4/5/6 in the opposite direction and
  verifies raising does not automatically restore Future. This is two browser
  clients on the real backend, not a physical iPhone claim.
- Live harness initially failed a direct non-null assertion when a background poll
  already owned the sync pass. Fixed the test helper to wait (bounded 15 seconds)
  for an actual completed pass. Permanent failures still time out; all convergence
  and data-preservation assertions remain. Full suite passes after the change.
- Settings regressions: **16/16 pass**, including new rollover/resume-handler opt-out
  and editable/repeat/composition shortcut guards. Resume handler simulation does
  not substitute for a real macOS sleep/unlock observation.
- iPhone: **138 unit tests, 5 local-backend skips, 0 failures; 1 UI test passes**.
  Added all-limit tests for add, blank-slot accounting, undo, History restore,
  Future restore, rollover overflow preservation, stale-confirmation refusal,
  focused-task retention and raising-without-restoring. The skipped tests require
  a separate local Supabase at port 54321; hosted browser tests above ran for real.
- Native Mac isolated QA: enabling shortcut opens drawer; switching it off then
  pressing ⌘⌥B leaves Settings open/unchanged. Literal backtick/tilde entry in an
  editable field remains text. Temporary text was cleared and QA app quit.
- Additional inspected renders: Mac 452×900 Today at every limit with done rows,
  corresponding 2/3/4/5-done Boss prompts, long focused text, reduced-motion
  Settings and settled hover/focus in all three themes. Transient frames were
  recaptured after animation settlement before judging layout. iPhone SE at
  largest system accessibility text setting: controls remain unobstructed; the
  existing fixed-size Geist typography does not itself grow with Dynamic Type.
- Preview console: optional config.js/favicon 404 and geolocation service 429,
  plus existing Tailwind vendor warning. No new feature JavaScript exception.
- `git diff --check` passes. No publish, main merge, installed-app replacement,
  production sync key use, or personal task changes.

### Remaining hands-on gate (permission requested, not assumed)
A paired physical iPhone is available. Requested permission to install a separate
Buddy QA app and briefly exercise real Mac sleep/wake. Until answered, do not
install on that phone or suspend/lock the user's Mac. This also needs final
cross-app typing/right-edge, OS-level shortcut conflict, and actual device-pair
reconnect checks. Current installed Buddy may still own the old global shortcut;
it must not be silently terminated merely to make the QA build's test pass.

The implementation and expanded automated checks are complete locally. The full
native lifecycle/physical-pair release gate is explicitly still open, not waived.


## 10. User-authorized release — September 16, 2026

User then explicitly requested shipping all finished work to all users. PR #163
merged; signed/notarized Mac 0.4.39 release is live and its actual updater endpoint
was checked for both CPU architectures. iOS 0.4.39 build 45 was archived, signed,
uploaded and processed VALID. Apple reports internal IN_BETA_TESTING and external
WAITING_FOR_BETA_REVIEW. Build assignment verified via each beta group's builds:
internal and Friends both include build 45. External availability is pending Apple,
not an unfinished upload. Do not describe external iOS distribution as complete yet.

All 10 iOS interaction tests and 138 unit tests (5 local-backend skips) pass in the
full release run. Mac gates rerun successfully against published 0.4.38 baseline.
Previously documented hands-on gaps were not retroactively marked verified.
