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

**Identity without a heavy login:** shared anon key + a user-invented **room id**
(passphrase) typed once on each device; RLS scopes rows to that id. No email, no
OAuth. (Sign in with Apple is the heavier "more correct for App Store"
alternative — decide per question Q1 below.)

**Conflict policy (v1):** whole-document **last-write-wins by `updated_at`**, with
the overwritten blob saved as a local backup + an undo, and a visible "synced at
HH:MM" indicator. No CRDTs. (The `DATA-SAFETY-PLAN.md` file-backup makes the
"saved before overwrite" trivial.)

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
  push-on-change, pull-on-launch; last-write-wins + "synced at" + backup-before-
  overwrite. STOP: round-trip + clobber-undo verified.
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

## Open questions to answer before a one-shot build

1. **Identity:** room-id passphrase (light, recommended) vs Sign in with Apple
   (heavier, more App-Store-correct)?
2. **Conflict:** whole-document last-write-wins + undo (recommended) — acceptable,
   or do you need per-task merge?
3. **Sync surface:** sync `today` + `history` only, or also `settings` +
   `deferred`? (Desktop settings like `reserveSpace` may be unwanted on phone.)
4. **iOS v1 scope:** read-only "glance at my tasks" (≈⅓ the work) vs full
   add/complete/edit?
5. **Destination:** TestFlight-only (you already run it) vs public App Store
   (more review risk + polish)?
6. **Update channels:** accept two (GitHub Releases for Mac, App Store/TestFlight
   for iOS)?
7. **Bundle id:** `fyi.whale.buddy` (matches the Mac app) for the iOS app too?
