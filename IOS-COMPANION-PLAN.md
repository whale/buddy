# Buddy — iOS Companion + Sync Plan (built to one-shot later)

_Written 2026-06-18. Goal: an iPhone "Buddy" that shares the Mac app's design
language and syncs tasks, while keeping the whole project open-source (MIT).
Reviewed adversarially for simplicity._

---

## TL;DR

- **Build it native (SwiftUI), not as a wrapped web view.** Reuse the proven
  TestFlight pipeline from `belly-apple` / `sensei`. The iPhone app shares
  Buddy's _soul_ (type scale, escalation colors, calm), not its desktop drawer
  layout.
- **Sync = one small JSON document for one user.** Use an **opt-in Supabase**
  backend (you already run it for Belly), with **local-only as the default** so
  the open-source clone-and-run story holds.
- **Decouple durability from sync.** The Mac data-safety fix
  (`DATA-SAFETY-PLAN.md`) needs _no backend_ and ships first.

---

## Why native SwiftUI, not Tauri-mobile

Buddy's identity _is_ the menu bar + right-edge drawer. On iPhone there is no
menu bar, no edge drawer, no always-present sliver — so even a perfect Tauri-iOS
render of `dist/index.html` would still need its navigation rebuilt for the
phone. The web-wrapper's one advantage (shared rendering) evaporates the moment
you accept the interaction model differs, leaving only its liabilities (Tauri-iOS
maturity, webview background-sync limits, an unproven signing path, App Store
"wrapped website" risk).

**So "pixel-identical" is the wrong target.** The right target: **same design
language, native shell.** Same type scale, same lvl0/lvl1/lvl2 escalation colors
(a trivial color-swap to port), same calm — different navigation, because the
devices are different. This is _less_ total work than fighting Tauri to fake a
drawer, and it reuses a pipeline you've already shipped twice.

**What the iPhone app is, concretely:** a full-screen single view = the drawer's
contents full-bleed. The 3 active slots as the home screen; "Donezo"/history
behind a bottom sheet (Buddy already speaks bottom-sheet); the escalation theme
as a computed background+text color from the active count.

---

## Sync — one document, opt-in, local-default

Buddy's entire state is one small JSON blob (`{today, history, deferred,
settings}`). You are syncing **one document for one user**, not a relational
dataset — far simpler than Belly's capture queue.

**Backend: a single Supabase project, free tier, Row Level Security.**
- Works from _both_ a Tauri webview (supabase-js) and SwiftUI.
- Open-source friendly: the anon key is publishable by design; the schema +
  client code are public; a contributor supplies their own Supabase URL + anon
  key, or the app runs **local-only with nothing configured**.
- **CloudKit is disqualified:** Apple-team-bound (can't reach the Tauri Mac app
  without Swift glue), kills any future web/Windows build, and can't be
  open-sourced/self-hosted (a cloner can't run your container).

**Non-negotiable rule:** the app boots and works **fully local-only** with no
backend. Sync is opt-in — paste a Supabase URL + anon key + a "room id"
passphrase in Settings (the Settings sheet already exists). That one choice
satisfies the MIT clone-and-run constraint cleanly.

**Identity — QR-code device pairing (LOCKED).** The seamless, login-free, secure
pattern (how WhatsApp/Signal/Plex link devices):
- On first run the Mac auto-generates a **high-entropy sync key** (never typed).
- Settings shows a **QR code** encoding `{ backendUrl, syncKey }`.
- The phone **scans it once** → both devices derive the same `owner_id` from the
  key; Supabase **RLS** scopes every row to it. No email, no password, no OAuth.
- Manual fallback: a copy-paste key string for anyone who can't scan.
This beats a typed passphrase (higher entropy, zero friction) and beats Sign in
with Apple (no Apple-account lock-in, works for the open-source/local story).

**Conflict policy (v1):** field-level **`merge()` on the client** + a dumb
compare-and-swap server (LOCKED 2026-06-19 — superseded the original whole-doc
last-write-wins, which an adversarial review showed silently loses an edit on any
two-device day). See the locked decisions + decision log below. A visible "synced
at HH:MM" indicator remains; no CRDTs.

---

## What's reusable (pipeline yes, product no)

| Asset (path) | Verdict |
|---|---|
| `belly-apple/fastlane/{Appfile,Fastfile}`, `project.yml` (XcodeGen) | **Copy wholesale**, swap bundle id → `fyi.whale.buddy` / `com.whale.buddy`, team `9QDAAYWU9X`. |
| `sensei/apps/ios/.github/.../ios-app-ci.yml` | **Copy wholesale** — XcodeGen + simulator build CI. |
| ASC API key `~/.config/belly-asc-key.p8` + `ASC_KEY_ID/ISSUER_ID/KEY_PATH` | **Reuse as-is** — same team, same key. |
| `belly-apple/BellyKit/CredentialStore.swift` | **Reuse as pattern** (Keychain wrapper) — store Supabase URL+key. |
| `belly-apple/BellyKit/BellyClient.swift` | **Reference only** — borrow auth/session plumbing; Buddy needs one `select`/`upsert` of a single row. |
| Buddy escalation tokens (lvl0/1/2 in `dist/index.html` `<style>`) | **Re-express in SwiftUI** — values port, CSS doesn't. |
| Buddy drawer layout | **Do not reuse** — rebuild full-screen for iPhone. |

**Genuinely new:** the iPhone presentation/navigation, the single-document sync
layer (both ends), the local-only/opt-in-sync Settings UX, the conflict rule.

**Apple facts (confirmed):** Team `9QDAAYWU9X` (Wimp Decaf), shared across Wimp
Stickers (live), Belly, Sensei. Bundle-id prefixes in use: `fyi.whale.*` /
`com.whale.*`. Pipeline = XcodeGen `project.yml` (Automatic signing, team pinned)
+ fastlane `beta` lane + ASC API key. Publishing via Wimp Decaf is fine.

---

## Sequenced plan (each phase independently valuable, ends at a STOP)

> ⚠️ **Superseded for sync details (2026-06-19):** Phases 3–6 below predate the
> adversarial review. For the *conflict model and sync mechanics*, the
> authoritative spec is the **"Sync build order"** + **Locked decisions** + **Decision
> log** further down (CAS-on-client, not LWW, and the live DB enters only at step 5).
> The phase list still holds for sequencing/value framing.

- **Phase 0 — Decisions (no code). STOP.** Lock: native SwiftUI; "same language,
  not pixel-identical"; opt-in Supabase + local default; durability-first;
  answers to Q1–Q7 below.
- **Phase 1 — Mac durability** (`DATA-SAFETY-PLAN.md`, no backend). Ships value,
  commits to nothing. STOP: data survives a localStorage wipe.
- **Phase 2 — Throwaway spike (~1 hr):** supabase-js upsert/select one row from
  `dist/index.html`. Discard the code. STOP/decision: if painful, reconsider a
  tiny custom endpoint (still Supabase-hosted).
- **Phase 3 — Mac sync (opt-in).** Settings fields (URL + anon key + room id);
  one Postgres table `buddy_state(owner_id, blob jsonb, updated_at)` + RLS;
  push-on-change, pull-on-launch; **CAS push (pull → merge → compare-and-swap →
  retry)** + "synced at" (LWW was reverted — see Locked decision 4 + Decision log).
  STOP: round-trip + two-device merge verified.
- **Phase 4 — iOS skeleton via the proven pipeline.** Copy belly fastlane +
  `project.yml`, swap ids/team, XcodeGen, empty SwiftUI app → TestFlight. No
  features yet. STOP: TestFlight build installs.
- **Phase 5 — iOS product.** Full-screen active list + escalation colors +
  bottom-sheet history + add/complete/undo; wire the Phase-3 sync layer. STOP:
  functional + red-state legibility sweep (RULE 2, adapted to SwiftUI).
- **Phase 6 — Open-source hardening.** README "runs local-only; to sync, paste
  your Supabase creds"; confirm no secret committed.

Phases 3→6 are one-shot-able **only because** 0–2 removed the unknowns. Don't
collapse 0–2 into the one-shot.

---

## Locked decisions (v1) — 2026-06-18

1. **Scope: full parity.** The iPhone app is the same experience as the Mac app —
   view, add, complete, edit, history. (Not read-only.) Native nav, shared design
   language (the menu-bar drawer becomes a full-screen view).
2. **Identity: QR-code device pairing** (see above) — auto-generated sync key, scan
   once, manual copy-paste fallback. No login.
3. **Sync surface: everything** — `today`, `history`, `deferred`, AND `settings`.
   (Desktop-only prefs like `reserveSpace` are simply ignored by the iOS UI.)
4. **Conflict: field-level MERGE, not whole-document last-write-wins.** An
   adversarial review (2026-06-19) showed whole-doc LWW silently loses an edit on
   any day both devices are touched, plus several other data-loss paths. The safe
   design (the minimum that works — NOT a CRDT):
   - **Globally-unique IDs** (UUIDs), not per-device `n1,n2…` counters. ✅ done.
   - A pure, **commutative + idempotent `merge(a,b)`** used at every reconcile point
     (Mac localStorage↔file boot, and local↔remote on both apps): `today.items`
     union by id keeping the higher per-item version; `history` union by date;
     `deferred` union by id; `settings` field-wise.
   - **Tombstones** (`{id: deletedAt}`) + a top-level `erasedAt` so deletes stick
     but stale pushes can't resurrect them, and a real "Erase all" can propagate.
   - Per-item **version counter** decides ties, NOT client wall-clock (clock skew
     would otherwise let stale data win). Server `now()` is only the "synced at" label.
   - **Merge runs on the CLIENT, never the server (LOCKED 2026-06-19 — see decision
     log).** The server is a **dumb atomic store** with a version stamp; each device
     does **pull → `merge(local, remote)` → compare-and-swap push → retry on version
     conflict**. This keeps `merge()` in the two places already tested (JS + Swift),
     not a third untestable plpgsql copy. First pair = **scanner pulls before it
     pushes** (an empty new phone can never wipe a full Mac); the client also refuses
     to push an empty blob over a non-empty remote.
5. **Distribution: open-source + TestFlight.** Official builds → TestFlight (Wimp
   Decaf team) for personal use; repo public so anyone can clone + build their own;
   **sync backend opt-in, local-only by default** (contributor supplies their own
   Supabase URL+anon key, or runs offline — no secret committed). Public App Store
   optional later.
6. **Two update channels accepted:** GitHub Releases (Mac), TestFlight/App Store (iOS).
7. **Bundle id:** `fyi.whale.buddy` (iOS target shares the identifier family).

### Sync build order (post-adversarial-review — each step ships safely on its own)
1. **Globally-unique IDs (UUID) + migration** on both apps. ✅ done & verified.
2. Add `v` (per-item version), `tombstones`, `erasedAt`, and **idempotent
   date-keyed rollover** to the local model on both apps; deletes write tombstones.
   No network. Gate on the existing smoke test + red-state sweep. ✅ done & verified
   (Mac: smoke test 10/10 + persistence round-trip + idempotent-rollover runtime test;
   iOS: mirrored, xcodebuild SUCCEEDED). ⚠️ timestamp UNITS still differ (Mac ms-epoch
   vs Swift Date/seconds) — step 4 must normalize before any cross-device merge.
3. Write + unit-test the pure `merge(a,b)` on both apps; wire it into the Mac's
   localStorage↔file boot reconcile FIRST (proves the merge with no network).
   ✅ **done & verified.** Mac: `merge()` in `dist/index.html`, wired into
   `bootReconcileFile`, 12-test `__buddy.mergeTest()` gated inside `smokeTest`
   (12/12 + smokeTest 11/11 in-browser). iOS: `BuddyMerge.merge()` in
   `ios/.../Sync/BuddyMerge.swift` + a real XCTest target (`BuddyTests`, wired via
   `project.yml`) — `xcodebuild test` 10/10 passing. ⚠️ TWO follow-ups before
   cross-device sync: (a) **timestamp units** still differ (Mac ms vs Swift s) —
   step 4 must normalize; (b) iOS `DayItem` has **no id**, so same-date history
   records merge positionally (done-wins) rather than by id like the Mac — give
   `DayItem` an id for fully robust cross-device history merge.
4. **Normalize the wire format (one place).** Pick **epoch milliseconds** as the
   single on-the-wire time unit (Mac already uses it); iOS converts on encode/decode
   (`savedAt`, `erasedAt`, tombstone `deletedAt`, `doneAt`). Give iOS `DayItem` an
   `id` (`h-<date>-<i>`, like the Mac) so history merges by id, not by position.
   No backend needed — testable on both apps directly.
5. **Dumb CAS server + client sync loop.** Server contract — `buddy_push(key, blob,
   expected_version) → {blob, version, ok}` (no merge logic on the server):
   - **No row yet** (first push from a new pairing): require `expected_version = 0`
     → insert at `version = 1`, return `{ok:true, version:1}`. A non-zero
     `expected_version` against a missing row returns `{ok:false}` + an empty/null row.
   - **Row exists:** if `expected_version = stored.version` → overwrite, set
     `version = stored.version + 1` (server-side increment), return
     `{ok:true, version:new}`. Else → `{ok:false, blob:stored, version:stored}`.
   - `buddy_pull(key) → {blob, version}` (version 0/empty if no row).
   The **version is owned and incremented by the server**; the client adopts the
   returned `version` as its next `expected_version` (no re-pull needed on success).
   Client loop (Mac first, in the browser against a fake in-memory store so it's
   testable without Postgres): `pull → merge(local, remote) → push(expected=pulled
   version) → on {ok:false}, merge(local, returned blob) and retry with the returned
   version`. Refuse to push when local is empty and remote is non-empty (the
   empty-over-full guard, scanner-pulls-first). Coarse debounce (2–5 s); cap synced
   history (~90 days); key in OS secure storage. Then QR pairing. The live Supabase
   function is ~15 lines, verified once the DB is up.
6. Explicitly reproduce each loss scenario (different-task edits, 5-min clock skew,
   empty-phone-vs-full-Mac, double midnight rollover) and confirm ZERO loss — runs
   locally with two simulated clients (no Postgres needed for the merge/loop logic).

### Decision log
- **2026-06-19 — CAS-on-client, NOT server-side merge.** A first cut wrote the merge
  in plpgsql (a third copy of `merge()`) which couldn't be tested without Docker and
  drifted from the JS/Swift versions. Reverted (PR #29 closed). Chosen: the server is
  a dumb atomic store with a version stamp; the client pulls, merges (already-tested
  JS/Swift), and pushes with compare-and-swap, retrying on conflict. Simpler, two
  merge copies instead of three, and fully testable on this machine.

### Still to decide (not blocking)
- Whether the maintainer hosts a default Supabase project or every user brings their own.
