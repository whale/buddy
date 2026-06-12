# Buddy — turning it into a real Mac app

This turns the Buddy web page into a little Mac app that lives in your menu bar
(the strip at the very top of your screen) and slides in on the right edge of your
display.

> **Heads up — this part is not tested yet.** I wrote all the Mac wrapper code, but
> I could not run it (I can't install the Mac developer tools in my environment).
> So the very first time you run it, expect one or two small errors you'll paste to
> me and I'll fix in a minute. That's normal and expected. The web app itself
> (the part you already saw working) is fully tested — this is just the shell
> around it.

---

## What you need to do once (about 30–60 minutes, mostly waiting)

### Part 1 — Install the Mac developer tools

**Step 1.** Open the **Terminal** app. (Press `Cmd + Space`, type `Terminal`, press Return.)

**Step 2.** Copy this whole line, paste it into Terminal, press Return:

```
xcode-select --install
```

A box pops up. Click **Install**. Wait for it to finish (a few minutes). If it says
they're already installed, great — skip to Step 3.

**Step 3.** Copy this whole line, paste it into Terminal, press Return:

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

This installs **Rust** (the engine that builds Mac apps). When it asks you a
question, just press Return to accept the default.

**Step 4.** Close the Terminal window completely, then open a fresh one. (This makes
Rust available.)

**Step 5.** Copy this line, paste it, press Return — to confirm Rust is ready:

```
rustc --version
```

If it prints a version number (like `rustc 1.8x.x`), you're good. If it says
"command not found," tell me and I'll help.

---

### Part 2 — Install the app's helpers

**Step 6.** Copy this whole line, paste it, press Return:

```
cd ~/Projects/buddy && pnpm install
```

This downloads the Tauri tool (the thing that packages the web page into a Mac app).
Takes under a minute.

> If it says `pnpm: command not found`, paste this instead, press Return, then redo
> Step 6:
> ```
> corepack enable
> ```
> Still stuck? Paste `npm install -g pnpm` and press Return, then redo Step 6.

---

### Part 3 — Run Buddy as a real app (the first run is the slow one)

**Step 7.** Copy this line, paste it, press Return:

```
cd ~/Projects/buddy && pnpm tauri dev
```

**Step 8.** Now wait. **The first time only, this takes 30–60 minutes** while it
builds the engine. You'll see lots of green text scrolling — that's normal, leave it
alone. (Every run after this one takes just a few seconds.)

**Step 9.** When it finishes, look for:

- A small **icon in your menu bar** (top-right of your screen).
- A **tall panel sliding in on the right edge** of your screen — that's Buddy.

---

## How to test that the Mac behavior works

Once Buddy is open, check these one at a time. Note which ones work and which feel
off, and tell me — these are the fragile parts I expect to tune.

1. **Menu-bar icon click** — click the Buddy icon in the menu bar. The panel should
   hide. Click again — it should come back on the right edge.

2. **Right-click the menu-bar icon** — you should see a small menu with
   "Show / Hide Buddy" and "Quit Buddy."

3. **The backtick key** — press the `` ` `` key (top-left of your keyboard, under
   Escape). Buddy should pop to the front. ⚠️ **Expected annoyance:** while Buddy is
   running, this key is "grabbed" system-wide, so you may not be able to type a
   normal backtick anywhere else. If that bugs you, tell me and I'll switch the
   shortcut to a combo like `Cmd + \`` instead.

4. **Right-edge position** — the panel should sit flush against the right side of the
   screen and run the full height.

5. **See-through corners** — Buddy has no window frame and a transparent background,
   so your wallpaper should show through any rounded corners. (Good news: Buddy's
   design is flat and doesn't use the one transparency feature that's broken on
   macOS, so this should "just work.")

**To stop it:** click the Terminal window and press `Ctrl + C`. Or right-click the
menu-bar icon and choose **Quit Buddy**.

---

## Known rough edges (these need us to tinker together on your machine)

These are real and expected — they're the parts that genuinely can't be built blind:

- **"Always on top" but still steals focus.** Right now, summoning Buddy makes it the
  active app. The ideal is a *non-activating panel* (it appears without yanking focus
  from what you were doing). That needs a deeper Mac-specific tweak we'll do live —
  it can only be tested on the real machine.

- **No "reserved space."** Other windows can still slide *behind* Buddy. Making the
  desktop treat Buddy's strip as off-limits is the single most finicky piece; we'll
  prototype and measure it together.

- **The notch / menu-bar overlap.** On a laptop with a notch, the very top of Buddy
  might tuck under the menu bar until we measure and nudge it down. Easy fix once we
  see it on your screen.

- **The menu-bar icon is a placeholder.** It's a plain "b." When you want a real one,
  drop a 44×44-pixel black-on-transparent PNG at
  `src-tauri/icons/tray.png` and we'll wire it in.

None of these block you from seeing Buddy run — they're polish we do once it's on
screen.

---

## What to send me after the first run

Just copy the last chunk of text from the Terminal (especially anything red) and
paste it to me, plus a one-line note on which of the 5 tests above worked. That's
everything I need to push it the rest of the way.
