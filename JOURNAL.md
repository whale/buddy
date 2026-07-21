# Buddy — Journal

Non-obvious learnings, gotchas, and decisions worth not re-learning the hard way.
Newest first.

---

## 2026-07-20/21 — 0.4.27: iOS Boss Mode sync-for-free, and the celebration that only worked in the test

**Sync a mirrored feature for free by riding the per-item `extras` bag.** iOS Boss Mode
("sweep done off the list") needed `clearedAt` to sync both ways. Instead of a new wire key +
merge rule, `clearedAt` is a COMPUTED `BuddyTask` property backed by `extras["clearedAt"]` (the
bag that already carries the Mac's unknown per-item fields). It round-trips the existing wire,
`pickItem` carries it (v-bump drives propagation), and it's excluded from `contentKey` exactly
like the Mac — zero merge/contentKey change, and a sweep on either device mirrors. When mirroring
a feature, check whether the value can ride an existing passthrough before inventing wire schema.

**`TimelineView(.animation)` silently never starts when the view is CREATED via an async state
change.** The celebration burst rendered from the forced screenshot fixture (which flips the flag
in `.task`) but NOT on a real task completion (which flips it from a tap callback). Same view,
same code — only the *timing of the trigger* differed. On-device observation was the only way to
see it: a temporary full-screen tint proved the overlay MOUNTED and `onAppear`/`launch()` RAN
(particles populated) — but the `Canvas` never redrew, so the `TimelineView` clock never ticked.
The happy-path fixture hid it completely. Fixes that finally worked, in combination: (1) keep the
overlay ALWAYS mounted and swap the child by `.id(trigger)` (don't insert it behind an `if` on
async toggle); (2) use `.periodic(from:by:)` not `.animation`; (3) GATE the `TimelineView` on the
populated `parts`/`launched` @State, so it's created in the RE-RENDER that follows `launch()` —
that post-populate re-render is what actually kicks the clock alive. **Lesson: a UI thing that
"works in the fixture but not in real use" is often a trigger-TIMING difference (initial-render
vs async), not a logic bug — and `TimelineView(.animation)` is fragile to async creation. Verify
animations by driving the REAL interaction path, not a forced flag.**

---

## 2026-07-19/20 — 0.4.25: sync stops deleting tasks, mutual unlink, and the race the happy path hid

Two sync features, and both taught the same lesson twice: **my own verification passed
before the adversarial review found a real, shipping-blocking bug.**

**Overflow → Future.** Sync used to silently DELETE tasks when two devices' combined active
list exceeded the 6-cap (the old `clampActiveItems` just dropped the overflow). Now they move
to Future with a synced, dismissible notice. The non-obvious part is **determinism**: "Mac
wins the slots" can't mean "whichever device I'm on" (the two devices would disagree and
ping-pong) — it's encoded in the DATA, via **id case** (Mac mints lowercase UUIDs,
`crypto.randomUUID`; iOS mints uppercase, `UUID().uuidString`), so both compute the identical
overflow set from the same merged input. Relocation happens inside `merge()`, reuses each
item's own id, and an invariant filter keeps a parked id off the active list. The review's fix:
the notice counts must be TRUTHFUL — count only tasks *actually relocated this merge*
(`keptActiveCount` read AFTER the invariant filter), or an already-parked overflow inflates it.

**Mutual unlink + the concurrent-sync race (CRITICAL, review-only catch).** Unlinking one
device now stamps the shared bucket with an `unlinkedAt` marker; the peer self-unlinks on its
next pass. My two-device live test passed. Then the review found the hole: a **poll pass already
in-flight when you tap Unlink** CAS-conflicts against the marker push, and the retry loop
folds+repushes the marker blob. On Mac that LEAKED `unlinkedAt` into local state (it rode the
`extras` bag → re-emitted on every future re-pair → **permanent, unrecoverable self-unlink
loop**, reinstall-only). On iOS the same fold DROPPED it (merge omits it) → peer never unlinks,
user falsely told it did. The lesson (again): a happy-path two-device test that doesn't force a
concurrent in-flight pass proves nothing about the race. Fix: read the marker in the **CAS-retry
loop too** and bail (never fold+repush); `pushUnlinkMarker` retries so it reliably lands; Mac
adds `unlinkedAt` to `DROP_WIRE_KEYS` so it can never touch local state. Regression test: a
two-writer race (in-flight pass vs marker push) asserting the marker survives on the server AND
never lands in local state.

**Release gotcha:** the v0.4.24 Mac release run FAILED mid-GitHub-outage; v0.4.25 superseded it
with all the code. A failed auto-release isn't worth chasing — the next merge's release carries
everything. Don't reuse a version number whose tag never published.

---

## 2026-07-14 — 0.4.0: Buddy Cloud + E2E encryption (the Ghost split), and what the reviews caught

The big architectural night: one codebase, two editions. The released app is the
**hosted edition** (backend identifiers injected at build time via gitignored
`dist/config.js` / fastlane-overwritten `BuddyCloud.swift`); a bare clone is the
**open edition** (local-only, self-host fields). Tasks are now **E2E-encrypted
on device** (HKDF(syncKey) → AES-256-GCM) — the server stores ciphertext plus
integers-only stats. No accounts, ever; payment (later) will be a purchase pass.
Decision record: `HOSTED-PLAN.md`.

1. **Two builds is a smell; one build with a config seam is the pattern.** We
   almost shipped a "secret" credentialed DMG. Zero of six comparable products
   (Bitwarden, Ente, Joplin, Standard Notes, Anytype, Ghost itself) do that — a
   publishable key is an *identifier*, not a secret, and anything in a shipped
   binary is extractable anyway. Enforce server-side; hide nothing.
2. **Resolve config at WRITE time, not read time.** A read-time fallback left
   `raw.url` empty in localStorage — and the pairing QR is built from the RAW
   config, so it would have encoded the literal string `"undefined"`, which iOS
   *accepts* (`URL(string:"undefined")` is non-nil) and silently syncs to
   nowhere. The adversarial review caught it pre-merge. Write the resolved
   values on Connect; everything downstream stays dumb.
3. **The mixed-version window is where sync upgrades die.** An old peer that
   pulls an encrypted row tolerant-decodes it as *empty-with-extras*, merges its
   plaintext in, and pushes a HYBRID (plaintext + stale `{enc,iv,ct}` echoed via
   the extras bag). A naive new client decrypts the stale half and discards the
   peer's edits — silent split-brain with both sides showing "Synced". New
   clients read the plaintext half and strip envelope keys from extras forever
   (`DROP_WIRE_KEYS` / `SyncWire.knownKeys`). The field report the same evening
   ("phone wasn't kept up while closed") was exactly this window, self-healing
   as designed once both devices updated.
4. **A rate limiter + a retrying client = self-inflicted lockout.** The per-IP
   creation throttle counted REJECTED attempts; Buddy retries every 1.5s, so one
   throttle event re-filled the counter forever. Only the two-device live gate
   against REAL prod caught it (unit tests with synthetic headers passed).
   Counters must count *allowed* actions. Corollary: `x-forwarded-for` is
   client-spoofable on the left and internally-polluted on the right — scan
   right-to-left for the first public IP, and verify against the real proxy
   chain, never just synthetic headers.
5. **E2E blinds your own tooling too.** `sync:doctor` now reads `today=0` on a
   healthy bucket — it can't decrypt (that's the point). It must learn to read
   the plaintext stats columns. Budget for every observability tool to need the
   same lesson.
6. **Stacked-PR gotcha:** merging + deleting a stacked PR's base branch CLOSES
   the child PR (GitHub won't retarget a closed one). Retarget children to main
   FIRST, then delete branches.

---

## 2026-07-10 — the field-report marathon: five lessons that now have guardrails

1. **Sync "working" on both ends ≠ synced.** Dev Buddy and the iPhone were each
   green — pushing to two DIFFERENT buckets (dev held a stale syncKey from an old
   Resync). Split brain is invisible from inside either device. Guardrails:
   `pnpm sync:doctor`, the bucket suffix in both Settings, `sync-owner` diag.
2. **Your own half-typed echo can beat your commit.** The 1.5s poll pushed
   mid-edit text at an unchanged per-item `v`; the equal-`v` canonical tiebreak
   then preferred "Thi" over "Thing". Fix: no sync passes while editing + the
   blur v-bump compares against the text at EDIT START (the live-updated
   `it.text` always said "unchanged").
3. **"Uploaded to TestFlight" ≠ visible.** Apple's ingestion silently swallowed
   build 21 — fastlane had `skip_waiting_for_build_processing`, so "success"
   meant only "file transferred". The lane now waits; green = installable.
4. **SwiftUI DragGesture (ANY priority) starves an enclosing ScrollView** — the
   Future list stopped scrolling even with `simultaneousGesture`. Row swipes must
   be a UIKit pan that only *begins* on horizontal movement. And its overlay must
   ride BEFORE `.offset`, or it covers the revealed tray and eats the action taps
   (shipped broken in build 24, caught by the user, now a UI test).
5. **XCUI frames lie about text.** The editor "jumped 4.5pt" by accessibility
   frame while a screenshot pixel-diff showed 0.0pt. Interaction claims need
   observed evidence — that's RULE 4 and `RELEASE-CHECKLIST.md` now.

## 2026-07-01 — "random" celebration words weren't random (deterministic hash of sequential ids)

**The bug.** A tester's completed tasks showed patterned done-words (Donezo / Ticked Off /
Donezo / Ticked Off) instead of random ones. The word was `DONE_WORDS[hash(id) % 25]` — a
*deterministic* pick, chosen so the word stays stable across re-renders (a good goal). But
the input was the task **id**, and ids are often **sequential** (history rows `h-DATE-0/1/2`,
the `n1/n2` fallback). A rolling hash of near-identical strings increments in lockstep, so
`% 25` **marched down the word list** — neighbouring tasks got neighbouring words. Random
UUID ids actually spread fine; the bug only surfaced when ids were sequential, which is easy
to miss if you only test with fresh UUID tasks.

**The fix.** Don't derive randomness from a value that isn't random. Use a **shuffle bag**
(every word handed out once before any repeat, then refill) and pick **once at completion**,
storing the result on the item (`it.doneWord`). That gets you *both* properties the hash was
trying to fake: genuinely spread out (bag) AND stable across renders (stored, not recomputed).
Persist it; backfill existing done items at boot so an old list re-shuffles immediately.

**Lesson: a deterministic hash of a non-random, sequential input is not a shuffle — it's a
march.** If you want "random but stable," roll once and store the result; don't hash an id and
hope it looks random. **Verify with the real input distribution** (sequential ids), not just
the happy-path one (UUIDs) — and confirm a pre-existing test failure is pre-existing by
stashing your change and re-running (the "hit targets" smoke check failed on baseline too).

## 2026-06-30 (later) — "Done" was conflating done + skipped; Future became a manual backlog

**The design bug.** History stores each task as `{text, done}`, and the Done tab rendered
*every* past task regardless of `done` — so tasks you **skipped** showed up in "Done" as
plain (un-struck) rows. "Done" should mean *done*. Fix: split into three tabs — Done
(`done:true` only) + a new Skipped tab (`done:false`), alongside the existing Future. The
data already carried the distinction; only the *view* was over-showing. **Lesson: when a
list looks "polluted," check whether the data is mixed or just the view — here the view was
the bug, the data was fine.**

**Future: auto-return was the wrong mental model.** Deferred ("Future") tasks auto-returned
to today at the next rollover (`wakeDeferred`). The user's instinct: Future should be a
*manual* backlog you pull from — auto-refilling the day with avoided tasks fights the whole
calm-focus premise. Reshaped Future into a holding pen: no auto-return, **+** to add, **×**
to remove, click-to-edit (mirrors the live list). Kept the cap guard (**+** hidden at
`HARD_CAP`) so pulling from Future/Skipped still can't overflow the day. The `wake` date
field is now vestigial (kept only for serialization shape).

**Releasing a feature — two gotchas.** (1) The auto-bump bot **+1's the patch on every merge
to `main`**, so a deliberate `0.3.0` in the PR shipped as **0.3.1** — set the version
expecting the bump, or add `[skip release]` to freeze it. (2) A **manual**
`gh workflow run "Release Mac app"` publishes even when `AUTO_RELEASE_MAC=false` — a
`workflow_dispatch` bypasses the gate, so you don't need to flip the var for a one-off release.

**Distribution is already solved (re: "how do I get an alpha tester?").** Because the app is
signed + notarized and the repo is public with a working auto-updater, onboarding a tester is
*just send the DMG link* — no TestFlight, no per-tester provisioning. Requirement: macOS 13+.
The only real friction is telling them it's a menu-bar / right-edge app so they know where it
went. First launch may show a one-time "downloaded from the Internet — Open?" dialog (normal;
notarized, so no hard Gatekeeper block).

---

## 2026-06-30 — "Flash then hide" was full-screen Spaces, not z-order (+ the updater stranding bug)

**Symptom.** After a release, the installed app stayed a version behind (no update
check mark). Worse, on launch Buddy would "flash up momentarily then hide behind
other windows," and clicking the tray "Show / Hide Buddy" did nothing.

**Two wrong guesses first (the lesson).** I assumed the window was losing z-order /
not staying frontmost, and shipped fixes around `set_focus` and `alwaysOnTop`. They
didn't work because the premise was wrong. The turning point was *running the real
app and inspecting the live window* (`CGWindowListCopyWindowInfo` via a tiny Swift
script) instead of theorizing: the window was already at floating **layer 5**, so it
literally could not be "behind" a normal window. **Inspect live state before
designing a fix — two iterations were wasted guessing.**

**Real root cause.** The window is `"alwaysOnTop": true` by config (in
`tauri.conf.json`). A floating window **cannot draw over an app in native
full-screen mode** unless its `NSWindow.collectionBehavior` opts in. The user works
in full-screen, so morning rendered on the *desktop* Space, got covered by the
full-screen browser, and "Show / Hide" re-showed it on a Space they weren't looking
at — looking like nothing happened.

**Fix.** Set `collectionBehavior |= CanJoinAllSpaces | FullScreenAuxiliary` at launch
(`allow_over_fullscreen` in `src-tauri/src/lib.rs`, via `objc2-app-kit`). Verified
live: behaviour value == **257** (1 = CanJoinAllSpaces, 256 = FullScreenAuxiliary).
Confirmed visually by the user in their real full-screen setup.

**Second bug, exposed by the first.** The reason the fix (and the prior release)
never *reached* the Mac: the in-app updater checked **once**, ~2.5s after launch, and
**swallowed errors silently**. One failed/missed check = stranded a full version
behind with no banner and no signal. Now it checks at launch, every 3h, and on window
focus (throttled to 1/min, stops once a banner shows), and `trace()`s failures so a
missed update appears in the bug-report logs.

**Delivery gotcha.** Because the updater itself was the broken link, you can't use it
to deliver its own fix — had to install the signed build directly (drag the DMG over)
once. After that, normal in-app updates resume.

**Takeaways.**
- A menu-bar / accessory app that must appear over full-screen apps needs
  `CanJoinAllSpaces | FullScreenAuxiliary`, not just `alwaysOnTop`.
- "Hidden behind a window" with an always-on-top window almost always means
  **Spaces / full-screen**, not z-order.
- Verify the *delivery path*, not just the fix — a silent once-only updater can mask
  every shipped fix.
