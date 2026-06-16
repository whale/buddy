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
