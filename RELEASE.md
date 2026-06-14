# Releasing Buddy to the community

**TL;DR.** For Buddy, the **Mac App Store and TestFlight are dead ends** — both require the App Sandbox, and Buddy's core behavior (reading the global cursor position, a global keyboard shortcut, an always-on-top accessory window) is exactly what the sandbox forbids. The right path is **direct distribution**: sign with your **Developer ID Application** certificate, **notarize** with Apple's `notarytool`, **staple**, and ship a **DMG**. For beta, hand testers a versioned DMG via **GitHub Releases** (private repo for closed beta → public for wider release). For auto-update, use the **Tauri v2 updater plugin**. The "TestFlight doesn't work with this" advice was correct — explained below.

## Why the app's traits decide everything
| Behavior | How it's built | Consequence |
|---|---|---|
| Reads the **global** mouse cursor position | `mouse_position` crate → CoreGraphics CGEvent | Banned in App Sandbox; fine for Developer ID |
| **Global** keyboard shortcut | `tauri-plugin-global-shortcut` | Restricted/unreliable in sandbox; fine for Developer ID |
| **Accessory** app (no Dock), transparent always-on-top edge window | `ActivationPolicy::Accessory` | Fine everywhere alone, but combined with the above pushes off the App Store |

Note: *reading* the cursor position / *monitoring* events is less restricted than synthesizing them. Outside the sandbox, Buddy will likely need the user to grant **Accessibility / Input Monitoring** once at first run (a System Settings toggle) — this is a runtime permission, **not** a build-time entitlement.

## 1. Direct distribution (recommended)
Developer ID signing → notarization (`notarytool`) → stapling → DMG.

**One-time Apple setup**
1. Create a **Developer ID Application** certificate (not "Apple Distribution," which is store-only); install it.
2. `security find-identity -v -p codesigning` → confirm `Developer ID Application: Your Name (TEAMID)`.
3. Create an **App Store Connect API key** (`.p8` + Issuer ID + Key ID) for notarization (more repeatable than an app-specific password).

**`tauri.conf.json` → `bundle.macOS`**
```jsonc
{ "bundle": { "active": true, "targets": ["dmg","app"],
  "macOS": { "signingIdentity": "Developer ID Application: Your Name (TEAMID)",
             "providerShortName": "TEAMID",
             "entitlements": "entitlements.plist",
             "minimumSystemVersion": "13.0" } } }
```
Tauri enables the **Hardened Runtime** automatically when signing for Developer ID (notarization requires it).

**`src-tauri/entitlements.plist`** (NO sandbox key):
```xml
<dict>
  <key>com.apple.security.cs.allow-jit</key><true/>
  <key>com.apple.security.cs.allow-unsigned-executable-memory</key><true/>
  <key>com.apple.security.cs.disable-library-validation</key><true/>
</dict>
```
There is **no entitlement that "unlocks" global event monitoring** — Accessibility/Input Monitoring is granted by the user at runtime. Add an `Info.plist` usage string explaining why Buddy reads input, and prompt with `AXIsProcessTrusted` on first run.

**Env vars** (shell or CI secrets): `APPLE_SIGNING_IDENTITY` (or `APPLE_CERTIFICATE` + `APPLE_CERTIFICATE_PASSWORD` for CI) and either the API key (`APPLE_API_ISSUER`, `APPLE_API_KEY`, `APPLE_API_KEY_PATH`) or `APPLE_ID` + `APPLE_PASSWORD` + `APPLE_TEAM_ID`.

**Build:** `pnpm tauri build --bundles dmg` → compiles, signs with Hardened Runtime + entitlements, submits to notarization via `notarytool`, staples, outputs a DMG.

**Verify before shipping:**
```
spctl -a -vvv -t install Buddy.app     # expect "accepted, source=Notarized Developer ID"
xcrun stapler validate Buddy.dmg        # expect "worked!"
```
Test the DMG on a second Mac that's never seen the app.

## 2. Beta — and the TestFlight answer
**TestFlight is not available to Buddy.** TestFlight only distributes builds uploaded to App Store Connect, and a macOS App Store Connect build must be **Apple Distribution-signed + App-Sandboxed**. Buddy can't be sandboxed (§3), so it can't be a Mac App Store build, so no TestFlight. Apple frames the two macOS tracks as mutually exclusive: notarized Developer ID **or** App Store/TestFlight.

**Realistic beta options for a notarized app:** a **private GitHub repo + GitHub Releases** (free, versioned, invite-gated, and it's exactly where the Tauri updater reads from). Beta → wide release = flip the repo public. (Alternatives: public GitHub Releases, plain DMG link, Sparkle beta appcast.)

## 3. Mac App Store — not viable
The App Store requires the App Sandbox. Inside it: reading the global cursor via CGEvent is banned, the global shortcut is unreliable/blocked, and the Accessibility APIs are blocked outright. No standard entitlement re-enables these. Buddy's cursor-edge detection — the whole point — wouldn't function and review would likely reject it. Don't spend time here.

## 4. Auto-update — Tauri updater (recommended) vs Sparkle
Use the **Tauri v2 updater plugin**: native to the stack, reads a `latest.json` from GitHub Releases, signed with **Minisign** (`tauri signer generate`; public key in `tauri.conf.json`). Sparkle is the gold standard for native Mac apps (deltas, channels) but needs FFI glue — overkill here. **Two independent signatures:** Apple notarization proves Gatekeeper trust; Minisign proves the update download is untampered. You need both.

## 5. Recommended path — checklist
**Phase A — one signed, notarized build**
- [ ] Developer ID Application cert installed; confirm via `security find-identity`.
- [ ] App Store Connect API key for notarization.
- [ ] `bundle.macOS` config + `entitlements.plist` (Hardened Runtime entitlements, no sandbox).
- [ ] `Info.plist` usage string + first-run Accessibility/Input-Monitoring prompt handling.
- [ ] `pnpm tauri build --bundles dmg`; verify with `spctl` + `stapler`.
- [ ] Test on a clean second Mac (opens without Gatekeeper warning; cursor-edge + hotkey work after granting permission).

**Phase B — closed beta**
- [ ] Private GitHub repo for releases; add testers as collaborators.
- [ ] Tag `v0.x.0-beta.1`; upload signed DMG as a Release asset with notes (include the "you'll be asked to allow Accessibility — here's why" line).
- [ ] Wire the Tauri updater (Minisign keypair, public key + GitHub `latest.json` endpoint, publish `latest.json` each release).

**Phase C — wider release**
- [ ] Make the release repo public (or a landing page pointing at the latest Release); keep the updater endpoint stable.
- [ ] (Optional) Homebrew Cask for `brew install --cask buddy`.

## Sources
- Tauri v2 — [macOS code signing](https://v2.tauri.app/distribute/sign/macos/), [updater plugin](https://v2.tauri.app/plugin/updater/)
- Apple — [distribution overview](https://help.apple.com/xcode/mac/current/en.lproj/devac02c5ab8.html), [TestFlight overview](https://www.developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview), App Sandbox / event-tap forum threads
- [Sparkle](https://sparkle-project.org/documentation/)

---

# Appendix: "Reserved space" when pinned (no windows underneath)

**Definitive answer: there is no public API to reserve screen-edge space** the way the Dock/menu bar do — that's system-only (`NSScreen.visibleFrame` is read-only, computed by the WindowServer). Higher window levels / collection behaviors only control stacking, never geometry (confirmed — that's today's "covers but doesn't reserve" behavior).

- **True reserved space** (windows literally cannot enter the strip, maximize snaps to Buddy's edge forever) requires injecting into Dock.app via a WindowServer scripting addition — which needs **SIP disabled** (this is what yabai does). Non-viable for a distributable app; App-Store-ineligible; can crash the display server.
- **The only realistic route** is an **Accessibility-API "window-nudging" mini window-manager**: with the user's Accessibility permission, watch other apps' windows and move/resize any that intrude into Buddy's strip (how Rectangle/Magnet/Loop manipulate windows). It would *feel* like reserved space for normal resizable windows on the main desktop, but with real caveats: needs a one-time Accessibility grant; can't touch **native-fullscreen** windows, **non-resizable** windows, or fight **Stage Manager** cleanly; it's **reactive** (a brief shove-back flicker); and it's per-monitor. It's a genuinely separate feature to build and maintain — not a flag on the existing window.

**Recommendation:** if "pinned reserves space" is worth it, build the Accessibility-API approach as its own opt-in feature (own PR), accepting it's a ~90%-case approximation. Otherwise, leave pinned as always-on-top.
