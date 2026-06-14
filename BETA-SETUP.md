# Beta setup — getting Buddy onto other people's Macs

The app is now **wired up** to be signed, notarized, and packaged as a `.dmg`.
What's left needs your Apple account. Do the three things below, paste me the
three values at the end, and I'll do the rest (build + notarize + DMG).

> Why: macOS blocks apps from unknown developers. "Signing" + "notarizing" is how
> Apple marks Buddy as trusted so testers can open it without scary warnings.

## 1. Make a Developer ID certificate (one time)

1. Open **Xcode**.
2. Menu bar → **Xcode → Settings…** → **Accounts** tab.
3. Click your Apple ID on the left → button **Manage Certificates…**
4. Click the **+** (bottom-left) → choose **Developer ID Application**.
5. Done — it's now in your keychain. Close the window.

*(No Xcode? Tell me and I'll give you the website version.)*

## 2. Make an app-specific password (one time)

1. Go to **https://appleid.apple.com** and sign in.
2. Find **Sign-In and Security** → **App-Specific Passwords**.
3. Click **+**, name it **Buddy notarize**, click Create.
4. **Copy the password it shows** (looks like `abcd-efgh-ijkl-mnop`). You won't see it again.

## 3. Find your Team ID

1. Go to **https://developer.apple.com/account** → **Membership details**.
2. Copy the **Team ID** (a 10-character code like `AB12CD34EF`).

## 4. Send me three things

Paste me:
- Your **Apple ID email**
- The **app-specific password** from step 2
- Your **Team ID** from step 3

I'll put them in a local, git-ignored `.env` (never committed), then run the
signed + notarized build. The result is a **Buddy.dmg** that anyone can download
and open.

## After that (I'll handle these)

- `pnpm tauri build` → signs with your Developer ID + notarizes via Apple → outputs
  `src-tauri/target/release/bundle/dmg/Buddy_<version>_aarch64.dmg`.
- Verify with `spctl` + `stapler` (must say "Notarized Developer ID").
- Upload the DMG to a **private GitHub Release** and invite your testers.

## Still to harden before a *wider* (public) release
- Bundle Tailwind locally (it currently loads from a CDN — fine for a small beta,
  but should be bundled + the CSP tightened for public). Tracked separately.
- A friendly first-run screen explaining the Accessibility permission.
