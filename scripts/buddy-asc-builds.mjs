#!/usr/bin/env node
// Buddy — list recent TestFlight builds from App Store Connect.
//
// This is the SOURCE OF TRUTH for "did the iOS build actually upload?". fastlane's
// exit code is NOT reliable proof — a pipe (`| tail`) or trailing command (`; echo`)
// silently replaces it, and "uploaded" ≠ "visible on TestFlight" (Apple processes for
// a few minutes). So ANY claim that an iOS build shipped must be confirmed here.
//
// Used by scripts/ios-testflight.sh; also runnable directly:
//   node scripts/buddy-asc-builds.mjs [bundleId]
// Needs ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH in the env (same as `fastlane beta`).
//
// Output: one line per build — `build <n>  v<version>  <processingState>  <uploadedDate>`,
// newest first. Exit 2 on missing creds / app not found (so callers can tell "couldn't
// check" apart from "nothing there").

import fs from 'node:fs';
import crypto from 'node:crypto';

const kid = process.env.ASC_KEY_ID, iss = process.env.ASC_ISSUER_ID, keyPath = process.env.ASC_KEY_PATH;
if (!kid || !iss || !keyPath) {
  console.error('buddy-asc-builds: missing ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH in env');
  process.exit(2);
}
const p8 = fs.readFileSync(keyPath, 'utf8');
const b64u = b => Buffer.from(b).toString('base64url');
const now = Math.floor(Date.now() / 1000);
const header = b64u(JSON.stringify({ alg: 'ES256', kid, typ: 'JWT' }));
const payload = b64u(JSON.stringify({ iss, iat: now, exp: now + 300, aud: 'appstoreconnect-v1' }));
const sig = crypto.sign('sha256', Buffer.from(header + '.' + payload), { key: p8, dsaEncoding: 'ieee-p1363' });
const jwt = header + '.' + payload + '.' + b64u(sig);
const api = async path => (await fetch('https://api.appstoreconnect.apple.com' + path,
  { headers: { Authorization: 'Bearer ' + jwt } })).json();

const bundle = process.argv[2] || 'fyi.whale.buddy';
const apps = await api(`/v1/apps?filter[bundleId]=${bundle}`);
const appId = apps.data?.[0]?.id;
if (!appId) { console.error('buddy-asc-builds: app not found for bundleId ' + bundle); process.exit(2); }

const builds = await api(`/v1/builds?filter[app]=${appId}&limit=8&sort=-uploadedDate&include=preReleaseVersion`);
for (const b of (builds.data || [])) {
  const pv = (builds.included || []).find(i => i.id === b.relationships?.preReleaseVersion?.data?.id);
  console.log(`build ${b.attributes.version}  v${pv?.attributes?.version || '?'}  ${b.attributes.processingState}  ${b.attributes.uploadedDate}`);
}
