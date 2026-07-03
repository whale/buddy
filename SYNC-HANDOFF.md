# Mac ⇄ iPhone sync — morning handoff

## TL;DR
The whole sync feature is **built and tested end-to-end**. Add/complete/edit/delete on
one device shows up on the other, and pairing works by showing a **QR code on the Mac**
that the **iPhone camera scans**. I proved every piece against a real database overnight
(49 automated tests, 0 failures, plus a real Mac-app → database → iPhone-code round-trip).

To actually use it on **your real iPhone**, two things need you (they need your hardware
and your accounts — I can't do them while you sleep). Both are quick. Start here 👇

---

## Do this first (≈10 minutes): make a free cloud database

Your Mac and iPhone need a shared place to sync through. Free Supabase project = that place.

1. Go to **https://supabase.com** and click **Start your project** (sign in with GitHub or email).
2. Click **New project**. Give it any name, set a database password (save it somewhere), pick the closest region, click **Create**. Wait ~2 minutes while it spins up.
3. In the left sidebar click **SQL Editor**, then **New query**.
4. Open the file **`supabase/hosted-setup.sql`** in this project, copy **everything** in it, paste it into that box, and click **Run**. (This creates the sync table. You'll see "Success".)
5. In the left sidebar click **Project Settings → API**. Copy two things:
   - **Project URL** (looks like `https://abcdxyz.supabase.co`)
   - **anon public** key (a long string — it's a *public* key, safe to share)

Keep those two values handy for the next part.

---

## Then: pair the two apps

### On the Mac
1. Open Buddy → click the **gear (Settings)**.
2. In **Sync with iPhone**, paste your **Project URL** and **anon key** into the two boxes.
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
