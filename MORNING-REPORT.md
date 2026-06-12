# Buddy — Morning Report
_Built overnight, June 11–12, 2026. Written for the owner._

---

## The short version

The web app is done and fully verified. Every feature works. The Mac wrapper code is written but needs you to boot it up for the first time — that's a 30–60 min install you do once, then it's fast forever. Steps are in `README-MAC.md`.

---

## What's working right now (open `index.html` in a browser to try it)

**Your day starts fresh every morning.**
Each morning Buddy asks for your top three things. It saves everything — tasks, which one you're working on now, your settings — so if you close the tab and come back, nothing is lost. At midnight it quietly rolls your day over and archives it to history.

To try it: open `index.html` in Chrome or Safari. You'll see the morning screen.

**Your history goes back 7 days.**
The thin bar at the bottom of the drawer is the history trigger — click it to slide up your last 7 days. Empty days show dimmed; days with tasks show what you did and whether you finished each one.

To try it: click the bar at the bottom of the drawer. It slides up.

**Pull unfinished things forward.**
If you left something undone yesterday, hit `+` next to it in history. It lands in today's list with a "today" badge so you remember where it came from. Hit "undo" to send it back.

**Completing a task throws confetti.**
100 party-parrots rain down the screen when you check something off. The parrots clean themselves up in about 2 seconds.

To try it: click any task once to mark it "now," click again to mark it "done."

**Turn confetti off in Settings.**
The gear icon (next to the pin in the Buddy pill at the top) opens a settings sheet. One toggle: "Celebrate completed tasks." Flipping it off stops confetti immediately and remembers the choice across reloads.

To try it: click the gear, flip the toggle, complete a task — silence.

**Full keyboard control.**
Buddy can be driven without a mouse. The backtick key (`` ` ``, top-left under Escape) opens and closes the drawer instantly. Arrow keys move a cursor ring between tasks. Enter cycles a task's state. `F` marks the one you're working on now. `E` edits. Backspace removes. `A` adds a new one.

To try it: press `` ` `` to open/close. Use ↑ ↓ to navigate, Enter to check things off.

**The red warning system.**
At 5 tasks, every word turns red — a gentle nudge. At 6, the whole drawer goes red. You can't add a 7th. The 😈 emoji appears at the cap as a pressure valve.

**Nothing breaks on bad data.**
If browser storage ever gets corrupted, Buddy boots clean instead of crashing. The bad data is saved to a backup key so nothing is silently lost.

---

## Screenshots to look at

These are in `.screenshots/` — open them in Preview or just Finder Quick Look (spacebar):

| File | Shows |
|------|-------|
| `morning.png` | The morning screen, 3 empty slots |
| `list-3-tasks.png` | Three tasks in progress |
| `soft-cap-red.png` | 5 tasks — words turn red |
| `hard-cap-red.png` | 6 tasks — whole drawer goes red |
| `history-open.png` | History panel slid up, 7 days visible |
| `settings-sheet.png` | Settings open, confetti toggle visible |
| `confetti-midburst.png` | Parrots mid-burst after completing a task |
| `phaseA-morning-firstrun.png` | First-run morning (demo history pre-seeded) |
| `phaseA-history-seeded.png` | History panel with real archived day |

---

## Known rough edges

**Parrot GIF is a placeholder.** The party-parrot image host was unreachable during the build, so confetti currently fires 100 🦜 emoji instead of animated GIFs. To get the real parrots, run this once in Terminal from the `buddy/` folder:
```
curl -L -o assets/parrot.gif https://cultofthepartyparrot.com/parrots/hd/parrot.gif
```
No code change needed — it picks up the file automatically.

**Two expected console messages.** When serving locally you'll see a Tailwind CDN warning ("should not be used in production") and a 404 for the parrot GIF. Neither breaks anything — they're known and harmless.

**The Mac shell is unverified.** See the section below.

---

## Phase C: Mac shell — what's left for you

The Tauri wrapper code is written and sitting in `src-tauri/`. It configures the window to be transparent, frameless, always on top, and anchored to the right edge. The menu-bar icon and global hotkey are wired up. But I couldn't run it — that requires Rust installed on your machine, and the first compile takes 30–60 minutes.

**This is the one thing I need you to do.** The steps are in `README-MAC.md` (plain language, numbered, no jargon). The short version:

1. Open Terminal
2. Install Xcode command-line tools (one command, one button click)
3. Install Rust (one command, one keypress)
4. Run `pnpm tauri dev` from the `buddy/` folder
5. Wait 30–60 min for the first compile
6. Tell me what the Terminal says and which of the 5 tests worked

Once it's on screen, the three finicky Mac-only pieces we tune together:
- Making it appear without stealing focus from whatever you're working in
- Making other windows not slide behind it (reserved space)
- Adjusting for the notch on a laptop

---

## Three open decisions from the plan (when you're ready)

**1. Where does the gear icon live?**
Right now it's in the Buddy pill alongside the pin. The alternative is a corner of the date card. Neither is wrong — it's a feel call. Look at `settings-sheet.png` and tell me if the current placement feels right.

**2. One parrot or a mix?**
The classic party-parrot (the green one) is what's spec'd. There are a dozen variants at cultofthepartyparrot.com — different colors, cowboy hat, etc. Worth a mix, or keep it one classic?

**3. A bigger flourish when all three are done?**
The plan flagged this as a possible future touch — a distinct celebration when you finish all three morning tasks, not just one. I didn't build it (per instructions, not doing this unprompted). But it's on the table if you want it.

---

_Web app: verified. Mac shell: your move. Questions or issues — paste the Terminal output and I'll fix it._
