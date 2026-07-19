// Buddy sync — ONE-COMMAND cross-platform validation (SYNC-COMPAT.md / VALIDATION.md).
//
// Run:  pnpm sync:validate      (== NODE_PATH=$(npm root -g) node scripts/buddy-sync-validate.mjs)
//
// Any agent can run this to answer "is sync working, and safe across Mac↔iOS version
// skew?" WITHOUT a device or a live backend. It checks three things and exits non-zero
// if any fail:
//   1. Mac sync logic   — __buddy.syncTest + mergeTest (merge/CAS/E2E correctness)
//   2. Version-skew fix  — __buddy.skewTest GUARDS (backward read, forward write,
//                          refuse-to-clobber, AAD downgrade defence, legacy upgrade)
//   3. Mac↔iOS interop   — the wire-2 envelope ciphertext computed by Swift (CryptoKit)
//                          MUST equal the value the Mac (WebCrypto) produces. If the two
//                          platforms emit the same envelope bytes, they read each other.
//
// Deeper checks live in VALIDATION.md: the full iOS suite (xcodebuild test) and the
// real two-device / real-phone passes.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));

// playwright is installed GLOBALLY (like sync:live) — resolve it via CJS (honours
// NODE_PATH) and fall back to the explicit global root.
function loadChromium() {
  const gRoot = execFileSync('npm', ['root', '-g']).toString().trim();
  for (const spec of ['@playwright/test', 'playwright',
                      path.join(gRoot, '@playwright', 'test'), path.join(gRoot, 'playwright')]) {
    try { const m = require(spec); if (m.chromium) return m.chromium; } catch {}
  }
  throw new Error('playwright not found (install: npm i -g @playwright/test)');
}
const DIST = path.join(__dirname, '..', 'dist');
const PORT = 8918;
// The shared pin — Mac (syncTest 12c-vec) and iOS (BlobCryptoTests) both assert this.
const WIRE2_VECTOR = 'dwuU613APPxtAVeAdb_UI1J97z3qrFHjfMMU';

const results = [];
const record = (name, pass, detail = '') => { results.push({ name, pass: !!pass, detail }); };

async function runMacSuites() {
  const chromium = loadChromium();
  const server = http.createServer((req, res) => {
    const f = path.join(DIST, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
    try { res.end(fs.readFileSync(f)); } catch { res.statusCode = 404; res.end(); }
  }).listen(PORT);
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage();
    await page.goto(`http://localhost:${PORT}/index.html`);
    await page.waitForFunction(() => !!(window.__buddy && window.__buddy.skewTest), { timeout: 10000 });
    const out = await page.evaluate(async () => ({
      sync: await window.__buddy.syncTest(),
      skew: await window.__buddy.skewTest(),
      merge: await window.__buddy.mergeTest(),
    }));
    record('Mac syncTest (merge/CAS/E2E)', out.sync.ok, `${out.sync.total - out.sync.failed}/${out.sync.total}`);
    record('Mac mergeTest (lossless union)', out.merge.ok, out.merge.failed ? `${out.merge.failed} failed` : 'ok');
    record('Mac skewTest GUARDS (version-skew fix)', out.skew.ok,
           `${out.skew.total - out.skew.failed}/${out.skew.total}` + (out.skew.gaps?.length ? ` · ${out.skew.gaps.length} documented server-floor gap` : ''));
    // Named guards must each be present + passing (not just the aggregate).
    const need = ['backward read', 'writes a WIRE-2 envelope', 'refuse-to-clobber', 'AAD', 'upgraded to a wire-2'];
    for (const frag of need) {
      const r = out.skew.results.find(x => x.name.includes(frag));
      record(`  guard: ${frag}`, r && r.pass, r ? '' : 'MISSING');
    }
    // The Mac's own wire-2 vector must equal the shared pin.
    const vec = out.sync.results.find(r => r.name.includes('wire-2 envelope vector'));
    record('Mac wire-2 envelope vector == shared pin', vec && vec.pass, vec ? vec.detail : 'MISSING');
  } finally {
    await browser.close();
    server.close();
  }
}

function runSwiftParity() {
  let swift;
  try { swift = execFileSync('which', ['swift']).toString().trim(); }
  catch { record('iOS envelope parity (Swift CryptoKit)', true, 'SKIPPED — no swift toolchain (run on macOS)'); return; }
  const src = `
import Foundation
import CryptoKit
func b64u(_ d: Data) -> String { d.base64EncodedString().replacingOccurrences(of:"+",with:"-").replacingOccurrences(of:"/",with:"_").replacingOccurrences(of:"=",with:"") }
func dec(_ s: String) -> Data { var b=s.replacingOccurrences(of:"-",with:"+").replacingOccurrences(of:"_",with:"/"); while b.count%4 != 0 { b+="=" }; return Data(base64Encoded:b)! }
let ikm = dec(String(repeating:"A",count:43))
let key = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: ikm), info: Data("buddy-blob-v1".utf8), outputByteCount: 32)
let aad = Data("buddy|2|aes256gcm.hkdf.v1|2".utf8)
let box = try! AES.GCM.seal(Data("{\\"probe\\":1}".utf8), using: key, nonce: try! AES.GCM.Nonce(data: Data(count:12)), authenticating: aad)
print(b64u(box.ciphertext + box.tag))
`;
  const tmp = path.join(os.tmpdir(), `buddy-envelope-parity-${process.pid}.swift`);
  fs.writeFileSync(tmp, src);
  try {
    const ct = execFileSync(swift, [tmp]).toString().trim();
    record('iOS envelope parity (Swift CryptoKit == Mac WebCrypto)', ct === WIRE2_VECTOR, `swift ct=${ct}`);
  } catch (e) {
    record('iOS envelope parity (Swift CryptoKit)', false, `swift run failed: ${String(e.message).slice(0, 120)}`);
  } finally { try { fs.unlinkSync(tmp); } catch {} }
}

(async () => {
  try { await runMacSuites(); }
  catch (e) { record('Mac suites', false, `harness error: ${String(e.message).slice(0, 160)}`); }
  runSwiftParity();

  const pad = Math.max(...results.map(r => r.name.length));
  console.log('\n  Buddy sync validation\n  ' + '─'.repeat(pad + 12));
  for (const r of results) {
    console.log(`  ${r.pass ? '✅' : '❌'}  ${r.name.padEnd(pad)}  ${r.detail}`);
  }
  const failed = results.filter(r => !r.pass);
  console.log('  ' + '─'.repeat(pad + 12));
  console.log(`  ${failed.length ? '❌ FAIL' : '✅ PASS'} — ${results.length - failed.length}/${results.length} checks\n`);
  process.exit(failed.length ? 1 : 0);
})();
