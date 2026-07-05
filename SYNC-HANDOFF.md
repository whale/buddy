# Mac ⇄ iPhone sync — morning handoff

## TL;DR
The whole sync feature is **built, tested, and the cloud backend is already live**. I created
a free Supabase project on your account, loaded it, and proved a real two-device round-trip
through it. Pairing works by showing a **QR code on the Mac** that the **iPhone scans**.

Nothing to create or configure — just paste two values on the Mac and pair. Start here 👇

---

## Your backend is ready — here are the two values

I already created and verified the cloud database. Paste these into Buddy's Mac Settings:

- **Backend URL:** `https://awzkpkhsigbhfeklogzk.supabase.co`
- **Anon key:** `sb_publishable_knDbBC63MXCYvMoskTLPIA_cqmCFVnN`

*(The anon key is a public key — safe to keep here. Dashboard if you ever want it:
https://supabase.com/dashboard/project/awzkpkhsigbhfeklogzk — org "MrDrFeesh's Org".
Both values are also in `.supabase-buddy.secret`, which is gitignored.)*

---

## Then: pair the two apps

### On the Mac
1. Open Buddy → click the **gear (Settings)**.
2. In **Sync with iPhone**, paste the **Backend URL** and **Anon key** above into the two boxes.
3. Click **Connect & show QR**. A QR code appears and the status says **Synced HH:MM**.

### On the iPhone
1. The Buddy app needs to be **installed on your phone** once. Easiest: plug your iPhone into the Mac, open `ios/Buddy.xcodeproj` in Xcode, pick your iPhone at the top, and press ▶ (Run). The first time, your phone will ask you to **trust** the app: Settings → General → VPN & Device Management → tap your Apple ID → Trust. *(If you'd rather I walk you through this live when you're around, just say so — it's a 3-tap thing once the phone's plugged in.)*
2. Open Buddy on the phone → **Settings → Scan QR to pair** → point it at the QR on your Mac.
3. Done. Add a task on the Mac; it appears on the phone within a few seconds, and vice-versa.

*(No camera / testing on the simulator? The iPhone Settings also has "Enter manually" — paste the same URL, anon key, and the sync key, and it pairs without the camera.)*

---

## What's proven vs. what's left

**Proven overnight (real database, automated):**
- The full sync protocol both directions, on both platforms (Mac web app ↔ iPhone Swift app).
- The Mac app writing a real change → the iPhone code reading and decoding it correctly.
- Deletes, "erase all", two-device same-day edits, and first-pairing all merge with nothing lost.
- The Mac renders a QR that decodes back to the exact pairing details.

**Left for you (needs your hardware/accounts — that's the only reason I didn't):**
- Creating the free cloud database (the 10-minute step above).
- Installing the app on your physical iPhone once (the Xcode step).
- The actual camera scan (a simulator has no camera; the scan code is built and ready).

**One honest note:** "sync to your phone over the internet" uses the free cloud database above.
Syncing *without* any cloud (Mac + phone on the same home Wi-Fi only) is possible but needs a
small extra security setting on the phone — say the word and I'll add it. Cloud is simpler and
works anywhere, so that's the recommended path.

---

## For me / next session
Branch `feat/ios-sync-live`. Plan + full status: `ios/_review/SYNC-EXEC-PLAN.md`.
Everything through P6 is done + verified; P7 = the two human steps above.
