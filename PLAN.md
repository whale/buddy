# Buddy — Overnight Build Plan (v1, web-complete)

**Status:** Ready for an autonomous overnight one-shot build (adversarially reviewed).
**Date:** 2026-06-11
**Working file:** `/Users/whale/Projects/buddy/index.html` (single self-contained file + one asset)

---

## 1. Goal

Make the current Buddy prototype a **complete, self-contained web app** with real logic: it remembers your day, rolls over to a new day, celebrates completions, has a settings menu, full keyboard control, and slight/speedy animation. Self-verifiable headlessly. The Mac (Tauri) shell comes later, together — §11.

## 2. Scope decision (read first)

**Overnight delivers:** the complete web app, self-verified via Playwright.
**Overnight does NOT deliver:** native Mac pieces (menu-bar, global hotkey, reserved-space window, login item) — they can't be verified headlessly. Phase 2 (§11).

**Critical context the agent must internalize:** the current prototype has **NO persistence** — `state` is in memory, `showMorning()` runs on every boot, history is hard-coded sample data. So persistence/rollover/real-history are **net-new builds**, not regressions to protect. Do not treat them as already-passing.

**Build order is data-first.** Phase A (the data layer) ships and self-verifies *before* Phase B (the delight layer) starts. If the night runs long, the load-bearing data layer is still done and proven. Each phase has a hard verification gate; do not advance past a red gate.

---

## 3. Feature specs

### 3.1 Daily lifecycle + persistence  *(gap #1)* — PHASE A

**Persistence:** all state in `localStorage` key `buddy.v1`. Save is **debounced ~250ms** on change, and **force-flushed synchronously** on `visibilitychange:hidden` / `beforeunload` (cancel the timer and write immediately — a trailing debounce gets killed by tab close).

**Data model:**
```json
{
  "version": 1,
  "today": { "date": "2026-06-11",
    "items": [ { "id": "n1", "text": "Finish the prototype", "state": "focused", "src": null } ] },
  "history": [
    { "date": "2026-06-10", "weekday": "Tuesday",
      "items": [ { "id": "h-1718000000-0", "text": "Ship newsletter", "done": true } ] }
  ],
  "settings": { "confetti": true },
  "pinned": false
}
```
- `state`: `neutral | focused | done`; one `focused` max.
- `src`: a **history item id** if pulled forward (drives the TODAY badge + undo).
- **History item ids are stable and persisted** (assigned at archive time, e.g. `h-${epochSeconds}-${index}`). Never recompute positional keys — `src` linkage and undo break across reload otherwise.

**Load + migrate (boot sequence — this REPLACES the current boot):**
1. `migrate(raw)`: `try { JSON.parse }`. If it throws, OR `version !== 1`, OR `today` missing/malformed → copy the bad value to `buddy.v1.bak`, discard, boot fresh (empty today, empty history). A corrupt blob must never reach render. Keep a `migrate(blob)` switch on `version` (empty body for now) so v2 won't need a wipe.
2. Run **rollover** (below).
3. **Then** decide morning: show it only if `today.items` is empty AND it's a fresh/rolled day. Restoring an in-progress same-day session must NOT show the morning.

**Rollover (`maybeRollover()`):**
- Compare stored `today.date` to the **current local date** (`YYYY-MM-DD`, local tz).
- Same date → restore verbatim. No morning.
- Older date → **only if `today.items.length > 0`**, archive `{date, weekday, items: items.map(i => ({id, text, done: i.state==='done'}))}` to the front of `history`. (Empty/skipped day → just advance the date silently, archive nothing.) Then `today = {date: today, items: []}`, clear `focused`, show morning. Trim `history` to 30 days.

**Live midnight trigger (this is a pinned, always-open drawer — boot won't fire at midnight):** run `maybeRollover()` on `window` focus, on `visibilitychange:visible`, AND on a `setInterval(~60s)`. **Never roll over while `editingId !== null`** — defer until the edit commits.

**History panel:** show the **last 7 calendar days** (excluding today). Build the 7 dates; match `history` by `date`; a day with a record shows its items (done/undone preserved), a day with none shows just the weekday name, dimmed.

**No auto carry-forward** (confirmed "fresh start, history kept"). Pull-forward is manual via `+`.

### 3.2 Keyboard control  *(gap #2 — "option y")* — PHASE B

One selection model. A transient **keyboard cursor** (subtle ring) is the navigation; the grey **"now"/focused** is a task *state* you can set. They are different and must look different — document this in code.
- **`` ` ``** — toggle drawer open/closed (stand-in for the future global hotkey).
- **↑ / ↓** — move the cursor between today's tasks (and the Add row).
- **Enter** on a cursored task — cycle its state (→ done fires confetti). On the Add row — add + edit.
- **F** on a cursored task — set it as "now" (focused) without cycling.
- **E** — edit. **⌫/Delete** — remove. **Esc** — commit+exit edit, else close drawer.
- **Guard:** while `editingId !== null`, the global keyboard layer is inert (Enter commits the edit, doesn't cycle). No double-fire.
- Morning overlay keyboard already built (Enter advances/starts, Esc skips).

### 3.3 Completion celebration + Settings  *(gap #3)* — PHASE B

**Confetti — 100 party-parrot GIFs, 24×24** (owner's explicit choice; the toggle is the escape hatch):
- **Fires only on a state transition *into* `done`, from any source** (click, keyboard, check). Does **NOT** fire when a `done` item is re-rendered, nor when a `done` item is pulled forward from history.
- 100 nodes, all reusing one cached `assets/parrot.gif` `src`. Absolute-positioned in a single overlay container, `pointer-events:none`, `will-change:transform`, CSS-keyframe burst (random x, fall/drift, slight rotation, 0–250ms stagger), ~1.8s.
- **One burst in flight at a time:** a new completion clears the existing container and starts fresh (mashing a row can't stack 500 parrots).
- **Cleanup belt-and-suspenders:** remove on `animationend` AND a hard `setTimeout(removeContainer, 2000)` backstop (animationend may not fire if backgrounded). Also clear any in-flight container before a new burst.
- **`prefers-reduced-motion: reduce` → skip the burst entirely**, and show the settings toggle as **disabled/overridden** (not silently dead) so it doesn't read as broken.

**Settings menu:** a **gear** icon in the Buddy pill (paired with the pin). Click → a settings sheet slides in (same language as the history sheet).
- **"Celebrate completed tasks 🎉"** — toggle, default ON, persisted to `settings.confetti`, applied immediately.
- Build only this row; leave structure for future rows (morning time, theme). Close returns to the list.

### 3.4 Animation pass  *(gap #4)* — PHASE B

Slight + speedy: **120–220ms, `ease-out`**, never bouncy/slow. Implement these **literal** specs (no open-ended "polish" pass; the agent can't judge feel — `frontend-design` is reference only, not a build dependency):
- Drawer reveal/hide ~240ms (exists — confirm).
- **Last 7 days open/close: a crossfade is the spec** (~200ms) — today list fades out, history fades in, the bar relocates. (The bar "travel" animation is explicitly NOT required; crossfade is primary, not a fallback.)
- Task state change: bg + text ~140ms (exists — confirm it also eases the red theme).
- **Red theme cross-level:** crossing 4→5 / 5→6 washes the drawer red over ~200ms (not a snap).
- Add: row expands/fades in ~160ms. Remove: collapses/fades out ~160ms.
- Settings sheet slide ~220ms. Pin/desktop resize animated (exists).
- Hover states already ~120ms — keep.
- **Wrap everything in `@media (prefers-reduced-motion: reduce)` → ~0 durations.**

### 3.5 "3 is ideal"  *(gap #5)*
The morning is the anchor: **exactly 3 slots.** In-day you may add more, but 5 = all-text-red (the edge), 6 = whole-view-red (over), no 7th. No copy change — the 3-slot morning teaches the ideal.

### 3.6 Carried-over decisions
No drag (#6). Caps: soft 5 / hard 6. Add visible-but-inert at the cap. TODAY badge on the history item, reverses on red. Edit via pencil/`E`; row click cycles. Keep 😈 at the hard cap (owner's choice).

---

## 4. Settings sheet — layout
```
Buddy pill:  [pin] [⚙]                 Buddy
Settings sheet:
  Settings                              ✕
  ──────────────────────────────────────
  Celebrate completed tasks 🎉   ( ●— )
```
One card, one row. Persist on toggle. Reflect reduced-motion override on the toggle.

## 5. Architecture / files
Stay **single-file + one asset** (lowest risk, trivial to Tauri-wrap):
```
buddy/
  index.html          # whole app (Tailwind CDN, vanilla JS)
  assets/parrot.gif   # bundled party parrot (24×24 display)
  PLAN.md  README.md
  .screenshots/       # morning-review captures from the build
```
No build step. `git init` + a commit per phase. If `index.html` passes ~1.5k lines, note (don't act on) a future split before Tauri.

## 6. Build sequence (ordered; gated)

**PHASE A — data layer (must fully pass its gate before Phase B):**
1. `load()/save()` with debounce + force-flush; `migrate()` + corruption→fresh-boot guard.
2. Replace boot with: load → `maybeRollover()` → conditional morning.
3. Real history (archive on rollover, stable ids); replace sample data (seed a tiny demo history ONLY when `history` is empty, so first-run shows the panel populated).
4. Live midnight trigger (focus + visibility + 60s interval, edit-guarded).
5. **Expose `openDrawer()/closeDrawer()` and a `__buddy` test hook** (read/inject state) so verification doesn't depend on hover timers.
6. **GATE A** — run Phase-A acceptance (§7) headless; all green or fix-and-repeat. Commit.

**PHASE B — delight layer:**
7. Confetti (bundle `assets/parrot.gif`; transition-into-done only; single-burst; hard cleanup; reduced-motion skip).
8. Settings sheet + gear + toggle (persisted, wired to confetti, reduced-motion-aware).
9. Keyboard layer (§3.2) with cursor ring + edit guard.
10. Animation pass (§3.4) — literal durations; crossfade for history; reduced-motion media query.
11. **GATE B** — full acceptance (§7) + screenshots to `.screenshots/`. Commit. Update README. Leave dev server running + app open.

## 7. Acceptance criteria (state-based; honest)

**Pre-flight:** assert Tailwind actually loaded (a known class computes a non-default style); if not (offline CDN), **halt and report** — do not screenshot a broken app. "No console errors" is a **logged observation, NOT a gate** (Tailwind CDN warns by design).

**Phase A (net-new — must build & pass):**
- [ ] Persistence: set tasks + focused + pinned + `settings.confetti`; reload; all restored.
- [ ] Rollover: inject `buddy.v1` with `today.date=yesterday` + 2 items; reload → history grew by one record (those 2 items, done flags correct), `today.items` empty, morning visible.
- [ ] Skipped-day: inject yesterday + **0** items; reload → nothing archived, date advanced, morning visible.
- [ ] Same-day restore: inject today + 2 items; reload → items restored, morning NOT shown.
- [ ] Corruption: write `buddy.v1 = "{ broken"`; reload → clean empty boot, no throw, `.bak` written.
- [ ] History panel shows last 7 calendar days; empty days dimmed; done/undone preserved; pull-forward + undo survive a reload (stable ids).
- [ ] XSS: set a task text to `<img src=x onerror=alert(1)>`; reload; assert no execution and it renders as literal text.

**Phase B (net-new):**
- [ ] Confetti lifecycle: complete a task → overlay container exists with 100 children → after ≤2500ms the container is gone and node count is back to baseline. Toggle OFF → completion spawns 0. Reduced-motion → 0.
- [ ] Settings: toggle persists across reload; disabled/overridden under reduced-motion.
- [ ] Each keyboard shortcut in §3.2 performs its action; global keys inert while editing.
- [ ] Animations assert **end states only** (history open → `histBody` present; add → count+1; remove → count−1) — never assert a tween happened.

**Regression (existing — must NOT break):** red levels 0/1/2, history slide/crossfade open, TODAY badge + undo, flex-fill + equal padding, single-click Add, no text under icons, all hover states (pin-on-red, focused-clears-on-hover, row 5%/10%).

**Morning review:** full-page screenshots of each major state → `.screenshots/` for the owner to judge feel (the honest division of labor: the agent proves it *works*; the owner judges it *delights*).

## 8. Security & robustness
- All user text via `textContent` only (today's pattern; confirm history rendering too). The one injection path is contenteditable→localStorage→re-render; the XSS test above guards it.
- **Bundle** the parrot GIF locally; no runtime hot-linking. (Tailwind/Fonts CDN acceptable for the overnight web artifact *if the pre-flight confirms they loaded*; bundle them at Tauri time.)
- `localStorage` wrapped in try/catch (private mode/quota) → degrade to in-memory.
- Corrupt-blob guard (§3.1) prevents bricking.
- No runtime network calls in v1 (GIF is local).

## 9. Risks & mitigations
- 100 GIFs perf → one cached src, absolute, CSS-only, single container, hard cleanup. Verified by the lifecycle test, judged by the screenshot.
- Rollover correctness → inject fake stored dates (don't mock the clock); the four rollover tests cover same/older/empty/corrupt.
- History animation jank → crossfade is the spec; no travel-tween to chase.
- Asset fetch → download `parrot.gif` once (§10); if unreachable, emoji-🦜 fallback + README note.
- Ambition → data-first phasing with Gate A means a long night still yields a proven data layer.

## 10. Asset sourcing
Party Parrot — bundle to `assets/parrot.gif`:
`https://cultofthepartyparrot.com/parrots/hd/parrot.gif`
Display 24×24. If unreachable → small CSS/🦜 burst + README note.

## 11. Phase 2 — Mac shell (NOT overnight; together)
Wrap in **Tauri** (riff-raff stack): transparent always-on-top non-activating panel (wallpaper shows through); right-edge reveal + pin (reserved-space is the fragile part — prototype & measure); global hotkey → real `` ` `` summon; menu-bar item reflecting current "now"; login-item, multi-display, notch. Needs interactive verification.

## 12. Open questions for the morning
- Settings gear placement (Buddy pill vs date-card corner)?
- Mix in a few parrot variants, or the one classic?
- A distinct bigger flourish when all three are done? (Agent will NOT build this unprompted.)
