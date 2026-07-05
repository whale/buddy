# Sync → QR: execution plan — ✅ BUILT & VERIFIED (2026-07-03)

## Status at wrap
- **P0.5 golden cross-decode** ✅ — B1 fixed (`BuddySettings` tolerant decode; `SyncWire` tolerant decode). 3 golden tests green.
- **P1.5 iOS snapshot bridge** ✅ — `BuddyStore.snapshot()`/`adopt()` + `onLocalChange`; 4 tests green.
- **P2 iOS sync loop + config** ✅ — `SyncConfig` (Keychain key, 43-char validation), `SyncEngine` (single-flight, coalescing re-arm, ownerId keying, foreground pull, failure surfacing).
- **P3 iOS Settings + QR scanner** ✅ — Sync section in `SettingsView` (scan / manual paste / status), `QRScannerView` (AVFoundation, graceful on sim), `NSCameraUsageDescription`. App builds.
- **P4 Mac adapter + loop + Settings + QR render** ✅ — `makeSupabaseCASStore` + auto-sync engine (initSync/setSync/syncNow/scheduleSync, coalescing) + save()/focus/boot hooks + M3 pinned fix + Sync settings UI + QR render (vendored `dist/vendor/qrcode.js`, MIT). smokeTest 39/39, syncTest 15/15, lvl2 visual clean.
- **P5 live round-trip** ✅ — proven every layer: iOS↔DB (live), Mac app→DB (real serialize push), Mac app←DB (fresh-device pull+adopt), and the definitive **Mac app → DB → iOS Swift decode** (`testE2EMacAppBlobDecodesOnIOS` passed).
- **P6 QR pairing** ✅ — Mac renders QR of the 349-char payload; BarcodeDetector decodes it back to the EXACT payload which `parsePairingPayload` accepts. iOS scan handler built (camera scan itself = device-only).
- **P7 real iPhone** ⏳ HUMAN-GATED — hosted Supabase (recommended) + Xcode signing/install. See `SYNC-HANDOFF.md`.

Full iOS suite: **49 tests, 0 failures, 0 skips** (all live tests ran against local Supabase).

---

# Sync → QR: execution plan (v1, pre-adversarial-review)

**Goal (user's words):** "I want mac and iphone synced… get it to where the QR works."
End state: on the user's **real iPhone**, open Buddy → Settings → Scan the QR shown on the
Mac → the two devices sync add/complete/edit/delete both ways.

This plan is grounded in the actual code (read 2026-07-03), not the doc summaries.

---

## What already exists (verified by reading source)

**iOS — engine complete, no wiring:**
- `BuddyMerge.merge` (field-level, tombstones, per-item `v`) — done, unit-tested.
- `BuddySync.syncOnce(store,key,local)` — pull→merge→CAS push→retry, empty-over-full guard,
  content-key no-op — done, unit-tested.
- `SupabaseCASStore` (URLSession → `buddy_pull`/`buddy_push` RPC, SyncWire ms↔s) — done,
  **verified live** against local Supabase (3 live tests actually ran).
- `SyncIdentity` (generateSyncKey / deriveOwnerId) + `SyncWire` — done.
- **GAP:** `BuddyStore` has **no** `snapshot()` producer and **no** `adopt(merged)` applier.
  No `SyncConfig`. No sync loop. No Settings sync UI. No QR scanner. No `NSCameraUsageDescription`.

**Mac (`dist/index.html`) — core present, no network/UI:**
- `generateSyncKey`, `deriveOwnerId`, `pairingPayload`, `parsePairingPayload` — done, unit-tested.
- `syncOnce`, `makeFakeCASStore`, `mergeWire`, `blobContentKey`, `serialize`/`applyWire` — done.
- **GAP:** no real `makeSupabaseCASStore` (it's on `feat/sync-live`, salvageable), no `scheduleSync`
  loop, no `SyncConfig` persistence, no Settings sync UI, no QR **render**.

**Backend:** local Supabase is UP (`http://127.0.0.1:54321`). Both CAS RPCs + tests exist.

---

## The two honestly human-gated legs (flagged, not hidden)

Everything through a **local round-trip (Mac app ↔ iOS *simulator* on 127.0.0.1)** I build and
verify myself. Two legs need the user's hardware/account — I make each a dead-simple step and
drive everything around them:

1. **A backend the *physical phone* can reach.** `127.0.0.1` is simulator-only. A real phone needs
   either **(A) hosted Supabase** (HTTPS, works anywhere, one-time `supabase login` + project) or
   **(B) the Mac's LAN IP** with local Supabase bound to `0.0.0.0` (same-wifi only, cleartext).
   → **Flagged decision, confirm at P7.** Recommendation: **hosted** (robust, survives leaving wifi,
   no ATS cleartext concerns). Code is identical either way — only the URL in the QR differs.

2. **The dev build on the physical iPhone.** Needs Xcode signing with the user's Apple ID + phone
   plugged in + "Trust". I prep signing/provisioning; the user plugs in + taps Trust once.

These are "first run = human unlocks access." They do **not** block P2–P6.

---

## Build order (each phase independently verifiable)

### P0.5 — Golden cross-decode (front-load the wire risk) ✅ cheap
Add a test asserting a **fixed Mac blob** (ms epoch) decodes via iOS `SyncWire.toSnapshot()` and a
**fixed iOS blob** decodes on the Mac (`applyWire`/`mergeWire`), yielding equal logical state.
Pins the ms/s boundary before both apps depend on it.
**STOP:** both decode tests green.

### P1.5 — iOS store snapshot bridge (the missing core)
In `BuddyStore`:
- `func snapshot() -> SyncSnapshot` — build from today/history/deferred/settings/tombstones/erasedAt/savedAt.
- `func adopt(_ merged: SyncSnapshot)` — replace state from a merged snapshot, on the main actor,
  **suppressing the save-debounce storm and firing NO celebration**. Must not spuriously re-trigger
  the morning planner (respect `today.morningDone` from the merge; guard the rollover interaction
  noted in `performRolloverIfNeeded`).
- Unit test: `adopt(snapshot())` is identity; `adopt(merge(local,remote))` applies remote edits.
**STOP:** round-trip identity + merge-apply tests green.

### P2 — iOS sync loop + config
- `SyncConfig { backendUrl, anonKey, syncKey, enabled }`. Persist url+anonKey in UserDefaults;
  **syncKey in Keychain**. `enabled=false` by default (local-only preserved).
- **Validate** the sync key is full **43-char base64url** before enabling (blank/short key →
  `deriveOwnerId("")` constant hash → shared bucket / cross-user leak). Reject in the setter.
- A `SyncEngine` actor (serial; no overlapping passes): `pull-on-launch`, `pull on scenePhase==.active`,
  **debounced push-on-change (2–3s)** via a dirty flag. **Re-arm the dirty flag** if a change lands
  during an in-flight sync. On success adopt merged + stamp `lastSyncedAt`. On failure (syncOnce
  ok:false / throw) **do NOT stamp** a reassuring time — record `lastError`, retry next trigger.
- `BuddyStore` marks dirty on every `scheduleSave`.
**STOP:** with config set (to local Supabase) the sim pushes on change + pulls on foreground; toggling
`enabled` off returns it to pure local. Verified via live test + a manual sim run.

### P3 — iOS Settings "Sync" section + QR scanner
- Buddy-styled Sync section in `SettingsView` (matches the card idiom, adapts to lvl0/1/2 theme):
  "Scan QR to pair" button, status row ("Synced HH:MM" / "Not connected" / error), and a
  **manual-paste fallback** (URL + anon key + sync key) so the simulator (no camera) is testable.
- QR scanner: native **AVFoundation** capture (or `DataScannerViewController`) → `parsePairingPayload`
  → validate → write `SyncConfig` → enable. Add **`NSCameraUsageDescription`** to `project.yml`+Info.plist.
  Graceful "no camera on simulator" message; paste path always works.
**STOP:** paste a payload in the sim → it configures + syncs. Scanner compiles; camera path is the
physical-phone leg. Screenshot the Sync section at lvl0/1/2 (RULE 2 every-state check).

### P4 — Mac adapter + sync loop + Settings + QR render (RULE 2 gates apply)
- **Salvage** `makeSupabaseCASStore` + `scheduleSync` from `feat/sync-live` into the CURRENT `dist`.
  Re-find the **current** `writeNow` / boot / `visibilitychange` hooks (dist changed since that branch)
  — this is re-integration, not copy-paste.
- `SyncConfig` in localStorage (Mac is single-user local; key-in-localStorage acceptable). Same
  **43-char validation**. Pull on boot + on window focus; debounced push on change with the same
  dirty re-arm; surface real last-sync/error state; **never stamp synced-at on failure**.
- Settings sync UI: **Generate key** (or paste), backend URL field, "Synced HH:MM", and a
  **QR render** of `pairingPayload(url, key)`. Vendor a tiny MIT QR encoder inline (self-contained;
  no CDN) → SVG/canvas.
- `pinned`: ensure the Mac preserves its own pin rather than adopting the merged blob's.
- **GATES (both required, RULE 2):** `await window.__buddy.smokeTest()` → `{ok:true}` **and** a clean
  visual red-state sweep (lvl0/1/2 legible), because sync touches shared save/boot plumbing.
**STOP:** Mac pushes/pulls against local Supabase; smokeTest green; red sweep clean.

### P5 — LIVE ROUND-TRIP (local, me-verifiable)
Same sync key on Mac app + iOS sim against local Supabase. Prove every scenario:
- add on Mac → appears on iOS; complete on iOS → reflects on Mac.
- delete (tombstone) propagates; a resurrecting stale push does NOT bring it back.
- erase-all barrier wins over a stale push (test on the lagging-clock device — the one wall-clock edge).
- two-device same-day edit merges with **no lost edit** (field-level).
- fresh empty device pulls-before-pushes (empty-over-full guard) on first pair.
**STOP:** all scenarios pass, screenshotted.

### P6 — QR pairing, both ends wired
- Mac Settings renders the QR (P4). iOS scans it (P3).
- Verify the **payload path** fully: decode the Mac-rendered QR image programmatically → assert it
  equals `pairingPayload(url,key)`; feed that string to the iOS parse+configure path → asserts enabled.
- Real **camera scan** is the physical-phone leg (P7).
**STOP:** rendered QR decodes to the exact payload; iOS configures from it.

### P7 — Real iPhone (human-gated, made trivial)
Confirm **hosted vs LAN** (flagged above). Then:
- If hosted: one-time `supabase login`, create project, `supabase db push` the two migrations,
  put the project URL + anon key in the Mac Settings. (I write numbered click-steps.)
- Prep Xcode signing; user plugs in phone + taps Trust; deploy the build.
- User scans the Mac's QR → real two-device sync.
**STOP:** the user confirms a real add-on-Mac shows on their iPhone.

---

## Sequencing & scope
- Phases share `BuddyStore` and `dist/index.html` (same files) → **sequential, not parallel** subagents
  (per delegation rules: don't fan out same-file work).
- Sync lives on its own branch `feat/ios-sync-live` / its own PR — don't bloat the parity PR (#61).
- One adversarial agent reviews THIS plan before execution (user's explicit ask).

## Adversarial review incorporated (v2 — CONFIRMED against source)
- **B1 (BLOCKER, confirmed):** Mac `serialize()` emits `settings:{celebrate, reserveSpace}` — **no
  `historyDays`**. iOS `BuddySettings` requires it → every Mac→iOS decode throws `keyNotFound` →
  whole pull fails. The "verified live" tests only round-tripped iOS-authored blobs, hiding it.
  **FIX:** custom `BuddySettings.init(from:)` with `decodeIfPresent ?? default` for all three fields.
  P0.5 fixture = a blob matching `serialize()`'s EXACT shape (no `historyDays`, `pinned` present,
  `src:null`, `doneAt:null`, `savedAt` in **ms**).
- **M2 (MAJOR, confirmed):** the row key is `owner_id = sha256(syncKey)`; the SQL does NOT hash —
  the caller derives it. Mac passes `deriveOwnerId(cfg.syncKey)` to `syncOnce`. iOS live tests pass a
  raw literal (transport test only). **FIX:** P2 `SyncEngine` MUST call
  `syncOnce(key: SyncIdentity.ownerId(for: syncKey))`, else Mac + iOS land in different buckets and
  each "syncs" to itself. Add a live cross-app test (below).
- **M3 (MAJOR, confirmed):** `pinned` is desktop-only; iOS `SyncSnapshot`/`SyncWire.toSnapshot()`
  drops it, Mac's `blobContentKey` includes it → infinite version churn + pin flip-flop. **FIX:**
  treat `pinned` as **device-local, never synced** — strip from `blobContentKey` on the Mac and keep
  local pinned across an adopt (don't let a merged blob overwrite it). iOS already ignores it.
- **M4 (MAJOR, confirmed):** `NSAllowsLocalNetworking` does NOT cover LAN IP literals (192.168/10/172).
  **FIX:** P7 default = **hosted Supabase**; drop the "LAN is identical, only the URL differs" claim.
  LAN kept only as an explicit fallback needing an ATS change (documented, not promised).
- **Real P5 gate (was hand-wavy):** the cheap gate that catches B1+M2+M3 at once = a **live test** that
  pushes a real Mac-`serialize()`-shaped blob to the DB **at the derived ownerId**, then pulls + decodes
  + merges it on iOS (and the reverse). App-to-app screenshots are secondary theatre.
- **QR encoder:** vendor **nayuki/QR-Code-generator** (MIT, ~1k lines, zero deps, CSP-safe). Not a CDN build.
- **Camera path is UNVERIFIED until hardware (P7).** "Scanner compiles" ≠ "scanning works" — say so.
- **Overnight boundary (honest):** I can build everything and verify a **live Mac-app ↔ iOS-simulator
  round-trip** against local Supabase + the QR payload path. The **physical iPhone** needs the user's
  Apple ID signing + a phone plugged in + a hosted backend login — those are the only human legs, left
  as a dead-simple morning checklist.

## Top risks (for the reviewer to attack)
1. `adopt()` re-entrancy: applying a merged snapshot triggers `scheduleSave` → marks dirty → schedules
   another push → ping-pong. Need a "applying remote" suppression flag.
2. Two idle devices version-churn despite the content-key no-op if `savedAt` leaks into the fingerprint.
3. Sim ATS cleartext to `127.0.0.1` (covered by `NSAllowsLocalNetworking`) vs a **LAN IP** (may NOT be
   covered — verify before promising LAN).
4. QR encoder vendored into dist must be dependency-free + MIT + small.
5. `scenePhase==.active` pull racing the launch pull (double sync on cold start).
6. Keychain access on first launch / entitlement for the app.
7. Merge re-triggering the morning planner via `performRolloverIfNeeded` after `adopt`.
