# Buddy sync — Mac ⇄ iOS — execution plan (2026-07-02)

## ⏱ PROGRESS — resume here (updated 2026-07-03)
Branch: **`feat/ios-sync-live`** (off `fix/ios-visual-parity`, pushed). Latest: `380ff78`.
- ✅ **P0 — backend up + CAS SQL 7/7.** Local Supabase running. Migrations applied.
- ✅ **P1 — iOS live adapter, VERIFIED LIVE.** Salvaged `SupabaseCASStore.swift` +
  `SupabaseSyncLiveTests.swift` from feat/sync-live; ATS `NSAllowsLocalNetworking` added.
  All 3 live tests **actually ran** (not skipped) & passed against the live server.
- ⏭ **NEXT = P2** (wire auto-sync into `BuddyStore`), then P3 (Settings opt-in UI),
  P4 (Mac `dist` supabase-js adapter — re-integration, re-run smokeTest+red sweep),
  P5 (Mac-app ↔ iOS-sim round-trip), P6 (QR), P7 (hosted Supabase — user step).
- ⚠️ **Remember P2/P3 must-fixes from the review:** validate sync key is full 43-char
  base64url (blank key = shared bucket); add `scenePhase==.active` pull; surface sync
  failure (don't stamp a false "synced at"); dirty-flag re-arm during in-flight sync.

**To resume the backend** (if OrbStack/Supabase was stopped):
    orb start && cd ~/Projects/buddy && supabase start
    # local publishable key: sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH  · API: http://127.0.0.1:54321
    # re-run live tests: cd ios && xcodebuild ... test -only-testing:BuddyTests/SupabaseSyncLiveTests

---


## Goal
Live sync between the Mac app and the iPhone app: add/complete/edit/delete on one shows up
on the other. Opt-in, local-first by default (per IOS-COMPANION-PLAN.md, locked design).

## Current state (verified)
- **DONE (on this branch, from `main`):** the whole engine — `BuddyMerge.merge` (commutative,
  tombstones, per-item version), `BuddySync.syncOnce` (pull → merge → CAS push → retry,
  empty-over-full guard, content-key no-op), `SyncIdentity` (generateSyncKey/deriveOwnerId),
  `SyncWire` (s↔ms timestamp normalization). Mac mirror in `dist/index.html`. CAS SQL
  (`buddy_pull`/`buddy_push`, dumb atomic store, server owns version). All unit-tested (37 iOS tests).
- **DONE but STRANDED on `feat/sync-live` (stale, pre-parity UI):** the LIVE network adapters —
  `ios/.../Sync/SupabaseCASStore.swift` (URLSession → Supabase RPC), `SupabaseSyncLiveTests.swift`,
  `supabase/tests/buddy_cas_test.sql`, and the Mac supabase-js adapter + wiring in that branch's `dist`.
  Commit history says "verified live end-to-end" there.
- **NOT done:** integrating the live adapter into the CURRENT (parity) code; wiring auto-sync into
  the store on both apps; the Settings opt-in UI; QR pairing UI; a running backend; a real round-trip.
- **Tooling present:** `supabase` CLI, `docker`, `orb` (OrbStack). Local Supabase is runnable.

## Strategy — SALVAGE, don't rebuild
The adapter code on `feat/sync-live` is proven; its UI is obsolete (I rebuilt it for parity).
Port the SYNC files forward onto a new branch off the parity branch; re-wire into the current
store/Settings; verify against a local Supabase; leave a hosted backend as the only user step.

Branch: `feat/ios-sync-live` off `fix/ios-visual-parity`.

## Decisions (defaults; flag for review)
- **Identity v1 = manual key paste** (URL + anon key + sync key), with **QR pairing as P6 follow-up.**
  Rationale: unblocks a working round-trip now; QR is UX sugar over the same key. (Plan LOCKED QR as
  the eventual method — manual is its documented fallback.)
- **Backend for verification = LOCAL Supabase** (`orb` + `supabase start`) reachable by the Mac app
  and the iOS *simulator* on `127.0.0.1`. A **real iPhone** needs a hosted (or LAN) backend → user step.
- Secrets: sync key in the iOS Keychain / Mac secure storage; URL + anon key in settings (anon key is
  publishable by design). Nothing committed.

## Build order (each step independently verifiable)
- **P0 — Backend up.** New branch. `orb` running → `supabase start` → `supabase db reset` applies both
  migrations. Run `supabase/tests/buddy_cas_test.sql` to prove CAS correctness (first-insert needs
  expected=0; CAS conflict returns current; version increments server-side). STOP: CAS SQL green.
- **P1 — iOS adapter.** Port `SupabaseCASStore.swift` + `SupabaseSyncLiveTests.swift` from
  `feat/sync-live`; reconcile against the current `BuddySync`/`SyncSnapshot`. Point live tests at
  local Supabase. STOP: iOS ↔ server round-trips in a test.
- **P2 — iOS store wiring.** A `SyncConfig` (url, anonKey, syncKey) persisted (Keychain for the key).
  `BuddyStore`: pull-on-launch, debounced push-on-change (2–5 s), adopt merged result, "synced at"
  stamp. No-op when unconfigured (local-only default preserved). STOP: toggling config makes the sim
  push/pull against local Supabase.
- **P3 — iOS Settings opt-in.** A Buddy-styled "Sync" section: paste URL + anon key + sync key,
  enable toggle, "synced at HH:MM". STOP: configure from the UI, see it sync.
- **P4 — Mac wiring.** Port the supabase-js CAS adapter + sync loop + opt-in Settings fields from
  `feat/sync-live`'s `dist` into the CURRENT `dist/index.html`; "synced at". STOP: Mac pushes/pulls
  against local Supabase.
- **P5 — LIVE ROUND-TRIP (local).** Same sync key on Mac app + iOS sim against local Supabase:
  add on Mac → appears on iOS; complete on iOS → reflects on Mac; delete (tombstone) and erase
  propagate; two-device same-day edit merges (no lost edit). STOP: all scenarios pass.
- **P6 — QR pairing (follow-up).** Mac renders a QR of `{url, syncKey}`; iOS camera scan fills the
  config. Manual paste keeps working. (Needs camera permission string.)
- **P7 — Hosted backend (USER STEP).** For a real iPhone (not on localhost): create a free Supabase
  project, `supabase db push` the migrations, paste the project URL + anon key. Dead-simple steps to
  be written for the user.

## What needs the user
Only P7: a hosted Supabase project (free tier) + its URL/anon key, for syncing to a *physical* phone.
Everything through P5 is verifiable locally by me (Mac app ↔ iOS simulator on localhost).

## Review incorporated (v2 — second-agent pre-flight)
- **Salvage = `git checkout feat/sync-live -- <files>`, NOT hand-port.** Verified byte-identical:
  `BuddySync.swift` diff is empty; the adapter references only current types. No reconcile needed.
- **P1 gate fix:** the 3 `SupabaseSyncLiveTests` SKIP silently when the backend is down. Gate on them
  having ACTUALLY RUN against the live local Supabase (assert not-skipped), else "green" proves nothing.
- **Port the ATS exception** (`NSAllowsLocalNetworking` / ATS dict) into `project.yml` + `Info.plist`,
  or the sim can't reach `http://127.0.0.1:54321`. It's on feat/sync-live; bring it forward in P1.
- **Security wording corrected:** protection is a **bearer-capability** — `buddy_pull/push` are
  `SECURITY DEFINER` and take `owner_id` as an argument, so **RLS is bypassed** (it only blocks direct
  table enumeration). The `owner_id` (= sha256(syncKey)) is an unguessable bearer token on every request.
  Don't tell the user "RLS protects you." No server-side rate-limit (256-bit key makes brute force moot).
- **Validate the sync key (P2/P3, both apps):** reject empty/short — require full 43-char base64url —
  BEFORE enabling sync. `deriveOwnerId("")` is a constant hash → a blank key dumps everyone into one
  shared bucket (cross-user leak). Guard on the client.
- **P0.5 golden cross-decode** (new, before wiring both apps): assert a fixed Mac blob decodes via iOS
  `SyncWire.toSnapshot()` and a fixed iOS blob decodes on the Mac, equal — front-load the ms/s risk.
- **Debounce dirty-flag:** an edit during an in-flight sync must re-arm on completion (Mac `scheduleSync`
  returns early while `syncing`); mirror on iOS.
- **iOS foreground pull:** add a `scenePhase == .active` pull (Mac pulls on window focus); launch+change
  alone won't show the Mac's edits.
- **Surface failure:** `syncOnce` returns ok:false after 5 retries / throws on non-2xx — don't stamp a
  reassuring "synced at" on failure; catch + log + retry next trigger; show a real error/last-sync state.
- **Erase + clock skew** is the one wall-clock edge (`savedAt < erasedAt` cross-device) — accept but
  add to the P5 scenarios (erase on the lagging-clock device).
- **P4 is re-integration, not copy-paste:** re-find the `writeNow`/`bootFinish`/focus hooks in the CURRENT
  dist (it changed since feat/sync-live), and re-run `__buddy.smokeTest()` + red-state sweep (RULE 2).
- **`pinned`**: iOS emits `pinned:false` (not in SyncSnapshot) — ensure the Mac preserves its own pin
  rather than adopting the merged blob's. Desktop-only, low stakes.
- **Scope the "verified" claim:** local round-trip proves protocol/wire/merge, NOT real-device
  reachability, production HTTPS, network-failure resilience, background sync, or camera QR.

## Risks / gotchas
- **Wire-format lockstep** Mac ↔ iOS ↔ SQL: epoch **ms** on the wire; iOS `SyncWire` converts. Any
  drift silently corrupts merges. Re-verify with a cross-app blob.
- **RLS**: `owner_id` = derived sync key scopes every row; anon key alone can't read another owner.
- **Empty-over-full guard**: a fresh phone must pull-before-push (scanner-pulls-first) — already in
  `syncOnce`; confirm on first pairing.
- **Local vs device reachability**: `127.0.0.1` works for the sim, not a real phone — hence P7.
- **Don't bloat the parity PR**: sync is its own branch/PR.
