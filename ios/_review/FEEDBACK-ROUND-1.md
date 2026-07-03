# iOS parity — round 1 feedback (2026-07-02) — ✅ ALL ADDRESSED

Status: #1–#7 fixed & verified in the sim; #8 core issue (selected icon) fixed via #6.
Commits on `fix/ios-visual-parity` / PR #61. 37 tests pass. Remaining minor deltas at bottom.

---


From the user reviewing comparison.html. Fix these on `fix/ios-visual-parity`.
**Rule: the Mac already has all this logic — port it, don't reinvent.**

## Daily view
1. **Equal-height active rows, fill the viewport, NO scroll.** Port the Mac flex logic:
   - active rows + Add row = `flex:1 1 auto; min-height:0` → share the remaining height EQUALLY.
   - Donezo/done rows = `flex:0 0 auto` → compact.
   - The list card fills the viewport height; all tasks fit without scrolling.
   - SwiftUI: list card `.frame(maxHeight:.infinity)`; active + Add rows `.frame(maxHeight:.infinity)`
     (VStack distributes equally); done rows fixed. Remove the trailing Spacer.
2. **New task takes disproportionate space** (image 2) — same root cause; fixed by #1.
3. **Unnecessary bottom spacing** before the keyboard (image 4) — remove; falls out of #1.

## lvl2 (red) — image 3
4. **Red = panels ONLY, not the whole background.** Backdrop stays neutral (#ececee) at lvl2;
   only the two cards go red (like the Mac desktop showing behind red cards).
   - `EscalationTheme.screenBackground` currently returns red at lvl2 → make it neutral.
5. **Dividers must span full width** at lvl2 (they blend now because bg == card). Fixing #4 restores them.

## Sheets (History + Settings) — images 5 & 6
6. **The selected chrome icon must stay VISIBLE.** On the Mac the sheet slides up over the LIST
   card (card 2) only — card 1 (chrome + date) stays on top, and the triggering icon shows a
   SELECTED state (filled dark circle, bg=--sel-bg, icon=--sel-ink).
   - Re-architect: present Settings/History as an in-app overlay over card 2 (NOT a native
     .sheet/.fullScreenCover that covers everything).
   - Add the chrome-btn selected state (filled circle) — calendar when History open, gear when
     Settings open, pin when pinned.
7. **Review ALL THREE history tabs** (Future / Done / Skipped) against the Mac, not just Done:
   rotating done-words (not always "Donezo."), row spacing, the +/× restore affordances,
   empty states, segmented-control exact look.
8. **Settings parity pass** (image 6): match the Mac's rows/spacing/dividers; reconcile which
   rows show (Mac has "Give Buddy room" [Mac-only], "Export my done tasks" w/ count, Quit/Restart).

## Verify (every fix)
Rebuild → `-uiFixture lvl0/lvl1/lvl2/empty/morning/history/settings` → screenshot → compare to Mac.
Needs THIS Mac's iPhone simulator (a cloud agent can't render iOS).
