// Two-device LIVE test of MUTUAL UNLINK (whale 2026-07-19): unlinking one device must
// break the link for BOTH. Two isolated browser "devices" pair on the real Supabase
// backend with a throwaway syncKey; device A unlinks; device B's next pass must detect
// the marker, self-unlink, keep its own tasks, and flag "peer unlinked".
//
// Run:  NODE_PATH=$(npm root -g) npx playwright test scripts/buddy-unlink-live.spec.js
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const http = require('http');

const PORT = 8919;
const DIST = path.join(__dirname, '..', 'dist');

function readSecret() {
  const p = path.join(__dirname, '..', '.supabase-buddy.secret');
  if (!fs.existsSync(p)) return null;
  const txt = fs.readFileSync(p, 'utf8');
  const get = k => (txt.match(new RegExp('^' + k + '=(.+)$', 'm')) || [])[1];
  return { url: get('URL'), anon: get('ANON_PUBLISHABLE_KEY') };
}

let server;
test.beforeAll(async () => {
  server = http.createServer((req, res) => {
    const f = path.join(DIST, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
    try { res.end(fs.readFileSync(f)); } catch { res.statusCode = 404; res.end(); }
  }).listen(PORT);
});
test.afterAll(async () => server && server.close());

async function bootDevice(browser, cfg, syncKey, seedText) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto(`http://localhost:${PORT}/index.html`);
  await page.evaluate(([url, anon, key, text]) => {
    const B = window.__buddy;
    B.clear();
    document.getElementById('morning').classList.add('hidden');
    B.state.today.morningDone = true;
    B.state.today.items = [{ id: text, text, state: 'neutral', v: 1 }];
    return B.setSync({ enabled: true, url, key: anon, syncKey: key });
  }, [cfg.url, cfg.anon, syncKey, seedText]);
  return page;
}
const sync = page => page.evaluate(() => window.__buddy.syncNow('unlink-test'));

test('mutual unlink: A unlinks → B self-unlinks, keeps its tasks, flags peer-unlinked', async ({ browser }) => {
  const cfg = readSecret();
  test.skip(!cfg || !cfg.url || !cfg.anon, 'no .supabase-buddy.secret — live backend creds required');
  const syncKey = 'k' + Math.random().toString(36).slice(2).padEnd(42, '0').slice(0, 42);

  const A = await bootDevice(browser, cfg, syncKey, 'mac-task');
  const B = await bootDevice(browser, cfg, syncKey, 'phone-task');

  // Converge: both paired, both see both tasks.
  await sync(A); await sync(B); await sync(A);
  expect(await A.evaluate(() => window.__buddy.syncConfigured())).toBe(true);
  expect(await B.evaluate(() => window.__buddy.syncConfigured())).toBe(true);

  // Device A unlinks (mutual). Stamps the bucket, then clears its own link.
  await A.evaluate(() => window.__buddy.syncUnlink());
  expect(await A.evaluate(() => window.__buddy.syncConfigured())).toBe(false);

  // Device B's next pass must SEE the marker and self-unlink.
  await sync(B);
  expect(await B.evaluate(() => window.__buddy.syncConfigured())).toBe(false);
  expect(await B.evaluate(() => window.__buddy.syncPeerUnlinked)).toBe(true);

  // B must NOT lose its own tasks — unlink stops syncing, it doesn't wipe local data.
  const bItems = await B.evaluate(() => window.__buddy.state.items.map(i => i.text));
  expect(bItems.length).toBeGreaterThan(0);

  await A.context().close();
  await B.context().close();
});
