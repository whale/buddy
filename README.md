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

### Sync with your iPhone

The released app pairs with **Buddy for iPhone** (TestFlight, App Store soon): open Settings → **Connect & show QR**, scan it with your phone, done. No account, no password, no email.

**Privacy, plainly:** your tasks are **encrypted on your device before they sync** — the sync service stores scrambled data it cannot read, and we couldn't peek if we wanted to. The only things visible server-side are counts (how many tasks, how often you sync), never words. There's an **Erase cloud data** button in Settings that deletes your synced copy from the server (unlink your iPhone first — a still-paired device re-uploads its copy on its next sync). One honest caveat: sync is a *convenience copy*, not a backup — if you ever lose every device at once, your history starts fresh.

### Updates are automatic
Buddy checks for new versions on its own (at launch, every few hours, and when it regains focus). When one's ready, a banner slides in offering **Install & Relaunch** — one click and you're up to date.

### Something broken or weird?
Use **Report a bug…** in the menu-bar icon's menu — it captures a screenshot of just Buddy plus a few diagnostics and sends them to the maintainer. That's the best way to send feedback.

---

## How to use it, in a minute

- **Morning** — a calm screen asks for up to **3** things. Press Enter between them.
- **A task's life** — hover a task and click the **✓** to complete it; click the task's **text** to edit it (Enter saves, Tab hops to the next task). Done tasks celebrate with confetti, then slide up to the top as **"Donezo."** rows (and also file themselves under **Calendar → Done → Today**). Hover any done row for the **↩ undo** to bring it back.
- **The gentle nudge** — 4 tasks is fine. **5** turns the text red; **6** turns the whole drawer red — Buddy's quiet way of saying *that's a lot*. Finishing things eases the red back down.
- **Pin it** — the pin icon keeps the drawer open so it doesn't tuck away.
- **History** — the calendar icon shows what you've finished and what's coming up.

## Keyboard control

Buddy is fully driveable from the keyboard:

| Key | Does |
|-----|------|
| `` ` `` (backtick) | Toggle the drawer open/closed |
| ↑ / ↓ / Tab | Move between today's tasks and the Add row (in the Future panel, Tab walks the parked rows) |
| Enter | On a task: cycle it (→ done throws confetti). On Add: add + edit. On a cursored Future row: send it to today |
| E | Edit · ⌫ / Delete | Remove · A or + | Add a task |
| Tab (while editing) | Save and edit the next task (Shift+Tab: previous) |
| Esc | Commit an edit, else close history, else close the drawer |

---

## For developers & contributors

Buddy is **MIT-licensed and open source**, and follows the Ghost model — one codebase, two ways to run it:

- **The released app** (the DMG above + the iPhone app) is the **hosted edition**: it ships with the address of Buddy's sync service inside, so sync is one button. That address + publishable key are *identifiers, not secrets* ([Supabase documents them as safe to ship in clients](https://supabase.com/docs/guides/api/api-keys)); everything privileged is enforced server-side, and task content is end-to-end encrypted so the service can't read it either way.
- **A clone of this repo** builds the **open edition**: fully local-only, no backend, no keys, no accounts — Settings shows self-host fields instead of the one-button connect. Bring your own Supabase (below) and you own the whole stack.

The hosted parts live *in this repo*, dormant — they activate only when a gitignored `dist/config.js` / injected `BuddyCloud.swift` is present at build time (see `RELEASE-UPDATER.md`). Nothing about the open edition is crippled; it's the same app pointed at nothing.

### Repository layout

| Path | What it is |
|------|-----------|
| `dist/index.html` | The entire Mac web app — vanilla JS + locally-bundled Tailwind & Geist. No build step. |
| `src-tauri/` | The **Tauri v2** (Rust) macOS shell — tray, windows, durable-state commands. |
| `ios/` | The **iOS companion** (SwiftUI, generated with XcodeGen, shipped with fastlane via TestFlight). Live-syncs with the Mac. |
| `api/` | A serverless function for bug-report intake (see [Bug reports](#bug-reports)). |
| `design/` | `escalation-tokens.json` — the cross-platform color contract (pinned by tests on both platforms). |
| Runbooks | `RELEASE-UPDATER.md` (sign/notarize/publish), `RELEASE-CHECKLIST.md` (pre-ship regression pass), `BUG-REPORTS.md`, `CLAUDE.md`. |

### Build & run the Mac app

```bash
cd dist && python3 -m http.server 4500    # the web app alone (fastest UI loop) → http://localhost:4500
pnpm tauri dev                            # the native Mac app
```

Before every release the browser smoke test must pass — `await window.__buddy.smokeTest()` → `{ ok: true }`. See **`CLAUDE.md`** (design + verify rules) and **`RELEASE-UPDATER.md`** (sign / notarize / publish).

### Build & run the iOS app

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is **generated** from `ios/project.yml` (not committed).

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

### Sync (live — opt-in, local-first, end-to-end encrypted)

Buddy stores your data **on your own machine** and works fully offline. Cross-device sync (Mac ⇄ iPhone) is **opt-in** and live:

- **E2E encryption:** the synced document is encrypted on-device (HKDF of the pairing key → AES-256-GCM) before it reaches the wire; the server stores ciphertext plus integer counts (`{active, done, …}`) it enforces as numbers-only. The pairing key never leaves your devices — only its hash travels, as the row id. Same rule as the diagnostics log: **counts, never content**.
- **Self-hosting (open edition):** create a free Supabase project, paste `supabase/hosted-setup.sql` into its SQL editor (schema + RLS + the abuse guards — tunables at the top), then enter your Project URL + anon key in Buddy's Settings. That's the entire stack. The schema denies all direct table access; the two `SECURITY DEFINER` RPCs can only touch the single row your key addresses.
- Devices pair by **scanning a QR code** carrying an auto-generated 256-bit sync key — no login, no email. One synced document with a deterministic symmetric merge (same test vectors on both platforms) and local backups. **Sync is a convenience copy, not a backup** — lose every device at once and the ciphertext is unrecoverable by design.
- Settings on each device shows the sync **bucket id** ("Synced 12:04 · ab12cd"), derived from backend + key — two devices showing the same code are provably paired *to the same backend*. If devices ever stop converging, run `pnpm sync:doctor` for a verdict. **Erase cloud data** in Settings deletes your server row immediately.

### Bug reports

In-app **Report a bug** posts a screenshot + diagnostics to a small serverless function (`api/bug-report.js`) that files a **private** GitHub issue. It's inactive until you deploy it — see **`BUG-REPORTS.md`** for the ~10-minute setup (private repo → token → Vercel). Until then it falls back to an email draft.

## Credits

- Menu-bar + app icon: the "sticker" glyph from [Lucide](https://lucide.dev) (ISC License).
- Completion confetti: party-parrots from [cultofthepartyparrot.com](https://cultofthepartyparrot.com).

## License

[MIT](LICENSE) © Matthew Matsuzaki
