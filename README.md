# Buddy

A tiny macOS focus companion for ADHD. Each morning it asks for your **top three** things. All day it lives as a drawer at the right edge of your screen — hover to peek, pin to keep it open. You mark which one you're on **now**, check things off, and glance back at the **last 7 days** so you never lose your place when you get yanked away.

> Status: **web app complete (Phase A + B).** The native Mac shell comes next.

## What's here

- `index.html` — the full interactive web app (single self-contained file: Tailwind via CDN + vanilla JS). Open it in a browser, or serve it:
  ```
  cd buddy && python3 -m http.server 4399
  # then open http://localhost:4399
  ```
- `assets/parrot.gif` — the party-parrot confetti image (see *Confetti asset* below).
- `PLAN.md` — the thorough, adversarially-reviewed plan for the overnight build (persistence, daily rollover, completion confetti + settings, keyboard control, animation pass) and the Phase-2 Mac shell.
- `.screenshots/` — captured states for review (morning, list, soft/hard-cap red, history, settings, confetti mid-burst). Gitignored.

## The prototype, in a minute

- **Morning** — a calm, light screen asks for up to 3 things. Press Enter between them.
- **Drawer** — hides at the right edge; hover the thin strip to reveal, or **pin** (icon in the Buddy pill) to keep it open.
- **A thing's life** — click it to cycle **now** (grey) → **done** (struck through) → neutral. Hover to **edit** (pencil) or **remove** (×).
- **The edge** — 4 is fine; **5** turns every word red; **6** turns the whole drawer red (no 7th).
- **Last 7 days** — the bar at the bottom rises to the top and reveals your history. Pull an unfinished thing forward with **+** (it gets a TODAY badge); undo removes it.
- **Completing a task throws confetti** — 100 party-parrots rain down. Turn it off in **Settings** (the gear in the Buddy pill).

## Keyboard control

Buddy is fully driveable from the keyboard (a stand-in for the future global hotkey):

| Key | Does |
|-----|------|
| `` ` `` (backtick) | Toggle the drawer open/closed (instant, no animation) |
| ↑ / ↓ | Move the cursor ring between today's tasks and the Add row |
| Enter | On a task: cycle it (→ done throws confetti). On Add: add + edit |
| F | Set the cursored task as **now** (focused) without cycling |
| E | Edit the cursored task |
| ⌫ / Delete | Remove the cursored task |
| A or + | Add a new task and start editing |
| Esc | Commit an edit, else close history, else close the drawer |

The **cursor ring** (a thin outline) is navigation; the grey **now** fill is a task *state*. They look different on purpose. While you're editing a task, the global keys go quiet so they don't double-fire.

## Confetti asset

The celebration uses **party-parrot GIFs** (`assets/parrot.gif`, sourced from
[cultofthepartyparrot.com](https://cultofthepartyparrot.com)). If the file is missing or
couldn't be downloaded, Buddy automatically falls back to the 🦜 **emoji** — same burst,
no broken images. Drop a real `assets/parrot.gif` in and it upgrades on next load, no code
change needed.

> **Note (this build):** the GIF host was unreachable from the build sandbox, so the
> bundled confetti currently uses the **🦜 emoji fallback**. To use the real GIF, run
> `curl -L -o assets/parrot.gif https://cultofthepartyparrot.com/parrots/hd/parrot.gif`
> from the `buddy/` folder.

Confetti is **skipped entirely** when your system is set to *reduce motion* (the Settings
toggle then shows as disabled/overridden, not silently dead).

## Console messages (expected, not errors)

Serving the app logs two benign messages: the **Tailwind CDN** "should not be used in
production" warning (by design — we bundle Tailwind when we wrap for Mac), and, until the
real GIF is added, a **404 for `assets/parrot.gif`** that triggers the emoji fallback.
Neither breaks anything.

## Design

Built to match the Foundation / Shapeshifter visual language: Graphik type, flat (no shadows), 24px-radius white cards, `#f4f4f4` selected fill, `#d9d9d9` hairlines.

## Roadmap

1. ✅ **Web-complete (done):** persistence + daily rollover + real history (Phase A); 100-party-parrot completion confetti with a settings toggle, full keyboard control, and a slight/speedy animation pass (Phase B). All self-verified with Playwright.
2. **Mac shell (Tauri):** menu-bar item, global hotkey, right-edge reveal, pin, wallpaper-behind. See `PLAN.md` §11.

## Credits

Menu-bar icon: the "sticker" glyph from [Lucide](https://lucide.dev) (ISC License) — free for open-source and commercial use.
