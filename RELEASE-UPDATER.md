# Buddy — Auto-Update Runbook

Buddy has an in-app updater (Settings → **Check for Updates**). It checks a
manifest on **GitHub Releases**, and if a newer signed build exists it downloads,
installs, and relaunches.

## How it's wired

- **Update signing key** (separate from Apple signing): `~/.tauri/buddy-updater.key`
  (private — keep it; losing it breaks updates) and `.key.pub` (public — already
  baked into `tauri.conf.json` → `plugins.updater.pubkey`).
- **Endpoint**: `https://github.com/whale/buddy/releases/latest/download/latest.json`
  → the repo (or at least its Releases) must be **public** for the app to read it.
- **Rust**: `check_for_update` / `install_update` commands in `src-tauri/src/lib.rs`,
  plugin registered in `run()`.
- **UI/JS**: the `#updateBtn` flow in `dist/index.html`.


## Automatic releases from `main`

Buddy now has a GitHub Actions workflow: `.github/workflows/release-mac.yml`.

Flow:
1. A change is merged/pushed to `main`.
2. `.github/workflows/version-bump.yml` bumps the patch version.
3. When that workflow finishes, `release-mac.yml` checks out the bumped `main`.
4. If `AUTO_RELEASE_MAC=true`, it builds a signed/notarized universal Mac app, creates `latest.json`, and publishes a GitHub Release.
5. Installed Buddy apps see the new release because the updater reads `releases/latest/download/latest.json`.

Automatic publishing is intentionally gated by the repo variable `AUTO_RELEASE_MAC`.
Leave it unset or `false` until the signing secrets below are installed, otherwise the release job will fail on every update.

Required GitHub **secrets** for automatic release:

- `APPLE_CERTIFICATE` — base64-encoded Developer ID Application `.p12` certificate.
- `APPLE_CERTIFICATE_PASSWORD` — password used when exporting that `.p12`.
- `KEYCHAIN_PASSWORD` — temporary CI keychain password; generate a long random value.
- `APPLE_API_ISSUER` — App Store Connect Issuer ID.
- `APPLE_API_KEY` — App Store Connect API Key ID.
- `APPLE_API_KEY_P8` — full contents of the downloaded `AuthKey_XXXXXX.p8` file.
- `APPLE_TEAM_ID` — Apple Developer Team ID. Optional for some accounts, but set it to avoid ambiguity.
- `TAURI_SIGNING_PRIVATE_KEY` — contents of `~/.tauri/buddy-updater.key`.
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` — updater key password; currently blank if the key was generated without one.

Required GitHub **variable** once secrets are ready:

- `AUTO_RELEASE_MAC=true`

Useful setup commands:

```bash
# Example only: choose your actual exported .p12 path.
gh secret set APPLE_CERTIFICATE < <(base64 -i path/to/DeveloperIDApplication.p12)
gh secret set APPLE_CERTIFICATE_PASSWORD
gh secret set KEYCHAIN_PASSWORD
gh secret set APPLE_API_ISSUER --body "$APPLE_API_ISSUER"
gh secret set APPLE_API_KEY --body "$APPLE_API_KEY"
gh secret set APPLE_API_KEY_P8 < "$APPLE_API_KEY_PATH"
gh secret set APPLE_TEAM_ID --body "<TEAM_ID>"
gh secret set TAURI_SIGNING_PRIVATE_KEY < ~/.tauri/buddy-updater.key
gh secret set TAURI_SIGNING_PRIVATE_KEY_PASSWORD --body ""
gh variable set AUTO_RELEASE_MAC --body true
```

You can also run the workflow manually from GitHub Actions → **Release Mac app**.

## One-time, before updates can flow

1. **Scrub old Apple IDs from git history**, then make the repo public (see
   "Going public" below). Until the repo/releases are public, the updater can't
   read `latest.json`.

## Pre-release smoke test (run before EVERY build)

Regressions hide in shared code (rendering, attributes, state) and don't show up
when you only test the new feature. Before building, serve `dist/` and run the
core-interaction smoke test in the browser console:

```js
await window.__buddy.smokeTest()   // → { ok: true, ... } means core flows pass
```

It asserts: add focuses the new task, edit focuses the task text, completing marks
done + drops the red count, undo restores, and rows don't reuse `data-tid`. If
`ok` is false, fix before building. (This exists because a render change once gave
the row and its text the same `data-tid`, which broke add/edit focus.)

## Building a release (each new version)

Bump the version in `package.json`, `src-tauri/Cargo.toml`, and
`src-tauri/tauri.conf.json` (keep them equal), then:

```bash
cd ~/Projects/buddy
source "$HOME/.cargo/env"
set -a && source .env && set +a                                  # Apple notarization creds
export TAURI_SIGNING_PRIVATE_KEY="$(cat ~/.tauri/buddy-updater.key)"
export TAURI_SIGNING_PRIVATE_KEY_PASSWORD=""
pnpm tauri build --target universal-apple-darwin
```

This produces, under `src-tauri/target/universal-apple-darwin/release/bundle/`:
- `dmg/Buddy_<ver>_universal.dmg` — the installer (manual download).
- `macos/Buddy.app.tar.gz` + `Buddy.app.tar.gz.sig` — the updater package + signature.

## Publishing so the app can update

Create `latest.json` (the manifest the app reads). `signature` is the **contents**
of the `.sig` file; both macOS arches point to the same universal tarball:

```json
{
  "version": "0.2.11",
  "notes": "What changed in this release.",
  "pub_date": "2026-06-16T00:00:00Z",
  "platforms": {
    "darwin-aarch64": { "signature": "<paste .sig contents>", "url": "https://github.com/whale/buddy/releases/download/v0.2.11/Buddy.app.tar.gz" },
    "darwin-x86_64":  { "signature": "<paste .sig contents>", "url": "https://github.com/whale/buddy/releases/download/v0.2.11/Buddy.app.tar.gz" }
  }
}
```

Then publish the release with the three assets attached:

```bash
gh release create v0.2.11 \
  src-tauri/target/universal-apple-darwin/release/bundle/dmg/Buddy_0.2.11_universal.dmg \
  src-tauri/target/universal-apple-darwin/release/bundle/macos/Buddy.app.tar.gz \
  latest.json \
  --title "Buddy 0.2.11" --notes "What changed."
```

Once published (on a public repo), any installed Buddy will find it via **Check for Updates**.

## Going public (one-time)

The repo currently has the old Apple **Key ID / Team ID** in git *history*
(commit `a056790`). Scrub before making public:

```bash
# requires git-filter-repo (brew install git-filter-repo)
git filter-repo --replace-text <(printf '8LPB7CQ8S8==>REDACTED\n9QDAAYWU9X==>REDACTED\n')
git remote add origin https://github.com/whale/buddy.git   # filter-repo drops the remote
git push --force --all && git push --force --tags
gh repo edit whale/buddy --visibility public
```
