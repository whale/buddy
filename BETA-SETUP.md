# Beta setup — getting Buddy onto other people's Macs

The app is **wired up correctly** to be signed, notarized, and packaged as a
universal `.dmg` (runs on both Intel and Apple-Silicon Macs). What's left needs
your Apple account. Do the two tasks below, send me three values, and I'll build it.

> Why: macOS blocks apps from unknown developers. "Signing" + "notarizing" is how
> Apple marks Buddy as trusted so testers can open it with no scary warning.

## Task 1 — Developer ID certificate (one time, in Xcode)

1. Open **Xcode**.
2. Menu bar → **Xcode → Settings…** → **Accounts** tab.
3. Click your Apple ID on the left → **Manage Certificates…** (bottom-right).
4. Click the **+** (bottom-left) → **Developer ID Application**.
5. A new row appears → **Done**. *(If it's greyed out, you already have one — fine.)*

## Task 2 — App Store Connect API key (one time)

1. Go to **https://appstoreconnect.apple.com/access/integrations/api**
   *(App Store Connect → Users and Access → **Integrations** tab.)*
2. Make sure **Team Keys** is selected. (First time: click to enable/Request Access, agree.)
3. Click **+** (Generate API Key) → name it **Buddy notarize** → Access **Developer** → **Generate**.
4. Click **Download API Key** → a file **`AuthKey_XXXXXX.p8`** goes to your Downloads. ⚠️ You can only download it **once** — don't delete it.
5. Note two codes on that page:
   - **Issuer ID** — long code above the keys table (like `69a6de7e-1a2b-…`)
   - **Key ID** — the 10-character code in the **Key ID** column (like `ABCD123456`)

## Send me three things
- The **`AuthKey_XXXXXX.p8`** file — just confirm it's in your **Downloads** (or tell me the path)
- The **Issuer ID**
- The **Key ID**

I'll move the key into a private, git-ignored spot (never uploaded), wire up the
credentials, and run the build.

## What I do after that
- `rustup target add aarch64-apple-darwin x86_64-apple-darwin`
- `pnpm tauri build --target universal-apple-darwin --bundles dmg`
  (signs with your Developer ID → notarizes via Apple → staples → outputs a **universal** DMG)
- Verify it: `xcrun stapler validate <dmg>` and `spctl -a -vvv -t install <dmg>`
  must say **"Notarized Developer ID"** before it goes out.
- Upload `Buddy_<version>_universal.dmg` to a **private GitHub Release** and invite testers.

**Tester experience:** download the DMG → open it → drag Buddy to Applications →
double-click. macOS shows a normal one-time "downloaded from the internet — open?"
(it'll even say Apple checked it and found nothing) — **not** the "unidentified
developer" block. On first use they grant Accessibility / Input Monitoring (for the
edge-reveal + reserve features) in System Settings.

## Notes
- Notarization is automatic during `tauri build` (uses your API key). No separate
  upload step.
- The signing certificate is auto-detected from your keychain. If the build can't
  find it, I'll have you run `security find-identity -p codesigning -v` and paste
  the `Developer ID Application: …` line.
- Before a *wider/public* release (not needed for a small closed beta): bundle
  Tailwind locally + a friendly first-run permission screen.
