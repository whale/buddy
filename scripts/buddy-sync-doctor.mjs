#!/usr/bin/env node
// buddy-sync-doctor — answers "why aren't my devices in sync?" in one command.
//
//   pnpm sync:doctor
//
// Reads every Buddy storage container on this Mac (installed app + dev build),
// extracts each one's sync pairing, derives the server bucket id (sha256 of the
// syncKey — same as the apps do), pulls each bucket's version/content from the
// backend, and prints a verdict. The 2026-07-10 divergence (dev paired to a
// stale key → pushing to a bucket nobody reads) is exactly what this catches.
//
// The iPhone's pairing can't be read from here — but if the Mac containers all
// point at ONE bucket and that bucket's version climbs when you edit on the
// phone, the phone is on it too.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const home = os.homedir();
const patterns = [
  ["INSTALLED", `${home}/Library/WebKit/fyi.whale.buddy/WebsiteData/Default`],
  ["DEV", `${home}/Library/WebKit/buddy/WebsiteData/Default`],
];

function* sqliteStores() {
  for (const [tag, root] of patterns) {
    if (!fs.existsSync(root)) continue;
    for (const hash of fs.readdirSync(root)) {
      const p = path.join(root, hash, hash, "LocalStorage", "localstorage.sqlite3");
      if (fs.existsSync(p)) yield [tag, p];
    }
  }
}

function readLocalStorage(dbPath) {
  // Copy first: WebKit holds the db open; a straight read can hit a lock.
  const tmp = path.join(os.tmpdir(), `buddy-doctor-${Date.now()}.sqlite3`);
  fs.copyFileSync(dbPath, tmp);
  for (const ext of ["-wal", "-shm"]) {
    if (fs.existsSync(dbPath + ext)) fs.copyFileSync(dbPath + ext, tmp + ext);
  }
  try {
    // WebKit schema: key is TEXT (utf-8), value is BLOB (utf-16le).
    const out = execFileSync("sqlite3", [tmp, ".mode json", "SELECT key k, hex(value) v FROM ItemTable;"], { encoding: "utf8" });
    const rows = out.trim() ? JSON.parse(out) : [];
    const map = {};
    for (const r of rows) map[r.k] = Buffer.from(r.v, "hex").toString("utf16le");
    return map;
  } finally {
    for (const ext of ["", "-wal", "-shm"]) { try { fs.unlinkSync(tmp + ext); } catch {} }
  }
}

async function pullBucket(url, anon, ownerId) {
  const res = await fetch(`${url.replace(/\/$/, "")}/rest/v1/rpc/buddy_pull`, {
    method: "POST",
    headers: { apikey: anon, Authorization: `Bearer ${anon}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_key: ownerId }),
  });
  if (!res.ok) throw new Error(`buddy_pull ${res.status}`);
  const rows = await res.json();
  const row = Array.isArray(rows) && rows.length ? rows[0] : null;
  if (!row) return { version: 0, items: null, deferred: null, savedAt: null };
  const blob = row.blob || {};
  return {
    version: row.version,
    items: blob.today?.items?.length ?? 0,
    activeItems: (blob.today?.items || []).filter((i) => i.state !== "done").length,
    deferred: blob.deferred?.length ?? 0,
    savedAt: blob.savedAt ? new Date(blob.savedAt).toISOString() : null,
  };
}

const found = [];
for (const [tag, p] of sqliteStores()) {
  let store;
  try { store = readLocalStorage(p); } catch (e) { console.log(`${tag}  ${p}\n  !! unreadable: ${e.message}`); continue; }
  const raw = store["buddy.sync.v1"];
  if (!raw) { console.log(`${tag} (${p.split("Default/")[1].slice(0, 10)}…)  — no sync config (unpaired container)`); continue; }
  let cfg;
  try { cfg = JSON.parse(raw); } catch { console.log(`${tag}  !! corrupt buddy.sync.v1`); continue; }
  const owner = cfg.syncKey ? createHash("sha256").update(cfg.syncKey).digest("hex") : null;
  found.push({ tag, cfg, owner, container: p.split("Default/")[1].slice(0, 10) });
}

if (!found.length) { console.log("No paired Buddy containers found."); process.exit(1); }

const buckets = new Map();
for (const f of found) {
  console.log(`${f.tag} (${f.container}…)  enabled=${f.cfg.enabled}  bucket=${f.owner?.slice(0, 8)}`);
  if (f.owner) buckets.set(f.owner, f.cfg);
}

console.log("");
for (const [owner, cfg] of buckets) {
  try {
    const b = await pullBucket(cfg.url, cfg.key, owner);
    console.log(`bucket ${owner.slice(0, 8)}  v${b.version}  today=${b.items} (${b.activeItems} active)  future=${b.deferred}  savedAt=${b.savedAt}`);
  } catch (e) {
    console.log(`bucket ${owner.slice(0, 8)}  !! pull failed: ${e.message}`);
  }
}

console.log("");
if (buckets.size > 1) {
  console.log("❌ SPLIT BRAIN: Mac containers point at DIFFERENT buckets — devices on");
  console.log("   different buckets sync 'successfully' but never see each other.");
  console.log("   Fix: re-pair the odd one out (Settings → Sync), or copy the good");
  console.log("   buddy.sync.v1 between containers.");
  process.exit(2);
} else {
  console.log(`✓ all Mac containers share bucket ${[...buckets.keys()][0].slice(0, 8)}.`);
  console.log("  If the phone still diverges: edit a task there, re-run this, and check");
  console.log("  the bucket version climbed. If it didn't, the phone is on another key —");
  console.log("  re-pair it from the Mac's Settings QR.");
}
