# Buddy — Status & Handoff

_Last updated: 2026-07-21. Branch `main`. Latest **Mac**: **`v0.4.27`** (auto-released via CI; DMG + updater manifest live). Latest **iOS**: **TestFlight `0.4.27 (build 40)`** — Apple-confirmed VALID. Both platforms fully in sync at 0.4.27. Live docs: THIS file + `RELEASE-CHECKLIST.md` + `SYNC-COMPAT.md` + `VALIDATION.md`._

## Session summary — 2026-07-20/21 — iOS Boss Mode (mirrored + synced), RULE 8, and two iOS fixes

Shipped to **Mac v0.4.27** + **iOS TestFlight build 40 (0.4.27)** (Apple-confirmed). This batch was iOS-only feature/UI work mirroring existing Mac behaviour, plus a new process rule; each Mac release here was a no-op lockstep rebuild (no Mac code changed).

**iOS Boss Mode — mirrored the Mac, WITH cross-platform sync (0.4.26).** At 5+ done, a row offers "Move to done, and make room for more?" → sweeps finished tasks off the Today list (they stay in the Done tab, roll over, sync). `BuddyTask.clearedAt` is a computed field backed by the per-item `extras` bag (epoch-ms, matching the Mac's `item.clearedAt`), so it rides the EXISTING wire with ZERO merge/contentKey change — a sweep on either device mirrors to the other. `bossMove` v-bumps to carry the change; `clearedAt` resets on cycle/complete/restore. Adversarial review confirmed the sync solid and caught a fit-math bug (the Boss row was unbudgeted in `RowFit` → could clip the bottom row; fixed).

**RULE 8 (CLAUDE.md).** Standing directive: every feature must consider the OTHER platform and ASK the user whether to mirror it (functionality + sync) before it's called done.

**Two iOS fixes (0.4.27).** (1) Boss row message padding 20→32 to align with task rows. (2) The celebration burst never fired on a REAL completion — only the forced `.task` fixture worked. Root cause (found by on-device observation): `TimelineView(.animation)` + `Canvas` silently never starts its clock when the overlay is CREATED via an async state change (a tap callback). Fix: celebration is now ALWAYS mounted + trigger-driven (`.id(celebrationTick)`), uses `.periodic` (deterministic schedule), and gates the `TimelineView` on the populated particles so it's created in the post-`launch()` re-render — which is what makes it tick. Adversarial-reviewed after the fact: no idle battery drain, no touch-swallowing, safe on rapid completions, Mac-parity constants untouched.

**Verified:** iOS 101 unit tests · Boss row on device (lvl0 + lvl2) · clearedAt wire round-trip + merge + "per-item-v beats savedAt" tests · celebration burst confirmed full-screen + uncut on a real completion (new DEBUG `celebration-real` fixture) · `pnpm sync:unlink` two-device live · Mac v0.4.27 assets + iOS build 40 VALID (both at source).

**Outstanding / notes:**
- iOS-only features still cut a no-op Mac release for version lockstep. Weigh `[skip release]` vs lockstep per change (currently choosing lockstep).
- `ECOSYSTEM.md` + `PAYMENT-PLAN.md` are uncommitted drafts. **PAYMENT-PLAN §5 says it updated HOSTED-PLAN.md but never did** — HOSTED-PLAN still lists "Lemon Squeezy vs Paddle" (decided: Polar) + "buddy.whale.fyi" (decided: kuma.wimpdecaf.com), and frames the pass backend as "someday" vs PAYMENT-PLAN's day-one blocker. **User decision pending** before committing those drafts.
- Minor deferred: iOS morning planner shows done tasks (Mac hides them) — pre-existing parity gap, unreachable for cleared items.

## Session summary — 2026-07-19/20 — sync never deletes tasks + mutual unlink

Two features, both shipped to **Mac v0.4.25** + **iOS TestFlight build 38 (0.4.25)** (Apple-confirmed). Both are shared sync plumbing → byte-parallel Mac (`dist/index.html`) + iOS (`ios/Buddy/Sources/Sync/*`), each caught a real bug in adversarial review (RULE 6) that the happy-path tests missed.

**1. Overflow → Future (sync never silently deletes a task).** When the UNION of two devices' active tasks exceeds the 6-task cap, the over-cap tasks are now MOVED to Future (undated) instead of dropped, with a **synced, dismissible notice** ("Sync combined N tasks. M overflow tasks have been moved to the Future tab.") + a Future button. **Mac tasks (lowercase UUID ids) keep the 6 slots; iPhone tasks (uppercase ids) overflow first** — encoded in the id so both devices compute the identical result. Relocation happens inside `merge()`, reuses each item's own id, and an invariant keeps a parked id off the active list (deterministic, converges — verified by a 400k-merge fuzz + the two-device live test). New synced field: `syncNotice {combined,moved,dismissed}`, in `blobContentKey` so a dismiss propagates. Review fix: counts are truthful (only tasks ACTUALLY relocated this merge count; `keptActiveCount` read after the invariant filter).

**2. Mutual unlink (unlinking one device breaks the link for BOTH).** The unlinking device stamps the shared bucket with a synced `unlinkedAt` marker (transport-only — read RAW in `syncOnce` before any merge, NEVER merged or adopted), then clears its own syncKey so reconnect is a fresh QR pair. The peer sees the marker on its next pass, self-unlinks, keeps its own tasks, and shows "Your Mac unlinked this device. Pair again to sync." **Review caught a CRITICAL concurrent-sync race**: an in-flight pass overlapping the unlink tap CAS-conflicted and folded+repushed the marker — which on Mac LEAKED it into local state (`extras` → permanent, unrecoverable re-pair breakage) and on iOS ERASED it (peer never unlinks, user falsely told it did). Fixed at the root: `syncOnce` reads the marker in the CAS-retry loop too and BAILS; `pushUnlinkMarker` retries so it reliably lands; Mac added `unlinkedAt` to `DROP_WIRE_KEYS`; `handlePeerUnlink` guards on still-linked; iOS surfaces a failed/offline unlink honestly.

**Verified:** Mac `syncTest` 38/38 (+ overflow, Mac-priority, notice, dismiss, overlap, mutual-unlink detection, concurrent-race) · Mac `mergeTest` ok · iOS 95 unit tests (+ same coverage + Mac↔iOS contentKey byte-parity pin) · `ui:smoke` 4/4 · **`scripts/buddy-unlink-live.spec.js`** two-device LIVE mutual unlink on real Supabase · overflow banner + iOS unlink note confirmed on both platforms (lvl0/lvl1/lvl2). New `__buddy` test hooks: `syncUnlink`, `syncPeerUnlinked`. New iOS screenshot fixtures: `sync-notice`, `sync-notice-lvl0`, `peer-unlinked`.

**Outstanding / notes:**
- The **v0.4.24 Mac release run FAILED** during a 2026-07-19 GitHub API outage — harmless: **v0.4.25 supersedes it** with all the code. No v0.4.24 tag exists; don't reuse it.
- iOS `MARKETING_VERSION` is tracked to `0.4.25` (PR #143); bump it in lockstep each Mac release (RULE 5).
- `ECOSYSTEM.md` + `PAYMENT-PLAN.md` remain uncommitted drafts (parked pending a public-vs-private decision).

---


## Session summary — 2026-07-19 — wire-2 sync fix + settings redesign + holdover cleanup

Big session. All shipped to `main` (Mac auto-released to **v0.4.23**; iOS cut to **TestFlight 0.4.20 build 36**, Apple-confirmed).

**Sync — fixed the 2026-07-18 split-brain (a v0.1.0 phone silently corrupting a v0.4.15 Mac's data):**
- New **wire-2 envelope**: a cleartext, AES-GCM-AAD-authenticated header `{b,wire,crypto,minReader}` on every synced row, so any client (and the server) can triage before decrypt and **degrade instead of corrupting**. Byte-identical on Mac (`dist/index.html`) + iOS (`ios/.../Sync`), pinned by a shared vector `dwuU613APPxtAVeAdb_UI1J97z3qrFHjfMMU`.
- **Refuse-to-clobber** on both platforms; iOS shows "Update Buddy to keep syncing"; Mac shows "Update needed".
- Design + threat model in **`SYNC-COMPAT.md`**; the reproduction/guards in `__buddy.skewTest`; one-command check **`pnpm sync:validate`** (10/10, incl. Mac↔iOS envelope parity via Swift); runbook in **`VALIDATION.md`**.
- **Server wire floor** SQL (`supabase/migrations/20260719130000_buddy_wire_floor_fix.sql` + hosted-setup) — ships DISABLED.

**Other shipped:** Settings redesigned to grouped cards (Mac + iOS); sync **watchdog** GH Action (`.github/workflows/sync-watchdog.yml`, emails hi@whale.fyi on failure); pairing UX ("Waiting for iPhone…" + "Cancel"; QR 150→113px flush); cold-launch morning/drawer overlap fix; holdover cleanup (removed the fake demo-history seed for new users, removed iOS "Enter manually" pairing, gated MockData, fixed stale "prototype"/"scaffold" copy).

**New guardrails:** RULE 5 (two release rails — iOS is manual `fastlane beta`), RULE 6 (adversarial review before shipping risky work), RULE 7 (confirm at the source of truth, never a proxy exit code / Debug build). Tooling: **`pnpm ios:beta`** (fastlane + polls App Store Connect to confirm the build is really live), `scripts/buddy-asc-builds.mjs`.

**Verified:** `sync:validate` 10/10 · iOS `BuddyTests` TEST SUCCEEDED · Release-config iOS build · App Store Connect confirms build 36 v0.4.20 VALID.

**Outstanding / NOT done or NOT verified:**
- **User:** update the iPhone to 0.4.20 + re-pair (Mac Settings → Resync shows QR; phone → Scan QR). Add 4 SMTP secrets for the watchdog email.
- **Server floor:** the migrations are in the repo but NOT deployed to live Supabase, and `supabase/tests/buddy_wire_floor_test.sql` was NOT run (no local pg here). Deploy + test, THEN `select public.buddy_set_wire_floor(2)` only AFTER both devices are on wire-2.
- **Cold-launch fix:** logic sound but the native "update-pending + first launch" race was NOT observed on the real app.
- **Deferred:** the hidden web-demo fake-desktop + `#devMorning` (display:none in native, but referenced by the pin logic — needs a verified native pass, RULE 6).
- **Docs:** `ECOSYSTEM.md` is still an uncommitted draft (parked with `PAYMENT-PLAN.md`, pending a public-vs-private decision) — should hold the release-rails table.



## Session summary — 2026-07-10 (night) — celebration physics, add choreography, swipe pan, friend beta

**Shipped as Mac v0.3.34 + TestFlight (28)** (PRs #93–#96, on top of the earlier marathon):
- **Physics celebration, both platforms** (lab preset "Whale ✦ picked"; constants in dist `CELEB/QUIET` and iOS `CelebPhysics` — change together): ballistic integrator, bottom-RIGHT of the SCREEN → top-left at full lab speed (a width-scaling squeeze read as a "swirl" on the phone — removed). Emoji variety scales with intensity (parrots+thumbs → full happy spread). **celebrate = 0 → quiet pop**: one yellow hand (👍🤘💪✊🤜) floats 70px up from the completed row's ✓, in-fast/out-slow.
- **Mac full-screen overlay window** `confetti`: transparent, click-through, floating, created lazily, hidden after each burst; surface is a pure renderer (no load/sync/saves, deaf to drawer broadcasts); Rust `celebrate_fullscreen`/`confetti_ready` (boot-replay handshake)/`hide_confetti_window`. ⚠️ **The native overlay's first appearance is UNVERIFIED** — it needs a real completion (no automatable trigger); if it misbehaves, windump the live windows first.
- **Calm add (iOS)**: removed the blanket `.animation(value: items/activeCount)` wrappers that crossfaded every descendant during add (blank header/rows) — one explicit animation driver per interaction; bottom bar has its own scoped fade. Frame-analyzed before/after.
- **Swipe pan (iOS)**: translation measured in the WINDOW (self-referential measurement under-counted travel → "bounce, needs two pulls"); direction check prefers accumulated translation. ⚠️ Feel on a real 120Hz device still needs the user's thumb.
- **Synced-done morph**: a task completed on the other device now becomes a Donezo row (render sets a catch-up timer; isDonezo is time-based but only the completing device re-rendered).
- **Settings sync row (Mac)**: Unlink iPhone + Resync side by side, "Synced HH:MM · bucket" on its own line below.
- **Friend beta (user completed setup)**: external group "Friends" created, tester added, **build 27 submitted for Apple Beta App Review — still `WAITING_FOR_BETA_REVIEW` at wrap** (check with `cd ios && fastlane status`). The invite email auto-sends on approval; the friend then auto-receives newer builds (28+) pushed to the group.

**Verified at wrap:** ui:smoke 4/4 · cargo check · iOS 74 unit + 9 UI tests · Mac burst direction measured in browser (x̄ 812→701 right→left) · iOS full-screen cascade sim-recorded · sync:doctor = one bucket (0dc16090) · v0.3.34 release assets + TestFlight 28 distribution confirmed via API.

**Next session:** (1) user's on-device pass — Mac overlay burst (first native flight!), swipe feel, quiet pop on both; (2) `fastlane status` → nudge user when build 27 review clears (the session-bound watcher died with this session); (3) then the standing queue below.

---

## Session summary — 2026-07-10 (marathon) — 15 field reports fixed + shipped both platforms

**Shipped as Mac v0.3.29 + TestFlight (25)** (PRs #90, #91):
- **THE PATTERN**: every text/element follows lvl0 black → lvl1 red → lvl2 white-on-red, no done-row carve-out. Contract: `design/escalation-tokens.json`, pinned by Mac smokeTest asserts + iOS `EscalationTokenParityTests`.
- **Mac**: history is a real slide-up sheet; sheets slide (ease-out up / ease-in down, curves in `:root`); Future +/× jitter fixed; Enter commits an edit (no chain, no complete); Tab hops rows / walks the Future panel; Buddy wordmark → Today; Give-Buddy-room `reserve_trusted` + Settings hint (root cause: TCC grant dies on re-signed updates — user must remove+re-add in Accessibility); **mid-edit sync no longer truncates commits** ("Thing"→"Thi": polls skip while editing + blur v-bumps vs edit-start).
- **iOS**: ghost-sizing edit swap (0.0pt text movement, pixel-verified); keyboard lift for low rows; date header from real font metrics (cap+64, baseline 32 from bottom); Mac-identical sheet curves + card-clipped sheets (no close flash); Future scrolls (UIKit `HorizontalPanCatcher` — ANY SwiftUI drag starves the ScrollView; overlay must ride BEFORE `.offset` or tray taps are swallowed, caught + regression-tested same day); swipe tray a11y ids.
- **Sync forensics**: dev build was split-brained onto a stale syncKey bucket. `pnpm sync:doctor` (containers → buckets → backend verdict), bucket suffix in both Settings ("Synced HH:MM · 0dc160"), `sync-owner` diag event. Dev now paired to the real bucket.
- **Process**: `RELEASE-CHECKLIST.md` (pre-ship regression pass, wired into RULE 2); CLAUDE.md **RULE 4** (see it, don't infer it — simulator/video evidence for every interaction claim); fastlane `beta` now **waits for App Store processing** (a silently-swallowed upload = loud failure; build 21 vanished this way) + `fastlane status` lane; ship announcements always state version/app/what-to-check (memory: feedback-ship-announcements).

**Open:**
1. User on-device pass of v0.3.29 + build (25); Give-Buddy-room re-grant (user action).
2. Dead-code sweep (still from THE PLAN batch 5): edge-tab subsystem, `renderSkipped`, `#morningUndone`, `.todaybadge`, `--chrome-hover`, `.donezo-leaving`, iOS `TaskRowView.swift`, `EscalationTheme.focusFill`.
3. THE PLAN batch 4 burrs: weekday XSS escape + CSP, Backquote global-shortcut chord, iOS Done-tab "Today" undo no-op, updater re-check after failed install, drawer poll pause when tucked, QR-in-bug-screenshot.
4. Known minor: iOS Settings sync fields don't keyboard-avoid; reserve strip 416 vs drawer 452; reserve is main-display-only.
5. If ONE more merge-class sync bug appears: migrate the document to Automerge (agreed stance) instead of patching.

---

## Session summary — 2026-07-10 (morning) — Future rows, red-state regression, Morning launch, releases

**Shipped + verified:**
- **Mac Future rows restored to desktop behavior:** Future rows are fixed at 110px, no extra `Future` heading, and actions are Mac hover-only (vertical `+` and `×` rail). iOS remains swipe-only for Future rows.
- **Future red-state regression fixed:** at 5 active tasks (`lvl1`), Mac Future titles now turn Buddy red; at 6 active tasks (`lvl2`), Future rows are white-on-red and `+` is hidden. iOS Future sent rows now follow the same escalation colors.
- **Morning window work continued:** Morning is a separate standard macOS window labeled `morning`; drawer remains `main`. Local app confirmed two Buddy windows after tray actions: a 2px drawer sliver and a standard Morning window at visible-screen size with an 8px inset. Raised Morning via AX after launch.
- **Releases:** Mac **v0.3.27** published successfully: `https://github.com/whale/buddy/releases/tag/v0.3.27`. iOS **TestFlight build 20** uploaded successfully; Fastlane skipped waiting for App Store processing. A docs-only wrap commit then triggered a source bump to `0.3.28`; no Mac `0.3.28` release was started in this session.

**Verified this session:**
- `pnpm ui:smoke` → **4/4 passed**, including new Future escalation regression test.
- `xcodebuild test -project ios/Buddy.xcodeproj -scheme Buddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` → **73 tests passed**, **1 UI editing test passed**, **5 live Supabase tests skipped** because local Supabase was not running.
- `cd src-tauri && cargo check` → passed.
- GitHub Actions Mac release run `29067686269` → success, assets uploaded (`Buddy_0.3.27_universal.dmg`, `Buddy.app.tar.gz`, `latest.json`).
- Local visual check: Playwright screenshot `/tmp/buddy-future-lvl1.png` confirmed Future text is red at warning state. Local `pnpm build` produced a usable `.app`; final updater signing failed locally because `TAURI_SIGNING_PRIVATE_KEY` is not present, expected because CI owns signing.

**Still open / needs human confirmation:**
- User should install/update to Mac `0.3.27` and confirm: Future hover icons, Future red state, Morning window resize/position behavior across displays, and whether the 8px visible-screen inset feels correct.
- User should wait for TestFlight build `20` to finish processing, install it, and confirm Future swipe actions plus red-state colors on device.
- Morning menu action may create/show the Morning window but not always raise it immediately in local automation. If the user still sees no Morning window, inspect existing Buddy windows before adding another geometry fix.

**Next recommended milestone:** finish the Mac Morning-window behavior as boring native macOS: visible, frontmost when requested, resizable by edges, survives display switches, and does not fight the drawer.

---

## Session summary — 2026-07-08 (evening/night) — Slice 2 shipped, field-report batch, self-diagnosis capability

Mac `0.3.18` + `0.3.19` released; iOS TestFlight builds `14` + `15`. PRs #80–#82 merged; draft #61 closed.

**Shipped + verified:**
- **Sync Slice 2 (PR #81)** — fully deterministic symmetric merge on BOTH platforms (`merge(a,b)===merge(b,a)`): savedAt = last user mutation; deferred rows carry `v`; projected-wire tiebreaks (Swift `CanonicalJSON` byte-parity-tested vs the Mac's JS); calendar-later day wins live; sent-row reconcile; unknown-field pass-through (version-skew safe); restartStash rides the wire; iOS foreground rollover; corrupt-store set-aside + .bak on iOS. **User confirmed cross-device sync feels seamless.**
- **Field-report batch (PR #82)** after live testing: banner sits on ONE PLANE (drop-shadow on the drawer column, box-shadow off `.bcard` — verified in WebKit, the native engine; the shadowed banner the user saw was 0.3.18 rendering the 0.3.19 offer); sync-liveness wedges fixed (leaked edit-guard self-heals — WebKit fires no blur on re-render removal, which silently blocked ALL adopts + rollover until relaunch; fetches abort at 10s + 60s watchdog); iOS add/edit focus no longer deletes a just-added task on silent @FocusState detach; **iOS morning view DISABLED** (gate commented in TodayView ~line 115, code kept; morningDone untouched so the Mac morning still shows); same-title dedupe for parked Future rows (field state had 'Warren Logo' ×3 — heals on next sync); lvl1/lvl2 legibility tokens (banner, sync error, tab pill, iOS Buddy! pill).
- **Self-diagnosis + self-testing (RULE 3 in CLAUDE.md):** `pnpm diag` — privacy-safe JSONL event log on both platforms (NEVER task text), Rust `append_event`, 1MB rotation — READ IT AT SESSION START. `pnpm sync:live` — two-device live harness against the real backend with a throwaway syncKey; reproduces future→today/undo/dedupe/convergence end-to-end in ~14s, no human needed.
- Tests at wrap: Mac mergeTest 27/27 · syncTest 15/15 · smokeTest 38/38 · ui:smoke · sync:live; iOS 70/70; cargo check clean.

**Open (next session):**
1. **Confirm on-device:** next update banner renders flat (first post-fix banner appears when 0.3.20 ships); diagnostics log starts populating (check `pnpm diag`).
2. **THE PLAN batch 4** (burrs): QR-in-bug-screenshot syncKey leak; weekday XSS escape + CSP; global Backquote shortcut; iOS Done-tab "Today" undo no-op; updater no-recheck-after-failed-install.
3. **THE PLAN batch 5** (hygiene): delete 9 stale docs (SYNC-HANDOFF/RELEASE-UPDATER/DATA-SAFETY leak repo-public details), README fixes, dead-code removal (edge-tab subsystem, renderSkipped, morningUndone, iOS TaskRowView…), .gitignore `*.p8`.
4. Deferred: two-window morning split; token-system PR (memory `buddy-token-system-todo`).

---

## THE PLAN — full adversarially-verified review, 2026-07-08 (evening)

Four specialist review agents (security / stability / design / docs) swept everything published
and live, then an adversarial agent re-verified every claim in code (most confirmed, 4 downgraded,
1 refuted, 4 new finds). PR #80 (Future rows read-only + one shared icon gutter) shipped from the
same session. This section replaces all older "open issues" lists.

### 1 — 🔴 Sync Slice 2: deterministic merge (IN PROGRESS, branch `fix/sync-slice2`)
The revert + overwrite data loss. `merge(a,b)==merge(b,a)` on BOTH platforms: stop using per-pass
`savedAt` as primary; canonical order + content-based winners; tombstone every removal;
unknown-field pass-through (Swift needs an unknown-fields Codable bag). MUST also fix, same seam:
- iOS never rolls over on foreground — only in `init` (TodayView.swift:127) → yesterday-dated blob fights the Mac all morning.
- Swift merge lacks the Mac's lossless carry-history branch (BuddyMerge.swift ~69) → older device's day list dropped.
- "Already archived" rollover branch drops live items with no carry-forward (index.html ~1322 + BuddyStore ~355), both platforms.
- contentKey asymmetry: iOS hashes the full wire (incl. `pinned`, `historyDays`); Mac projects a subset (index.html ~995) → phantom pushes.
- Mac `deleteDeferred` (~2069) writes no tombstone → deleted Future rows resurrect via sync (iOS does this right).
- Sync adopt wipes `restartStash` (+`doneWordBag`) — not carried by `hydratedToWire` (~1003) / `applyHydrated` (~775) → "Restore your last list" unrecoverable.
- Verify on two real devices (human-gated; browser + unit vectors first — SAME test vectors on both platforms).

### 2 — Data-safety batch (small fixes, big trust)
- iOS: corrupt/unreadable store file → default empty state is auto-SAVED 0.25s later, wiping the file. Set the bad file aside as `.corrupt`, add a `.bak` layer (BuddyStore ~408).
- iOS: `adopt()` runs on every 1.5s poll pass with no `editingId` guard → mid-typing clobber (SyncEngine ~98; Mac guards at index.html ~1022).
- After-merge clamp can orphan a "Sent to today!" row: if the linked today item is deduped/capped away, `sentTid` dangles (index.html ~840 vs ~1424). Reconcile sent rows after clamp.
- Mac `save_state`: fsync file + dir before/after rename (lib.rs ~599) — power cut can zero primary AND recovery.
- `fileSave()` fire-and-forgets the durable write with no `.catch` (~667); tray Quit `app.exit(0)` skips the 250ms save debounce → flush-then-quit.

### 3 — Legibility batch (RULE 1 violations, one token-compliance PR)
- Update banner: hardcoded `text-black`/`bg-black` on `.bcard`, which turns red at lvl2 → black-on-red (index.html ~290–303).
- `#syncError` is red-on-red at lvl2 (inline `color:var(--red)` in the settings sheet, ~407). iOS SettingsView:87 same bug + wrong red (#e5474c vs token #e5484d).
- History segmented pill hardcodes `bg-white text-[#1a1a1a]` instead of `--sel-bg`/`--sel-ink` (~2083); iOS mirrors it (incl. a literal `lvl2 ? .white : .white` no-op).
- iOS morning Buddy! pill misses the lvl1 red — theme already exposes selBg/selInk (MorningView ~178).

### 4 — Confirmed bugs & burrs (fix opportunistically)
- Mac polls Supabase every 1.5s ALL DAY while the drawer is tucked (visibilityState never trips; ~57k req/device/day) — pause when tucked (index.html ~3258).
- Bug-report screenshot captures `#drawer` including an open pairing QR = uploads the raw syncKey. Blank `#syncQR` before capture (~3115).
- iOS Done-tab "Today" undo is a NO-OP (`restoreHistoryTask(text:)` dupe-guard matches the done item itself; Mac uses `restoreItem(liveId)`) (HistoryView ~149).
- Stored-XSS hardening: history `weekday` from a synced blob hits `innerHTML` raw (~1731) + `csp:null` in tauri.conf.json. Escape it + set a real CSP. (MED: needs the victim's syncKey.)
- Global plain-Backquote shortcut steals ` system-wide in release builds (lib.rs ~746) — move to a chord.
- Updater: after a failed install the banner never re-checks that session (`if(shown) return`, ~2420).

### 5 — Hygiene sweep (docs + dead code, one PR)
- DELETE stale docs: README-MAC.md, MORNING-REPORT.md, PLAN.md, BETA-SETUP.md, SYNC-HANDOFF.md (leaks live Supabase URL/key/org — values live in `.supabase-buddy.secret`), PARITY-PLAN.md, RELEASE.md, HANDOFF.md, DATA-SAFETY-PLAN.md (real task text), ios/_review/.
- RELEASE-UPDATER.md:142 re-publishes the Apple Key ID + Team ID its own scrub command was written to remove — placeholder them.
- README fixes: sync is live not "not wired up yet"; XcodeGen link → yonaskolb/XcodeGen; "Report a bug" opens a mail draft (endpoint never deployed — BUG_ENDPOINT is still REPLACE-AFTER-DEPLOY).
- Dead code to DELETE: edge-tab subsystem (+`renderDots`), `renderSkipped()`, `#morningUndone`+`renderMorningUndone`/`toggleUndone`, `.todaybadge`, `--chrome-hover`, `.donezo-leaving`, iOS TaskRowView.swift, EscalationTheme.focusFill.
- `.gitignore`: add `*.p8`/`AuthKey_*`; consider un-ignoring pnpm-lock.yaml (public repo).
- styleguide.html badge says v0.2.x; Proposals live only on unmerged `feat/styleguide-proposals`.
- Close draft PR #61 (superseded). Typography drift (four 14px trackings, Skip 15 vs 16) → fold into the token-system PR.

### Consciously NOT fixing
Bug-report endpoint hardening (never deployed — harden if/when deploying); done-word cross-device
divergence (cosmetic); positional history-id collision (deterministic archival makes it moot);
"infinite CAS loop" (REFUTED — the contentKey noop guard catches it after one round).

## Session summary — 2026-07-08 — morning-window rebuild, sync convergence attempt (STILL BROKEN), many releases

Very long session, Mac `0.3.4 → 0.3.17` + iOS TestFlight `0.1.0 (12)→(13)`. Every fix was verified where possible by running the app (`pnpm tauri dev` + `screencapture`); AppleScript keystrokes/Quartz are blocked in this harness, so tiling/drag and cross-device sync need the USER to confirm.

**Shipped + verified (high confidence):**
- **Morning is a real window** (0.3.12): decorated, resizable, shadow, min-size 432×600, on the SAME transparent drawer window via objc2 (`set_morning_mode`/`morning_window_chrome`). See memory `buddy-morning-real-window`.
- **Morning goes behind other apps** (0.3.13): `setLevel(0)` for morning, `3` for drawer (`set_always_on_top(false)` doesn't reset the level).
- **Morning opens full-screen + is tileable** (0.3.17): retired the buggy geometry-memory (its save raced the native re-chrome → off-screen/tiny windows); strip `CanJoinAllSpaces|FullScreenAuxiliary` during morning so Rectangle/Magnet/green-button treat it as normal (`collectionBehavior=Default`). Verified: 3456×2174 full frame + behaviour=0.
- **App icon** = proper macOS squircle (0.3.10), regenerated from `ios/.../icon-1024.png` via `pnpm tauri icon` (may need a Finder icon-cache clear to SEE it). Memory `buddy-native-only-visual-bugs`.
- **⌘⌥⌃M** always brings morning forward (global shortcut raises the window first) (0.3.14).
- **Updater banner** now reveals the drawer so it's visible (0.3.15) — but "verified" was overstated (it was already visible with the drawer open; no manual "Check for Updates" button exists). Memory `buddy-updater-banner-in-drawer`.
- **"Sent to today!" on Mac** (0.3.11) — verified in-browser.

**🔴 STILL BROKEN — sync convergence (do FIRST next session):**
- On Mac 0.3.17 + iPhone 13 (both have the parity code), sending a Future item to today **flashes "Sent to today!" then reverts**, AND the today items already there get **OVERWRITTEN / lost — DATA LOSS.** Slice 1 (align iPhone model + order-independent content-key, 0.3.16) was INSUFFICIENT exactly as the adversarial review warned: the merge is still **non-deterministic** (always-local-primary via per-pass `savedAt`; array-order/clamp survivor divergence). **Fix = the deterministic/symmetric merge (Slice 2) on BOTH platforms + unknown-field pass-through.** Full detail in memory `buddy-sync-convergence`.

**Other open Buddy issues reported 2026-07-08:**
- **Future items editable but broken** — clicking a Future row's text makes it contentEditable but you can't edit; user wants Future rows NOT editable. Remove the `mousedown→contentEditable` + blur handler in `renderFuture` (`dist/index.html` ~1977).
- **Future tab +/× icons right-aligned wrong** — should line up with the history panel's `×` close button (top-right gutter). Fix the `pr-[72px]`/absolute-right offsets in `renderFuture`/`buildSentFutureRow`.

**Deferred (deliberate):**
- **Two-window split for morning** — the REAL architecture fix (dedicated opaque decorated window; drawer stays its own). Ends the morning-window regression treadmill + gives reliable frame memory (macOS autosave). Adversarial-reviewed, ranked plan in memory `buddy-morning-real-window` context / the review transcript.
- **Sync Slice 2** (deterministic merge + unknown-field pass-through) — also the version-skew-safety the user wants (ship Mac/iPhone on different versions).
- **iPhone drops `doneWord` + `historyDays` on sync** (pre-existing minor data loss).

**Next session:** (1) FIX sync — Slice 2 deterministic merge (the revert + overwrite/data-loss); (2) remove Future-item editability + fix +/× alignment; (3) then the two-window morning split.

---


## Session summary — 2026-07-05 — merge cap+dedupe fix, sync-UI tweak, 0.3.3 shipped via CI

- **Merge cap + dedupe fix (the known bug).** Cross-device merge unioned both devices' active lists and never re-clamped, so Mac(6)+iPhone(new) → 8 rows with same-title dupes (seen live: two "Check on Anthropic bill"). New `clampActiveItems()` runs after every same-day merge on **both** platforms (`dist/index.html` + `ios/.../BuddyMerge.swift`): keep all done items, drop same-title active dupes (newer device wins), cap active at `HARD_CAP`. Deterministic → devices converge, no ping-pong. Tests: Mac `mergeTest` **18/18** (+3), iOS `BuddyTests` **51/51** (+2).
- **Sync-settings tweak.** "Synced HH:MM" moved to the right of Unlink/Resync, one type step down (15→14px). Stays legible on the lvl2 red sheet via the existing `.lvl2 #settings [class*="text-black"]` override.
- **Shipped as Mac 0.3.3 (via CI).** `feat/ios-sync-live` (the whole iOS companion + live sync, 42 commits) merged to main (PR #62, squash) → bump bot → **`gh workflow run "Release Mac app"`** built + published v0.3.3 with DMG + `Buddy.app.tar.gz` + `latest.json`; `releases/latest` resolves to v0.3.3. **Correction to prior belief:** CI *can* cut the signed release from main via manual dispatch — local notarization only needed for code not yet on main (like 0.3.2). See memory `buddy-0-3-2-release`.
- **Still open:** iPhone TestFlight distribution to the 2 friends (public link needs Apple beta review — user will do later). Confirm 0.3.3 on-device.

---


## Session summary — 2026-07-04 — Mac⇄iOS polish, staged sync UI, adaptive row fitting

Long session refining the synced Mac + iPhone apps against live testing. Branch `feat/ios-sync-live`.

**Shipped / done + verified:**
- **Mac 0.3.2 released** (signed+notarized, local build from the branch): Done-page **jitter fix** (poll no longer re-renders on no-change), **grey day headers** (not chrome→no red at lvl1), **Skipped tab removed** (Future · Done), **staged sync UI** (setup → pairing/QR → linked with **Unlink / Resync**; Resync mints a fresh syncKey = clean bucket), **pairing-QR redraws** on every Settings open.
- **iOS through TestFlight `0.1.0 (11)`**: sync-settings + date-baseline alignment (killed a stray `+12` hack), one 32pt gutter everywhere (close ✕ / weather / row icons), Future `+`/`×` always shown, Done-tab **revert** icon, **rollover carries all 6** (was 5), Skipped removed, **tap-to-edit focus fix** (deferred focus — kept text + cursor lands), bottom bar hides while editing.
- **Adaptive row fitting — one engine both platforms** (`RowFit` iOS, `fitWrap` Mac): largest uniform font where every row's real wrapped text fits → compress padding then font → floor (Mac 15 / iOS main 16 / morning 22→16) → scroll only as last resort; clip-safe by construction. **Fixed the iOS morning scroll** (was a ScrollView + fixed 120pt rows). Verified 6 multi-line tasks fit on Mac drawer, iOS main, iOS morning.
- **Tests:** iOS **49/49**, Mac browser smoke **35/35**.

**KNOWN BUG (unfixed — do first next session):** the **sync merge can exceed the 6-task cap and creates duplicates**. The `HARD_CAP` is only enforced on manual Add; `mergeWire`/`mergeHistory` union both devices' active lists and never re-clamp, so Mac(6)+iPhone(different) → 8 rows with dup titles (seen live: two "Check on Anthropic bill"). **Fix:** after a merge, clamp active list to 6 + dedupe by title. Contained change in the merge logic (dist `mergeWire` + iOS `BuddySync`), NOT the fit code.

**Also parked:** installed-app vs dev-build **localStorage split** — pairing/config lives per-origin (`WebKit/buddy` dev vs `WebKit/fyi.whale.buddy` installed), so updating the installed app showed "Off" until re-paired (backend URL/key are in `.supabase-buddy.secret` / `SYNC-HANDOFF.md`). Not a bug, but worth a note in onboarding.

**Next session:** (1) fix the merge cap+dedupe bug; (2) cut **Mac 0.3.3** so the installed app gets adaptive fit; (3) confirm TestFlight `0.1.0 (11)` feels right on the real phone.

---

_Historical: 2026-06-30. Branch `main`. Released **`0.3.1`** — history split into three tabs (Future · Done · Skipped) + Future turned into a manual holding pen. Signed/notarized, published via a manual `Release Mac app` dispatch (the in-app updater delivers it). `AUTO_RELEASE_MAC` stays **OFF** — a manual `gh workflow run "Release Mac app"` publishes anyway (workflow_dispatch bypasses the gate); no need to flip the var. Open work: the de-inline-styles / token-system follow-up (memory `buddy-token-system-todo`)._

Buddy is a shipped, public, self-updating macOS menu-bar focus app for ADHD.
Repo: `github.com/whale/buddy`.

## Session summary — 2026-07-02 — iOS visual parity (branch `fix/ios-visual-parity`, pushed, no PR)

Rebuilt the **iPhone** app UI to match the Mac drawer's design language (it had drifted:
system font, one card, native iOS nav/list/form chrome). Bundled **Geist** (static OTFs) +
a `Font.geist()` helper; rebuilt **TodayView** as two floating Geist cards (chrome row +
numeral-left date block; Donezo-on-top / active / Add rows; clean text rows with
tap=complete, long-press=edit/sleep/remove; escalation lvl0/1/2 via theme tokens); rebuilt
**Settings** and **History** as custom Buddy sheets (no native Form/List — the 👍🏼…🦜 slider,
the [Future|Done|Skipped] segmented history); restyled **MorningView**. Added store methods
`restoreHistoryTask` / `wakeDeferredTask`. Added a DEBUG `-uiFixture` screenshot harness for
deterministic captures. **All 37 iOS unit tests pass.** Review artifact:
`ios/_review/comparison.html`. Latest commit on the branch: `62328c4`. **Not merged; no PR.**
Known deltas + follow-ups are listed in comparison.html and `ios/_review/PROGRESS.md`.
## Session summary — 2026-07-01 — done-word shuffle bag (PR #60, open, not released)

**The bug (tester report).** A tester completed several tasks and the celebration labels (Donezo!, Ticked Off!, …) came out patterned, not random — Donezo / Ticked Off / Donezo / Ticked Off.

**Root cause.** The done word was derived from a **hash of the task's `id`**. For sequential ids — history rows (`h-DATE-0, -1, -2`) and the `n1/n2` fallback — the hash marched straight down the 25-word list, so neighbouring completions got neighbouring words. (Random-UUID ids actually spread fine; the bug only bit when ids were sequential.)

**The fix (PR #60, branch `fix/done-word-shuffle`).** Replaced id-hashing with a **shuffle bag**: every word is handed out once before any repeat, then the bag refills and reshuffles. The word is picked **once at completion** and stored on the item (`it.doneWord`) → genuinely spread out AND stable across re-renders. Persist the word per-item + the bag; survives sync (items pass through `mergeItems` whole). **Backfill at boot** heals already-completed tasks so an existing list re-shuffles immediately. Legacy hash kept only as a fallback for past-day history rows with no stored word. All in `dist/index.html`.

**Verified (browser, port 8899).** `smokeTest` — all completion + done-word assertions pass; the lone failure ("hit targets") fails identically on the **unmodified baseline** (headless hover-button quirk, not this change — confirmed by stashing the edits and re-running). Shuffle bag: 55 consecutive completions → first 25 all distinct, next 25 all distinct, order scrambled. lvl2 red state screenshotted — 4 done rows, words varied and legible in light-on-red (no hardcoded-dark regression). **Not on-device-verified** (browser only).

**Not released.** `AUTO_RELEASE_MAC` stays OFF; PR #60 is open, awaiting merge into the next batched release.

## Session summary — 2026-06-30 (later) — Future/Done/Skipped tabs + Future holding pen (shipped 0.3.1)

**The problem.** The **Done** tab showed both completed *and* skipped past tasks (each past day's `done:true` *and* `done:false` items), so skipped work polluted the "done" list — no clean view of what was actually finished.

**The change (PR #58, released 0.3.1).**
- **Three history tabs** — `Future · Done · Skipped` (was `Future · Done`). `renderPast` now filters to `done:true` only; new `renderSkipped` renders past `done:false` tasks; shared `histLoadMore()` helper. Third segment added to the tab pill (`px-5`→`px-4` so three fit).
- **Future is now a manual holding pen.** Removed the `wakeDeferred()` auto-return path entirely (the call in `rolloverAndCarry` + the function). Parked tasks no longer come back on rollover — pulled in with **+**, removed with **×**, edited by clicking the text (mousedown→contenteditable, empty deletes), mirroring the live list. Flat list, newest-parked on top (dropped the now-meaningless "Tomorrow/Monday" wake-date grouping). Added `addDeferredToToday()`.
- **Cap rule everywhere:** every **+** (Future *and* Skipped) hides at `HARD_CAP` (6 active / full red), so a day can't overflow.
- Renamed the list-row **"Sleep till tomorrow" → "Move to Future"**; removed dead `EDIT_SM` icon; `deleteDeferred` now persists.

**Verified.** Browser `smokeTest` **39/39** (updated for the new model — old "rollover wakes deferred" assertion became "holding pen: parked tasks do NOT auto-return"; added Done-vs-Skipped separation + Future-`+` assertions). Full visual sweep of all three tabs at **lvl0 / lvl1 / lvl2** — all adaptive-token legible, `+` correctly hidden on full-red. Click-to-edit on Future verified (editable-on-click, save-on-blur, empty-deletes). Release **v0.3.1** published with DMG + `Buddy.app.tar.gz` + `latest.json`; workflow succeeded. **Note:** the auto-bump bot ticked `0.3.0` → **0.3.1** on merge (it always +1's the patch), so the feature shipped as 0.3.1.

**Alpha-tester onboarding (asked at end of session).** Buddy is already distributable to a tester with **zero extra setup** — signed + notarized (opens cleanly on other Macs, no Gatekeeper block) and the repo is public with a working auto-updater. To onboard one tester: (1) send the direct DMG link `https://github.com/whale/buddy/releases/download/v0.3.1/Buddy_0.3.1_universal.dmg`; (2) tell them it's a menu-bar + right-edge app (so they know where it went); (3) "just text me" is a fine feedback loop for n=1. Requirement: **macOS 13 (Ventura)+**. First run may show a one-time "downloaded from the Internet — Open?" dialog (normal; notarized, so no hard block).

## Session summary — 2026-06-30 — full-screen-Spaces fix + reliable updater (shipped 0.2.47, on-device verified)

**The bug.** User was stranded on `0.2.39` (no update banner), and on launch Buddy would "flash up
then hide behind other windows," with the tray "Show / Hide" doing nothing. They work with apps in
**native full-screen**.

**Two wrong guesses first (the lesson).** Assumed z-order / focus loss; shipped `set_focus` +
`alwaysOnTop` juggling (released as 0.2.46) — wrong premise, didn't help. Turning point: *ran the real
app and inspected the live window* (`CGWindowListCopyWindowInfo` via a throwaway Swift script) — the
window was already at floating **layer 5**, so it could never be "behind" a normal window. **Inspect
live runtime state before designing a fix.**

**Real root cause + fix (0.2.47, PR #55).** The window is `alwaysOnTop:true` by config, but a floating
window **can't draw over an app in native full-screen mode** unless its `NSWindow.collectionBehavior`
opts in. Fix: `collectionBehavior |= CanJoinAllSpaces | FullScreenAuxiliary` at launch
(`allow_over_fullscreen` in `src-tauri/src/lib.rs`, via new `objc2` / `objc2-app-kit` deps). Verified
live: behaviour == **257**. Reverted the mis-aimed `nativeFit` always-on-top block from 0.2.46.

**Second bug, exposed by the first — the updater stranding (same PR).** The in-app updater checked
**once** ~2.5s after launch and **swallowed errors silently** → one miss = stuck a full version behind
with no signal (how 0.2.39 missed 0.2.46). Now checks at launch, **every 3h, and on window focus**
(throttled 1/min, stops once a banner shows), and `trace()`s failures into the bug-report logs.

**Delivery gotcha.** The updater was itself the broken link, so it couldn't deliver its own fix — had
to install the signed build **directly** (drag the DMG) once. After 0.2.47, normal in-app updates resume.

**Verified:** full-screen behaviour confirmed by the user in their real setup; `over-fullscreen
behaviour set: NSWindowCollectionBehavior(257)` in the launch log; browser `smokeTest` **35/35**;
installed `0.2.47` is **signed + notarized** (`spctl` → "accepted, Notarized Developer ID") and running
on-device. Full writeup in `JOURNAL.md` (PR #56, `[skip release]`). **Releases 0.2.46 & 0.2.47 both
published; `AUTO_RELEASE_MAC` flipped back OFF.**

## Session summary — 2026-06-26 (evening) — data-loss fix shipped + Done-tab/UX overhaul (batched, unreleased) + token-system spec

**Released 0.2.39 (PR #44): overnight task-loss fix.** Root cause traced from the user's on-disk
state: "Restart Buddy" stashed the list in a RAM-only var → dismissing the morning / relaunching
lost it, and three backup layers all failed (recovery file overwritten because leftover tombstones
made an empty-today look "recoverable"; `.bak` only healed an *unparseable* primary, not a valid-empty
one; the empty-over-full guard lived only in the sync path). Six safety-only fixes: Restart now
persists its stash + tombstones what it clears; Rust recovery-file ratchet; `load()` heals from `.bak`
+ won't overwrite a fuller `.bak`; `.bak` added as a boot-reconcile source; the **live midnight
rollover** now carries unfinished forward + wakes deferred (shared `rolloverAndCarry()` with boot —
previously only boot did, so leaving Buddy open across midnight dropped the working set); smokeTest
cases for all of it. The user's 4 lost tasks were recovered from the `.bak`. smokeTest 24/24.

**Merged but NOT released** (all in `main`; `AUTO_RELEASE_MAC` flipped OFF to batch them):
- **#45** weather stroke 2→1.4; **Skip/Buddy! hover fixed** (an inline `style=color` was defeating the `:hover` rule; Buddy! now *darkens* on red, not lightens); RULE 2 gained an every-color+interactive-state clause.
- **#46** Done tab now shows skipped/undone past tasks with a **↩ restore-to-today** arrow; removed the side-drawer restore row (morning restore untouched).
- **#47** Done tab shows **one week + "Load more"**; dropped the vestigial `historyDays` setting.
- **#48** the "Donezo." label now **rotates through 25 phrases** (deterministic per task id; Title Case + "!").
- **#49** added **`styleguide.html`** (tokens / components / state matrix / discrepancy audit).
- **#50** interaction change: **complete via a checkmark icon** in the hover action column (was tap-to-cycle), **edit by clicking the task text** (pencil removed; goes editable on mousedown so one click works), **removed the "now"/focused state**, solid action icons, weather icon **44→50px** (Figma node 17:78).

**⚠️ Release state — READ BEFORE MERGING ANYTHING:** latest published = **0.2.39**. Everything after it
is merged into `main` (~0.2.43) but **unreleased** by design — the user wants to review the batch first.
`AUTO_RELEASE_MAC=false` is the guard (merging won't publish). To cut the single release after review:
`gh variable set AUTO_RELEASE_MAC --body true` → `gh workflow run "Release Mac app"` → confirm `gh release list`.
Gotcha: `gh pr merge --squash` drops a `[skip release]` PR-title tag (uses the commit msg), so the **var**
is the real guard, not the tag. (Memory: `buddy-release-squash-gotcha`.)

**Not built yet — the design-token system** (designer-approved; visual spec in the styleguide's
"⚐ Proposals" section on the **unmerged** `feat/styleguide-proposals` branch; full spec in memory
`buddy-token-system-todo`): OKLCH hover `--red-hover: oklch(from var(--red) calc(l-.05) calc(c+.05) h)`
(darker *and* more saturated — a black veil goes muddy), type scale 16→15 / 13→14, icon weights
≤20px→1.8 / weather→1.4, and de-inlining every render-time `style="color:…"` into utility classes.
This is the next PR.

**Verified:** every PR via `__buddy.smokeTest()` + an lvl0/lvl1/lvl2 visual sweep; the single-click
edit confirmed with a real mouse click. **NOT verified:** none of the post-0.2.39 work has been in a
**native build or on device** — only the browser preview. The lone smokeTest "hit targets" failure is a
known headless artifact (30px hover icons under a parked Playwright mouse), not a regression.

## Session summary — 2026-06-26

Shipped a **critical click-blocking fix** as **0.2.38** (PR #42, merged → auto-release).

### The bug (regression introduced 2026-06-25 in `bef4a7d`, shipped in 0.2.37)
The Fade+Drift refactor changed the *closed* settings sheet from `translateY(100%)`
(fully off-screen) to `translateY(22px); opacity:0` (invisible, in place) but **forgot
`pointer-events:none`** — the same line it correctly added to `#drawer` and `#morning`.
Result: an invisible `z-20` `#settings` sheet blanketed the whole list panel (Card 2)
and **swallowed every click** — the Future/Done history toggle **and** task rows. So in
0.2.37 you couldn't complete tasks or switch to the Done view; the disc/gear/pin in the
header (Card 1) still worked because they sit outside the sheet. User reported it as
"my dones are gone" + "the toggle doesn't work."

### The fix (4 lines, `dist/index.html`)
- `pointer-events:none` on `.sheet[data-open="false"]` (normal **and** reduced-motion variants).
- History toggle buttons: `min-height:38px` (inline style — was ~22px) + `px-5`,
  `grid place-items-center`. NOTE: a brand-new arbitrary Tailwind class (`min-h-[38px]`)
  does **not** work here — this dist uses a **precompiled** Tailwind stylesheet, so only
  classes present at build time exist. Use inline style or existing utilities.

### Verified (browser, served `dist/` via Playwright real clicks)
- Real click on closed-sheet build **timed out** (blocked by `#settings`) → after fix it **lands**.
- Closed sheet computes `pointer-events:none`; toggle pill is 38px tall; realistic tap zone **15/15**.
- `smokeTest`: no new failures (the lone pre-existing hit-target flag fails identically on `main`,
  an artifact of running the audit via Playwright vs `pnpm ui:smoke`).

### Not verified / open
- **0.2.38 release**: was `in_progress` at wrap. Confirm it **published** (DMG + tarball + latest.json)
  and that installing it actually restores clicking in the running app.
- The 0.2.37 on-device items still pending (live weather fetch, 30pt top padding, Fade+Drift feel).

## Session summary — 2026-06-25

A long build session. Shipped **6 public releases** (0.2.32 → 0.2.37). The auto-release pipeline is now fully working end to end.

### Completed & shipped (all on `main`, released in 0.2.37)
- **Restart-to-fresh:** "Restart Buddy" stashes the current plan and shows a blank morning with a "Restore your last list" row.
- **Fade+Drift motion (app-wide):** unified show/hide style (fade + small drift + slight scale, ease-out, `--t-drift` = .48s) on the drawer, morning leave, settings/history sheets, and update banner. Micro-interactions (row add, Donezo, crossfade, confetti) left as short ease-out fades. Started as a morning→drawer handoff animation, then unified per user pick of "Fade + Drift".
- **Font → Geist** (self-hosted variable woff2, SIL OFL; Inter removed).
- **Weather date header** (per Figma): number left, weekday/month stacked, weather icon right, 32/26/32 spacing, baseline-aligned via `.tbt` (text-box-trim). Live weather: IP (ipwho.is) → Open-Meteo (no key) → 13-icon **Lucide outline** set (`WX_ICONS`/`wxKey`), day/night aware, cached 1h, fails silently. Applied to morning + drawer headers.
- **History:** store ~1 year (`pruneHistory`, RETENTION_DAYS=365), show a fixed **14-day** Done window for everyone (`HISTORY_DAYS=14`). Removed the per-user "days of history" slider.
- **Settings:** "Give Buddy room" pin label (was "Reserve space when pinned"); done-task count beside Export (`#exportCount`); Quit/Restart as matching pill buttons; removed the green auto "Update available" indicator AND the manual "Check for Updates" (the banner is the only update path); removed "Improve weather location" (see below).
- **Notch top padding:** window top inset `MENUBAR` const (currently **30pt**) so the drawer's top gap matches the bottom on notch Macs. Tuned by eye.
- **Release workflow protocol:** "ship it" → public signed release; "just land it" → `[skip release]` in the commit skips bump+release (added to `.github/workflows/version-bump.yml`).

### Verified this session
- `pnpm ui:smoke` passes (incl. the hit-target audit, now skips `pointer-events:none`/`opacity:0`).
- **v0.2.37 published** — signed, notarized, with DMG + `Buddy.app.tar.gz` + `latest.json` (version 0.2.37). The full auto-pipeline (version-bump → release-mac) works; `AUTO_RELEASE_MAC=true` and all 9 signing secrets present.
- The in-app updater works end to end (user updated across multiple releases).
- Browser-verified: header layout/baseline, weather-icon mapping (injected codes), settings layout, drawer drift states, export count, Done 14-day window.

### Not verified / open
- **Live weather fetch** (ipwho.is → Open-Meteo) only verified with *injected* weather codes — the real network fetch + correct local conditions need confirming in the running app. Fails silently if it doesn't work.
- **Native feel** of Fade+Drift and the **30pt top padding** are eyeball estimates — confirm on-device; both are one-token/number tweaks (`--t-drift`, `MENUBAR`).
- **Precise weather location** deferred: a Tauri/WKWebView app can't reach macOS location via `navigator.geolocation` (returns PERMISSION_DENIED with no prompt). Would need native CoreLocation (Rust) if revisited. IP-based already follows travel.

### Gotcha worth remembering
- **Apple notarization 403 "agreement missing/expired"** blocked two release builds. Apple periodically re-issues the Developer Program agreement; the account holder must re-accept at developer.apple.com/account, then re-run `gh workflow run release-mac.yml`. Not a code/credentials problem.


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
