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
Use **Report a bug…** in the menu-bar icon's menu — it captures a screenshot of just Buddy plus a few diagnostics and sends them to the maintainer. That's the best way to send feedback.

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

## For developers & contributors

Buddy is **MIT-licensed and open source**. The Mac app is the shipped product; an iOS companion is in early development. Everything is **local-first** — it works fully offline, and sync is opt-in (below), so you can clone, build, and run with **no backend and no secrets**.

### Repository layout

| Path | What it is |
|------|-----------|
| `dist/index.html` | The entire Mac web app — vanilla JS + locally-bundled Tailwind & Inter. No build step. |
| `src-tauri/` | The **Tauri v2** (Rust) macOS shell — tray, window, durable-state commands. |
| `ios/` | The **iOS companion** (SwiftUI, generated with XcodeGen, shipped with fastlane). Early WIP. |
| `api/` | A serverless function for bug-report intake (see [Bug reports](#bug-reports)). |
| Plans & runbooks | `RELEASE-UPDATER.md`, `IOS-COMPANION-PLAN.md`, `DATA-SAFETY-PLAN.md`, `BUG-REPORTS.md`, `CLAUDE.md`. |

### Build & run the Mac app

```bash
cd dist && python3 -m http.server 4500    # the web app alone (fastest UI loop) → http://localhost:4500
pnpm tauri dev                            # the native Mac app
```

Before every release the browser smoke test must pass — `await window.__buddy.smokeTest()` → `{ ok: true }`. See **`CLAUDE.md`** (design + verify rules) and **`RELEASE-UPDATER.md`** (sign / notarize / publish).

### Build & run the iOS app

Needs Xcode and [XcodeGen](https://github.com/yonsm/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is **generated** from `ios/project.yml` (not committed).

```bash
cd ios
xcodegen generate
open Buddy.xcodeproj    # then ⌘R to run in the Simulator
# …or headless:
xcodebuild -scheme Buddy -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

To run it on **your own iPhone**, open the project in Xcode and set the signing team to your own Apple ID (a free account works for 7-day local builds). Maintainer TestFlight builds go through fastlane:

```bash
cd ios && fastlane beta    # needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH set
```

### Sync (planned — opt-in, local-first)

Buddy stores your data **on your own machine** and works fully offline. Cross-device sync (Mac ⇄ iPhone) is **opt-in** and not wired up yet. The design:

- A **Supabase** backend you supply yourself (URL + anon key). Nothing is baked into the app — a fork runs **local-only by default**, so cloning and building needs no accounts.
- Devices pair by **scanning a QR code** carrying an auto-generated sync key — no login, no email. One synced document, last-write-wins with a local backup.

Full design in **`IOS-COMPANION-PLAN.md`**; how local data is kept safe in **`DATA-SAFETY-PLAN.md`**.

### Bug reports

In-app **Report a bug** posts a screenshot + diagnostics to a small serverless function (`api/bug-report.js`) that files a **private** GitHub issue. It's inactive until you deploy it — see **`BUG-REPORTS.md`** for the ~10-minute setup (private repo → token → Vercel). Until then it falls back to an email draft.

## Credits

- Menu-bar + app icon: the "sticker" glyph from [Lucide](https://lucide.dev) (ISC License).
- Completion confetti: party-parrots from [cultofthepartyparrot.com](https://cultofthepartyparrot.com).

## License

[MIT](LICENSE) © Matthew Matsuzaki
