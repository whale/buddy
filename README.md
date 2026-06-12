# Buddy

A tiny macOS focus companion for ADHD. Each morning it asks for your **top three** things. All day it lives as a drawer at the right edge of your screen — hover to peek, pin to keep it open. You mark which one you're on **now**, check things off, and glance back at the **last 7 days** so you never lose your place when you get yanked away.

> Status: **web prototype + build plan.** The native Mac shell comes next.

## What's here

- `index.html` — the full interactive prototype (single self-contained file: Tailwind via CDN + vanilla JS). Open it in a browser, or serve it:
  ```
  cd buddy && python3 -m http.server 4399
  # then open http://localhost:4399
  ```
- `PLAN.md` — the thorough, adversarially-reviewed plan for the overnight build (persistence, daily rollover, completion confetti + settings, keyboard control, animation pass) and the Phase-2 Mac shell.

## The prototype, in a minute

- **Morning** — a calm, light screen asks for up to 3 things. Press Enter between them.
- **Drawer** — hides at the right edge; hover the thin strip to reveal, or **pin** (icon in the Buddy pill) to keep it open.
- **A thing's life** — click it to cycle **now** (grey) → **done** (struck through) → neutral. Hover to **edit** (pencil) or **remove** (×).
- **The edge** — 4 is fine; **5** turns every word red; **6** turns the whole drawer red (no 7th).
- **Last 7 days** — the bar at the bottom rises to the top and reveals your history. Pull an unfinished thing forward with **+** (it gets a TODAY badge); undo removes it.

## Design

Built to match the Foundation / Shapeshifter visual language: Graphik type, flat (no shadows), 24px-radius white cards, `#f4f4f4` selected fill, `#d9d9d9` hairlines.

## Roadmap

1. **Overnight (web-complete):** persistence, daily rollover + real history, 100-party-parrot completion confetti (toggle in settings), full keyboard control, slight/speedy animations. See `PLAN.md`.
2. **Mac shell (Tauri):** menu-bar item, global hotkey, right-edge reveal, pin, wallpaper-behind. See `PLAN.md` §11.
