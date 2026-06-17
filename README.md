# Buddy

A tiny, calm macOS focus companion — built for ADHD brains.

Each morning Buddy asks for your **top three** things. All day it lives quietly in your **menu bar**, with a drawer that slides out from the right edge of your screen. You mark which one you're on **now**, check things off (with a little celebration), and glance back at what you've finished — so you never lose your place when life yanks you away.

---

## ⬇️ Download & try it

**[Download the latest version →](https://github.com/whale/buddy/releases/latest)**

On that page, grab the **`Buddy_…_universal.dmg`** file.

**Requirements:** macOS 13 (Ventura) or later · works on both Apple Silicon and Intel Macs.

### Install (about 30 seconds)
1. **Open** the downloaded `.dmg`.
2. **Drag Buddy** onto the **Applications** folder.
3. Open **Applications** and **double-click Buddy**.
4. The first time, macOS asks *"Buddy was downloaded from the Internet — open?"* — click **Open**. (It's signed and notarized by Apple, so there's no scary warning.)
5. **Look at your menu bar** (top-right of your screen) — Buddy lives there as a little sticker icon. There's no Dock icon; the menu bar is home.

### Where did it go?
Buddy is a **menu-bar app**, so it won't show in your Dock. Click the sticker icon up top to show/hide it, open settings, or quit. The drawer also reveals when you move your mouse to the **right edge** of your screen.

### Updates are automatic
Buddy checks for new versions on its own. When one's ready, a banner slides in offering **Install & Relaunch** — one click and you're up to date. (You can also check manually in **Settings → Check for Updates**.)

### Something broken or weird?
Use **Report a bug…** in the menu-bar icon's menu — it attaches a screenshot of just Buddy plus logs to an email draft. That's the best way to send feedback.

---

## How to use it, in a minute

- **Morning** — a calm screen asks for up to **3** things. Press Enter between them.
- **A task's life** — click it to set it as **now**, click again to mark it **done**. Done tasks celebrate with confetti, then slide up to the top as **"Donezo."** rows (and also file themselves under **Calendar → Done → Today**). Hover any done row for the **↩ undo** to bring it back.
- **The gentle nudge** — 4 tasks is fine. **5** turns the text red; **6** turns the whole drawer red — Buddy's quiet way of saying *that's a lot*. Finishing things eases the red back down.
- **Pin it** — the pin icon keeps the drawer open so it doesn't tuck away.
- **History** — the calendar icon shows what you've finished and what's coming up.

## Keyboard control

Buddy is fully driveable from the keyboard:

| Key | Does |
|-----|------|
| `` ` `` (backtick) | Toggle the drawer open/closed |
| ↑ / ↓ | Move between today's tasks and the Add row |
| Enter | On a task: cycle it (→ done throws confetti). On Add: add + edit |
| F | Set the cursored task as **now** without cycling |
| E | Edit · ⌫ / Delete | Remove · A or + | Add a task |
| Esc | Commit an edit, else close history, else close the drawer |

---

## For developers

Buddy is a single self-contained web app (`dist/index.html`, vanilla JS + locally-bundled Tailwind & Inter) wrapped in a **Tauri v2** macOS shell (`src-tauri/`). MIT licensed.

```bash
# Run the web app standalone (fastest to iterate on the UI)
cd dist && python3 -m http.server 4500    # → http://localhost:4500

# Run the native Mac app
pnpm tauri dev
```

Before every release, run the core smoke test in the browser console — it must return `{ ok: true }`:

```js
await window.__buddy.smokeTest()
```

See **`CLAUDE.md`** for the design + verification rules, **`RELEASE-UPDATER.md`** for the build/sign/notarize/publish flow, and **`PLAN.md`** for the original spec.

## Credits

- Menu-bar + app icon: the "sticker" glyph from [Lucide](https://lucide.dev) (ISC License).
- Completion confetti: party-parrots from [cultofthepartyparrot.com](https://cultofthepartyparrot.com).

## License

[MIT](LICENSE) © Matthew Matsuzaki
