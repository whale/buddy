# Buddy — Open Source Project + Hosted Service

**Status:** v4, 2026-07-14. Founder decisions folded in: **no accounts, ever** (no passwords, no emails); paid hosting arrives later via a purchase pass; updates flow through the existing auto-updater + a Ghost blog for release notes.
**The product:** Buddy, a hosted service — pay (later), install, sync just works. Users never see a server, a key, a field, or a login.
**The project:** the same code, MIT, on GitHub — ships with NO backend; the README tells a developer what to stand up themselves.

---

## THE SHAPE

Buddy already contains the hard half of the right architecture: **the syncKey is an end-to-end data key the server never sees** (only `sha256(syncKey)` goes over the wire). Keep it forever. Layer the purchase pass on top of it later. Two things, arriving at different times:

- **The syncKey** — *what encrypts your data and pairs your devices.* Exists today. Add `HKDF(syncKey)` → AES-GCM and the E2E story is done: the server stores ciphertext, we can't read tasks, and the QR becomes the key-transport step (the Signal "link a device" pattern).
- **The purchase pass** — *proof of payment, no identity attached.* Arrives in phase 2, when money arrives. **No accounts, no passwords, no emails stored** (founder decision 2026-07-14). Buy on the web (merchant of record) → the receipt contains a pass → pasted once on the Mac → rides the pairing QR so the phone never asks → the server's push RPC checks it. Bound to a small number of sync buckets on first use so a leaked pass is worthless. Beta testers get free-forever passes.

**Sequence: Phase 0 this week (zero code) → Phase 1 encryption + invisible cloud, one PR per concern → Phase 2 payments (when there's something to charge for).**

Encryption is the only irreversible item, so it goes first; the pass is cleanly additive later because the data layer (syncKey buckets) doesn't change.

### Releases without accounts (standing model)

- **Mac:** the existing signed auto-updater feed. **iOS:** App Store/TestFlight. Neither knows who the user is.
- **Announcements:** a Ghost blog (release notes, "what's new"); the in-app update banner links to the relevant post via the `notes` field in `latest.json`.
- Nothing about shipping ever requires a login.

---

## 1. How one codebase serves both worlds (the Ghost pattern)

Ghost ships its Pro-only code *inside* the open repo, dormant, activated by a `hostSettings` config object injected only on Ghost(Pro) infrastructure. Buddy does the same:

- **A gitignored `dist/config.js`** holding the hosted backend `{url, anon}`. One `<script src="config.js">` tag before the main script (a missing file is silently ignored).
- **Repo ships without it** → a clone runs local-only and Settings shows the self-host URL+key fields. That IS the open-source edition.
- **Our machines + release CI drop the file in** (one `echo` from a GitHub secret before `tauri build` — a copy step, not a build step; `dist/index.html` stays hand-edited and shipped verbatim).
- **iOS mirrors it**: a gitignored Swift constants file injected by fastlane.
- **Hosted Settings never shows server fields.** `window.BUDDY_CLOUD` defined → one button: **Connect & show QR**. Undefined → today's fields. No flag, no fork, no second build.

**Honesty note we accept:** the config ships inside every public DMG, so it is *extractable* — "not advertised," not "secret." That's fine: every server-side protection below already assumes the anon key is public (Supabase documents the publishable key as safe to expose), and the founder's intent — nothing hosted in the repo or the README — is satisfied where it matters.

### Config is resolved at WRITE time (not a read-time fallback — that was a bug)

Connect writes the values into the stored config: `setSync({enabled:true, cloud:true, url:BUDDY_CLOUD.url, key:BUDDY_CLOUD.anon, syncKey})`. The QR and Resync read raw localStorage (`dist/index.html:1383,1405,1434`); a read-time fallback would leave those empty and the QR would encode the literal string `"undefined"` — which iOS *accepts* (`SyncIdentity.swift:40` checks only non-empty) and then syncs to nowhere, silently, forever. Write-time makes that impossible, and `readSyncCfg`, the three-state UI, iOS, and every test work unchanged. `cloud:true` lets `initSync` refresh url/key from config.js, so the hosted key stays rotatable.

### QR shrinks (v2)

With the backend implicit, the payload no longer needs `backendUrl`/`anonKey` — a v2 QR carries just the syncKey on hosted; keep v1 parsing for self-host. The QR is load-bearing: it is how the encryption key (and later the pass) reaches a new device.

### Bucket id becomes backend-aware

`:1389` shows `sha256(syncKey).slice(0,6)` and the README says "same code = provably paired." With two possible backends that's false (Mac on Cloud, phone on old backend, same id — the split-brain detector would certify a split brain). Display id becomes `sha256(url+'|'+syncKey).slice(0,6)`; **mint a fresh syncKey whenever the backend URL changes.**

---

## 2. Privacy: E2E, Option A, defused

**Decided:** tasks are encrypted on-device; we cannot read them. Founder: *"I don't want to track my users' tasks — that's private."*

**There is no reset dilemma, because there is nothing to reset.** No accounts → no passwords. The key lives on devices and travels by QR. The only true loss case is losing *every device at once* — and for a 3-tasks-a-day app that means losing glanceable history, not a document vault. Today's tasks are re-typed in ten seconds.

The honest pitch: *"Your tasks are scrambled before they leave your device — we couldn't read them if we wanted to. If you ever lose all your devices at once, your history starts fresh. **Buddy syncs; it isn't a backup.**"*

No recovery codes at signup, no key escrow, no Bitwarden ceremony. If users ever ask, "write down your sync key" already exists as an optional path.

**Mechanics:** blob envelope `{enc:1, iv, ct}`; clients detect a plaintext row and upgrade it on next push (trivial at two users — which is exactly why encryption ships before a third user exists). Shared JS/Swift test vectors, like the existing `sha256("buddy-test-key")` pin. Merge, `blobIsEmpty`, `blobContentKey` all run client-side on plaintext — the sync engine doesn't change.

### Metrics — counts, never content

| Metric | Source |
|---|---|
| Downloads | GitHub Releases download counts |
| Cloud users | `count(*)` on `buddy_state` (later: active passes) |
| Task volume | plaintext `stats jsonb` beside the ciphertext: `{active:int, done:int}` — integers only |
| Usage frequency | `updated_at` + a `pushes` counter |
| Version / platform | existing `device` column |

Same rule as the diagnostics log (CLAUDE.md RULE 3): counts, versions, timings — never content. Enforce with a test that `stats` contains no strings. Local-only and self-hosted users are invisible by construction; measuring them would mean phoning home, so we don't.

---

## 3. Hardening before the service takes strangers (unchanged from review 1 — all verified)

1. **Close the other Supabase doors.** `POST /auth/v1/signup` is open on a default project: unlimited `auth.users` rows and confirmation emails sent from our project. Disable all auth providers, email signup, anonymous sign-ins (until phase 2 re-enables deliberately). Confirm no Storage buckets; confirm `buddy_state` is not in the realtime publication.
2. **Blob size cap** in `buddy_push` (~256 KB; a year of Buddy is a few KB).
3. **Per-IP bucket-creation throttle**, plain SQL via `current_setting('request.headers',true)::json->>'x-forwarded-for'`. *Never a global ceiling* — public source means an attacker reads the number and burns it at 00:01 UTC, locking real users out all day.
4. **`buddy_delete(p_key)` RPC + an "Erase my cloud data" button** next to Unlink. No such path exists today; it's the first thing users ask and an EU obligation.
5. **Automatic alarm, not a ritual:** daily GitHub Action — row count / DB size jump → open an issue.
6. **Rotatable publishable key** (Supabase's new key system), which works because `cloud:true` re-reads config.

Cut as theatre or self-harm: global daily ceiling (DoS lever), per-owner write throttle (attacker just mints fresh owner_ids; wedged clients are handled by the 3s debounce + CAS no-op), GC (only item that could delete a customer's data; nothing is 90 days old), the proxy service (per-IP works in SQL).

---

## 4. Phase 2 — money without accounts (design now, build when charging)

- **The purchase pass.** `passes(pass text pk, status, max_buckets default 3, created_at)` + `pass_buckets(pass, owner_id, first_seen)`. **RLS on both tables in the same commit** (they live in `public`; forgetting it would expose every pass sold). `buddy_push` takes `p_pass`; when `require_pass` is on, a push from a new bucket binds it to the pass (reject past `max_buckets`); missing/revoked/expired → a **distinguishable** error the client renders as "Your Buddy hosting has expired" (today every RPC failure collapses to `Error`, `:1391` — that produces support tickets, not renewals).
- **Flow:** buy on the web → receipt email (sent by the merchant, not us) contains the pass → pasted once on the Mac → carried in the v2 QR → the phone never asks. No password, nothing to reset, nothing personal stored next to the data. Bucket-binding means a pass posted publicly works for 3 buckets and stops — visibly.
- **Merchant of record** (Lemon Squeezy/Paddle) — they carry EU VAT/US sales tax and send the receipts; Stripe leaves both on us. For a solo designer this is the decision.
- **Paid Supabase tier before the first sale** (SLA + support path). Privacy policy (short — with E2E and no accounts there's almost nothing to declare). iOS App Privacy label updated from "no data collected."
- **Self-hosters flip `require_pass = false`** in their own SQL — same file, nothing crippled; they pay their own hosting bill.
- **Beta testers: free-forever passes**, generated and handed out personally.

### App Store reality (checked July 2026)

Nothing forces In-App Purchase if the iOS app sells nothing in-app. Guideline 3.1.3 (multiplatform) allows a free app unlocked by something purchased on the web — Slack/Notion pattern. Buddy iOS dodges the "non-functional without purchase" trap because it already works free as a local task list; sync is the unlock. Hand App Review a working demo pass + paired setup in the review notes. Post-Epic (2025-26): external purchase links are currently permitted in the US at zero commission, under active appeal (SCOTUS took the case 2026-06-30) — treat a "subscribe on the web" link as a nice-to-have, don't architect around it.

### Explicitly rejected

- **Accounts** — founder decision. No sign-up, no passwords, no emails stored. The pass is proof of payment with no identity attached.
- **Blocking self-hosters from the iPhone app** — unenforceable under MIT (they can rebuild it), and trying = shipping DRM in an open-source app. The honest gate is: **the hosted service is paid; the phone app is free.** Ghost's exact bargain.

---

## 5. Protect the name, not the code

`TRADEMARK.md` modelled on ghost.org/trademark: forks may say *"derived from the source code for Buddy"* / *"Hosting for Buddy"*; they may **not** use the mark or call themselves "Buddy Cloud / Buddy Hosting / Managed Buddy." An hour of work; it's the actual moat.

---

## 6. Work plan

**Phase 0 — this week, zero code.** 30 minutes in the Supabase dashboard (§3.1 lockdown) + apply the size cap; then send the tester the URL + anon key to paste into Mac Settings. The wall he hit was missing credentials, not missing code. His data is plaintext for ~2 weeks — one consenting tester, fixable precisely because n=2.

**Phase 1 — the real MVP (~a week).**
1. Client-side encryption (envelope + upgrade-on-push), Mac + iOS, shared test vectors.
2. `dist/config.js` (gitignored) + CI secret injection; iOS constants via fastlane.
3. One-button hosted Settings; self-host fields only when config is absent; v2 QR; backend-aware bucket id; fresh key on backend change.
4. `buddy_delete` + Erase button; per-IP throttle; daily alarm Action.
5. **Verify per CLAUDE.md RULE 4:** `pnpm sync:live` driven against the real Cloud project end-to-end on two devices; `ui:smoke`; red-state sweep (lvl0/1/2 × every interactive state); full RELEASE-CHECKLIST. Guard: Cloud stays opt-in behind a click — the smoke test runs from `file://` and must never mint buckets.
6. README rewrite (hosted = default story; self-host = developer path; *"sync, not backup"*), TRADEMARK.md.
7. Ship a normal Mac release + TestFlight; reconnect the tester (announce per ship-announcements memory).
8. **Staging:** a second free Supabase project so `sync:live` never mints test buckets in production.

**Phase 2 — payments** (when ready to charge): `passes` + `pass_buckets` + `require_pass` + the distinguishable expiry error + pass field in the v2 QR, merchant-of-record checkout on buddy.whale.fyi, paid Supabase tier, privacy policy + iOS label, free-forever passes for the testers.

---

## 7. What running a service means (eyes open)

1. **Money converts "app" into "service" overnight** — implied uptime, a support inbox, refunds, a status answer when Supabase hiccups. Mitigations are cheap up front: paid tier, merchant of record, and copy that says *sync*, never *backup* — the promise defines the liability.
2. **The auto-updater is the blast radius.** One bad sync build reaches every Mac in hours. RELEASE-CHECKLIST + `sync:live` against Cloud are the deploy gate, not hygiene.
3. **No accounts keeps us out of the email business** — the merchant of record sends receipts; we never run auth email. This is a load-bearing simplification: guard it.

---

## 8. Decisions

**Decided (founder, 2026-07-14):** hosted = paid service with an invisible backend, no server fields, **no accounts/passwords ever**; open source = self-host via README; E2E encryption (can't read tasks); metrics = counts never content; releases via auto-updater + Ghost blog.

**Assumption to confirm at phase 2:** paid-without-accounts is implemented as a purchase pass in the receipt email (§4). If that's ever unacceptable, the alternative is accounts — there is no third option.

**Decide at phase 2, not before:** price; Lemon Squeezy vs Paddle; `max_buckets`; whether the iOS app shows a US-only web-subscribe link.
