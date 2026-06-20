# iOS ⇄ Mac Parity Plan

Goal: the iOS app matches the Mac app — **functionality (UX) first, then visual style.**
Mac (`dist/index.html`) is the source of truth. Target: UI parity from ~4/10 → 9/10.

Reference screenshots in `.screenshots/`: `mac-daily-lvl0`, `mac-morning`, `mac-lvl2`, `ios-daily-lvl0`.

Execute **one item at a time**, reviewing each before moving on. Check items off as they land + verify.

---

## What the comparison showed

| Aspect | Mac | iOS (today) |
|---|---|---|
| Date header | weekday + month stacked, giant numeral on the right | small inline "Saturday 20", no month |
| Task list | inside a **bordered rounded card**, generous rows, dividers | flat full-bleed list, tighter |
| Row numbers | none | shows 1 / 2 / 3 |
| Focused ("now") | grey-fill highlighted row | **not shown at all** |
| Donezo | struck row **at the top** of the card | a "DONEZO" section **at the bottom** |
| Morning view | 3-slot planner + Skip / Buddy! bar | **missing entirely** |
| Typography | Inter (bundled) | system San Francisco |
| Escalation lvl0/1/2 | ✅ | ✅ (faithfully ported) |

---

## Phase 1 — UX / functionality parity (do first)

- [x] **1. Morning view** — ✅ shows on a fresh/rolled day with yesterday's carried-over tasks pre-loaded, Add row, Skip + Buddy! controls; both set `morningDone`. Verified in simulator + code-reviewed (fixed: blank-task race on fast Buddy! tap, Skip wired to `skipMorning`). Styling polish deferred to item 11.
- [x] **2. Focused / "now" state** — ✅ focused task now gets the grey "now" fill (`#f4f4f4`; red+15%-black `#c33d41` at lvl2), matching the Mac. Covers item 9. Verified in sim + 4 cycle/cap XCTests (focus, single-focus, complete, cap).
- [ ] **3. Donezo placement** — move completed rows to the **top of the list inline** (Mac model), not a bottom section.
- [x] **4. Erase all data** — ✅ "Erase all data" (Danger zone) in Settings with a confirm alert → `store.eraseAll()` (clears + stamps `erasedAt` sync barrier). Build + store test verified.
- [x] **5. Caps + add-at-cap behavior** — ✅ confirmed soft 5 / hard 6; add returns nil past hard cap; Add row hidden at cap. Covered by `testAddBlockedAtHardCap` + the morning carry-cap test.

## Phase 1.5 — UX gaps the owner flagged

- [x] **A. Check-off affordance** — ✅ tappable circle completes each row (filled check on done → restore). Also fixed: swipe actions were DEAD outside a List → replaced with a long-press menu (edit / sleep / delete).
- [x] **B. Report a bug** — ✅ Settings → Feedback → "Report a bug" opens a prefilled GitHub issue (app version + device + iOS in the body).
- [x] **C. Dev restart/reset** — ✅ DEBUG-only Developer section: "Reset data (show morning)" + "Restart app (quit)".

## Phase 2 — Visual style parity (4/10 → 9/10)

- [x] **6. Font** — use the **system San Francisco font** (owner's call — no Inter bundle).
- [x] **7. Date header** — ✅ weekday + month stacked + giant numeral, matches `mac-daily-lvl0`.
- [x] **8. Task card** — ✅ bordered rounded card + subtle shadow, generous rows, numbers removed (circle replaces them).
- [x] **9. Focused highlight** — ✅ done with item 2.
- [x] **10. Donezo style + placement** — ✅ struck inline "Donezo. <title>" at the TOP of the card, matching the Mac.
- [ ] **11. Morning view styling** — match `mac-morning` (Skip / Buddy! pill).
- [ ] **12. Final sweep** — screenshot iOS at lvl0/1/2 + morning, side-by-side vs Mac; iterate to 9/10.

---

## Notes
- Each item: build → run in simulator → screenshot → (agent) review → commit.
- Sync wiring (network + live DB + QR UI) is a **separate** track (see `IOS-COMPANION-PLAN.md`); not part of this parity plan.
