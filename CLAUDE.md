# Buddy — Project Rules

Buddy is a calm macOS menu-bar focus app: pick your top three each morning, a
right-edge drawer holds them all day, complete them, glance at history. Single
self-contained web app in `dist/index.html` wrapped in a Tauri v2 shell
(`src-tauri/`). No build step for the web app.

---

## 🔴 RULE 1 — Use the escalation theme tokens. NEVER hardcode adaptive colours.

Buddy has three escalation levels driven by **active** task count:

- **lvl0** — normal (white cards, black text)
- **lvl1** — 5 active → all text turns **red** (the "you're getting full" warning)
- **lvl2** — 6 active → the **whole drawer background turns red**, text turns light

The UI re-themes itself across these states **entirely through CSS custom
properties** defined in the `<style>` block. When you add or change any UI that
shows text/borders/icons on a card, you MUST use these tokens so it adapts:

THE PATTERN (user decision 2026-07-10): **EVERY text and element follows
lvl0 black-on-white → lvl1 red-text-on-white → lvl2 white-on-red. No carve-outs** —
done rows, day headers, glyphs, settings text and controls all follow. The canonical
token table lives in `design/escalation-tokens.json` (mirrored by the CSS vars on Mac
and `EscalationTheme.swift` on iOS; each platform has a test pinning it).

| Token | lvl0 (white) | lvl1 (red text) | lvl2 (red bg) | Use for |
|-------|-------------|-----------------|---------------|---------|
| `var(--ink)` | `#000` | `var(--red)` | `#fff` | ALL primary text (active + done + labels) |
| `var(--ink-dim)` | `rgba(0,0,0,.45)` | `rgba(229,72,77,.65)` | `rgba(255,255,255,.6)` | secondary / struck / dim text |
| `var(--glyph)` (`.icon-ink`) | `#8c8c8c` | `var(--red)` | `rgba(255,255,255,.92)` | row action glyphs |
| `.chrome` class | black | red | white | header glyphs/date |
| `.bd` class | `#d9d9d9` border | `#d9d9d9` | `rgba(255,255,255,.3)` | adaptive card borders/dividers |
| `var(--chrome-ink)` / `--sel-bg` / `--sel-ink` / `--line` / `--addtxt` | … | … | … | buttons, selected pills, lines, Add row |

**Hardcoding `text-black`, `text-black/35`, `rgba(0,0,0,…)`, `#000`, `border-[#d9d9d9]`
on anything that sits on a card is a BUG** — it stays dark on the red background and
becomes illegible (this exact mistake shipped the unreadable "Donezo" rows on red).
Since `--ink`/`--ink-dim` are level-driven, per-level colour branching in JS is also
a smell — just use the token.

⚠️ CSS gotcha: an ID rule (`#settings{ transition:… }`) silently overrides `.sheet`'s
transition (specificity) — that once killed the sheet slide entirely. Keep all sheet
transitions on `.sheet`/`.sheet.closing` only.

---

## 🧪 RULE 2 — Verify every build before shipping. Two gates, both required.

**Before ANY release/TestFlight upload, walk `RELEASE-CHECKLIST.md` top to
bottom** (automated gates → per-platform interactive pass → sync → announce).

A change that "looks cosmetic" can break shared plumbing three steps away
(rendering, attributes, focus, colours). Before **every** `pnpm tauri build`:

1. **Functional smoke test.** Serve `dist/` and run in the console:
   ```js
   await window.__buddy.smokeTest()   // must return { ok: true }
   ```
   It asserts: add focuses the new task, edit focuses the task text, complete
   marks done + drops the red count, undo restores, rows don't reuse `data-tid`,
   and **lvl2 done text adapts to light** (the red-bg legibility guard).

2. **Visual red-state sweep.** Inject states and screenshot all three levels;
   confirm every element is legible and correctly themed:
   - **lvl0**: ≤4 active — black text on white.
   - **lvl1**: exactly 5 active — all text red on white.
   - **lvl2**: 6 active — light text on red background (check Donezo rows, dividers,
     icons, the date card, settings sheet).

   Force a level by injecting items (see `__buddy.inject`); lvl = active count.
   Both `ok:true` AND a clean visual sweep are required — neither alone is enough.

3. **Every-state interactive check (EVERY UI task, not just builds).** Any change
   that touches colour, text, borders, icons, or interaction MUST be verified in
   **all three escalation states (lvl0 / lvl1 / lvl2)** AND in **every interactive
   state it has** — default, **hover**, focus/"now", selected, done. A fix that
   only works at lvl0, or only at rest, is not done.
   - **Hover specifically:** confirm the *post-transition* colour actually changed
     in each state — don't trust that the rule exists. Read the computed colour
     while hovering (a CSS `transition` will return the mid-flight value if you
     read instantly, which once hid a hover that never applied).
   - **Inline `style="…"` beats a stylesheet `:hover` rule.** If an element sets
     its base colour inline, a `:hover` rule silently does nothing — move the base
     colour into a CSS rule (or it won't hover). This is a recurring trap here.
   - **Direction must match the system:** hover *darkens* on light/coloured
     surfaces (the row + chrome idiom). It may only *lighten* where darkening is
     impossible (a pure-black surface). Never lighten a red/white surface on hover.

---

## Releasing / auto-updater

See `RELEASE-UPDATER.md`. Builds are signed + notarized (Apple creds in `.env`,
local only) and updater-signed (key at `~/.tauri/buddy-updater.key`). Ship a new
version by bumping `package.json` + `src-tauri/Cargo.toml` + `tauri.conf.json` in
lockstep, building, then `gh release create` with the DMG, `Buddy.app.tar.gz`,
and a `latest.json` manifest. The installed app auto-checks and shows an update
banner. Repo is public (MIT).

## 🩺 RULE 3 — Self-diagnose at session start; self-test before blaming the user's setup.

Buddy has a **privacy-safe diagnostics log** and a **two-device live sync harness** so
field reports can be traced and reproduced WITHOUT the user babysitting.

1. **At every session start** (and whenever the user reports weirdness), read the
   event log first: `pnpm diag errors` (or `pnpm diag 60`). It's structured JSONL at
   `~/Library/Application Support/fyi.whale.buddy/buddy-events.jsonl` — sync passes,
   conflicts, watchdog resets, healed edit-guards, rollover branches, banner shows.
   **It never contains task text** (event names / counts / versions / timings only —
   keep it that way; never log user content). iOS writes the same schema on-device
   (`BuddyDiag.swift`); surface it via a future Settings → Export diagnostics.
2. **Reproduce cross-device bugs yourself** with `pnpm sync:live` — it boots TWO
   isolated browser "devices" paired on the real Supabase backend with a throwaway
   syncKey and drives future→today, undo, dedupe, convergence end-to-end. Extend it
   with the user's exact repro before touching the merge code.
3. The state files are forensics: `buddy-state.json` (+ `.recovery`, localStorage
   `.bak`) show ids (uppercase = iPhone-minted, lowercase = Mac), per-row `v`, and
   tombstones — often enough to reconstruct what happened without any log.

## 🎥 RULE 4 — See it, don't infer it (Mac AND iOS)

Any claim about interaction, motion, scrolling, keyboard behavior, or layout
MUST be verified by OBSERVING the running app — reading the code and reasoning
about it is not verification (that's how "Future scrolls now" shipped broken).

- **Mac web:** serve `dist/` + Playwright — screenshots per state, computed-style
  reads, and transition sampling (poll `getComputedStyle().transform` mid-flight).
- **Mac native:** `pnpm tauri dev` + `screencapture` / screen recording.
- **iOS:** a BOOTED simulator, always: build, install, launch (`xcrun simctl`),
  seed deterministic state with the DEBUG `-uiFixture` harness, drive real
  gestures (XCUITest), and capture evidence —
  `xcrun simctl io booted screenshot` / `recordVideo`.
- **Motion/gesture bugs need video or frame sampling**, not a single still.
- Save all captures to the session scratchpad; report what was observed vs.
  what remains unverified. "The code should do X" is a hypothesis, not a result.

## 🚢 RULE 5 — Buddy is TWO apps on DIFFERENT release rails. iOS is manual; "merged" ≠ "shipped".

Buddy = **Mac** (Tauri, `dist/` + `src-tauri/`) **and iOS** (Swift, `ios/`), plus the
marketing site (`buddy-site`, Vercel). They do NOT ship together automatically:

- **Mac** auto-releases on merge to `main` (GitHub Actions → signed DMG + updater).
  Merging = shipped.
- **iOS** has **NO CI release**. It ships ONLY when someone runs `fastlane beta` from
  `ios/` locally (needs `ASC_*` + `BUDDY_CLOUD_*` in the shell env). Merging does
  **nothing** for iOS — the phone has nothing to update to.

**Any change to SHARED plumbing — sync/wire/merge/crypto, escalation tokens, anything
both apps consume — is only HALF shipped when the Mac releases.** Leaving iOS behind
recreates the exact version-skew problem the change was meant to fix (this is how the
2026-07-18 split-brain nearly stranded the user again).

Therefore:
1. A shared-plumbing change is NOT done until BOTH the Mac release AND a new iOS
   TestFlight build (`fastlane beta`) are cut. Say "shipped to Mac; iOS still owed" —
   never just "shipped".
2. **Never tell the user to "update in TestFlight" without first confirming a newer
   build exists** (the `beta` lane's `latest_testflight_build_number`, or ask).
3. Bump iOS `MARKETING_VERSION` (in `ios/project.yml`) to track the Mac version each
   release — it silently sat at `0.1.0` for months. Build number auto-increments.
4. Cross-repo coordination (which repo releases how) lives in `ECOSYSTEM.md` — keep it
   current; read it before cross-repo work.

## Foundation

Buddy's design language follows the shared Foundation system — prefer its tokens
and primitives over inventing local ones. When a colour/spacing/type value needs
to adapt to state, it belongs in a token, not inline.
