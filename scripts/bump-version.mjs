// Bumps the patch version in package.json, src-tauri/tauri.conf.json and
// src-tauri/Cargo.toml so they stay in sync. The app shows this in Settings
// (read from CARGO_PKG_VERSION). Run by .github/workflows/version-bump.yml.
import { readFileSync, writeFileSync } from 'node:fs';

const bumpPatch = (v) => {
  const p = String(v).split('.');
  p[2] = String((Number(p[2]) || 0) + 1);
  return p.join('.');
};

const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const next = bumpPatch(pkg.version);

pkg.version = next;
writeFileSync('package.json', JSON.stringify(pkg, null, 2) + '\n');

const tauri = JSON.parse(readFileSync('src-tauri/tauri.conf.json', 'utf8'));
tauri.version = next;
writeFileSync('src-tauri/tauri.conf.json', JSON.stringify(tauri, null, 2) + '\n');

const cargoPath = 'src-tauri/Cargo.toml';
const cargo = readFileSync(cargoPath, 'utf8').replace(/^version = ".*"$/m, `version = "${next}"`);
writeFileSync(cargoPath, cargo);

console.log('Bumped version to ' + next);
