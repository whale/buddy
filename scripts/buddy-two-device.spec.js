// Two-device LIVE sync harness — lets Claude (or anyone) reproduce cross-device
// field reports WITHOUT a human holding an iPhone: two independent browser pages
// ("mac" and "phone") pair against the real Supabase backend with a THROWAWAY
// syncKey, then drive real UI-level flows and assert convergence on both sides.
//
// Run:  NODE_PATH=$(npm root -g) npx playwright test scripts/buddy-two-device.spec.js
// Creds come from .supabase-buddy.secret (gitignored). Every run uses a fresh
// random syncKey, so it never touches real user buckets and needs no cleanup.
//
// This pins the exact 2026-07-08 field reports:
//   - "sent a Future task back to today and it never appeared on the other device"
//   - "Sent to today! reverted"
//   - duplicate Future rows accumulating ('Warren Logo' ×3)
const { test, expect } = require('@playwright/test');
const fs = require('fs');
const path = require('path');
const http = require('http');

const PORT = 8917;
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

// Boot one "device": fresh page + storage, sync configured with the shared key.
// `seedToday` (optional) is applied BEFORE sync is configured. That ordering is load-bearing
// for any back-dated scenario: setSync pushes immediately, and merge()'s different-date rule
// makes the CALENDAR-LATER day live — so a device that boots on today's date and pushes first
// will beat a back-dated seed applied afterwards, archiving it into history and leaving both
// devices staring at an empty list.
async function bootDevice(browser, cfg, syncKey, seedToday) {
  const ctx = await browser.newContext();           // isolated storage = its own device
  const page = await ctx.newPage();
  await page.goto(`http://localhost:${PORT}/index.html`);
  await page.evaluate(([url, anon, key, seed]) => {
    const B = window.__buddy;
    B.clear();
    document.getElementById('morning').classList.add('hidden');
    B.state.today.morningDone = true;
    if (seed) { B.state.today = seed; B.state.savedAt = Date.now(); B.flush(); }
    return B.setSync({ enabled: true, url, key: anon, syncKey: key });
  }, [cfg.url, cfg.anon, syncKey, seedToday || null]);
  return page;
}

const settle = async (page, ms = 4500) => page.waitForTimeout(ms); // > debounce(3s) + poll(1.5s)
// A scheduled poll may already own the sync pass. Wait for an actual result,
// rather than mistaking the intentional coalesced null for a failed merge.
const sync = async page => {
  let result;
  await expect.poll(async()=>{ result=await page.evaluate(()=>window.__buddy.syncNow('harness')); return result!==null; },{timeout:15000}).toBe(true);
  return result;
};
const texts = (page, sel) => page.evaluate(() =>
  window.__buddy.state.items.map(i => ({ text: i.text, state: i.state })));
const deferred = page => page.evaluate(() =>
  window.__buddy.state.deferred.map(d => ({ text: d.text, sent: !!d.sent })));

test('two live devices: future→today, undo, dedupe — full convergence', async ({ browser }) => {
  test.setTimeout(120000);
  const cfg = readSecret();
  test.skip(!cfg || !cfg.url, 'no .supabase-buddy.secret — live harness needs the backend');

  const syncKey = await (async () => {
    // 43-char base64url throwaway key, valid per isValidSyncKey
    const bytes = require('crypto').randomBytes(32);
    return bytes.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  })();

  const mac = await bootDevice(browser, cfg, syncKey);
  const phone = await bootDevice(browser, cfg, syncKey);

  // 1. Mac adds a long-named task → phone converges.
  await mac.evaluate(() => {
    const B = window.__buddy;
    B.state.items.push({ id: 'm-' + crypto.randomUUID(), text: 'Something longer here that really stretches the title', state: 'neutral', v: 1 });
    B.state.savedAt = Date.now(); B.flush(); return B.syncNow('harness');
  });
  await sync(phone); await settle(phone, 2500); await sync(phone);
  await expect.poll(async () => (await texts(phone)).map(t => t.text).join('|'), { timeout: 20000 })
    .toContain('Something longer');

  // 2. Phone parks it in Future ("Move to Future") → mac converges.
  await phone.evaluate(() => {
    const B = window.__buddy;
    const it = B.state.items.find(i => /Something longer/.test(i.text));
    // sleepItem equivalent through internal API: park + tombstone + remove
    B.state.deferred.push({ id: 'p-' + crypto.randomUUID(), text: it.text, wake: '2099-01-01', v: 1 });
    B.state.tombstones[it.id] = Date.now();
    B.state.items = B.state.items.filter(x => x.id !== it.id);
    B.state.savedAt = Date.now(); B.flush(); return B.syncNow('harness');
  });
  await sync(mac);
  await expect.poll(async () => (await deferred(mac)).map(d => d.text).join('|'), { timeout: 20000 })
    .toContain('Something longer');
  expect((await texts(mac)).some(t => /Something longer/.test(t.text))).toBe(false);

  // 3. Phone sends it BACK to today (the exact field repro) → MUST appear on mac
  //    and MUST NOT revert on either side.
  await phone.evaluate(() => {
    const B = window.__buddy;
    const d = B.state.deferred.find(x => /Something longer/.test(x.text));
    const tid = 'n-' + crypto.randomUUID();
    B.state.items.push({ id: tid, text: d.text, state: 'neutral', v: 1 });
    d.sent = true; d.sentTid = tid; d.v = (d.v | 0) + 1;
    B.state.savedAt = Date.now(); B.flush(); return B.syncNow('harness');
  });
  await sync(mac); await settle(mac, 2500); await sync(mac); await sync(phone);
  await expect.poll(async () => (await texts(mac)).map(t => t.text).join('|'), { timeout: 20000 })
    .toContain('Something longer');
  // the sent flag survives on both sides (no revert)
  await expect.poll(async () => JSON.stringify(await deferred(phone)), { timeout: 20000 })
    .toContain('"sent":true');
  await expect.poll(async () => JSON.stringify(await deferred(mac)), { timeout: 20000 })
    .toContain('"sent":true');

  // 4. Same-title dedupe: both devices park 'Warren Logo' independently → converges to ONE row.
  const park = (page, id) => page.evaluate(pid => {
    const B = window.__buddy;
    B.state.deferred.push({ id: pid, text: 'Warren Logo', wake: '2099-01-01', v: 1 });
    B.state.savedAt = Date.now(); B.flush(); return B.syncNow('harness');
  }, id);
  await park(mac, 'wm-' + Date.now()); await park(phone, 'wp-' + Date.now());
  await sync(mac); await sync(phone); await sync(mac); await sync(phone);
  await expect.poll(async () =>
    (await deferred(mac)).filter(d => d.text === 'Warren Logo' && !d.sent).length, { timeout: 20000 }).toBe(1);
  await expect.poll(async () =>
    (await deferred(phone)).filter(d => d.text === 'Warren Logo' && !d.sent).length, { timeout: 20000 }).toBe(1);

  // 5. Final convergence: both sides agree on the full content key.
  const key = p => p.evaluate(() => {
    const B = window.__buddy;
    return B.syncNow('harness').then(() => JSON.stringify({
      items: B.state.items.map(i => i.text).sort(),
      def: B.state.deferred.map(d => d.text + ':' + !!d.sent).sort(),
    }));
  });
  await settle(mac, 3000); await settle(phone, 1000);
  await expect.poll(async () => (await key(mac)) === (await key(phone)), { timeout: 25000 }).toBe(true);
});

// The 2026-08-08 field report: "I've already checked off Ghost pricing pages, but I still
// see the task showing up."
//
// A rollover DROPS completed rows, and pure absence never wins a union-merge — so the peer
// that never saw the completion re-added its own stale ACTIVE copy every single day.
//
// The ASYMMETRIC case is the one that actually bites and the one a "both devices roll over"
// test walks straight past: the phone completes the task at 23:50, the Mac is tucked and never
// pulls, the Mac rolls over at midnight carrying its still-active copy forward, and only THEN
// do they meet — in merge()'s different-date branch, which used to take the later day's list
// wholesale (no tombstones, no done-marks).
test('a task completed on one device stays gone after the other rolls over', async ({ browser }) => {
  test.setTimeout(120000);
  const cfg = readSecret();
  test.skip(!cfg || !cfg.url, 'no .supabase-buddy.secret — live backend creds required');
  // MUST be a real 43-char base64url key — isValidSyncKey rejects anything else, initSync then
  // leaves syncStore null, and every syncNow silently returns null. A test that never syncs
  // "passes" for the wrong reason, so the assertions below also check the pass actually ran.
  const syncKey = require('crypto').randomBytes(32).toString('base64')
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

  const yesterday = new Date(Date.now() - 86400000);
  const day1 = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, '0')}-${String(yesterday.getDate()).padStart(2, '0')}`;

  // Both devices start on YESTERDAY holding the same two tasks under the same ids —
  // seeded before their first push (see bootDevice).
  const seed = () => ({ date: day1, morningDone: true, items: [
    { id: 'gp-shared', text: 'Ghost pricing pages', state: 'neutral', v: 1, src: null, doneAt: null, doneWord: null },
    { id: 'nav-shared', text: 'Ghost Navigation', state: 'neutral', v: 1, src: null, doneAt: null, doneWord: null },
  ] });
  const mac = await bootDevice(browser, cfg, syncKey, seed());
  const phone = await bootDevice(browser, cfg, syncKey, seed());
  expect(await sync(mac)).not.toBeNull();
  expect(await sync(phone)).not.toBeNull();
  expect(await mac.evaluate(() => window.__buddy.state.today.date)).toBe(day1);
  expect(await phone.evaluate(() => window.__buddy.state.items.map(i => i.id))).toContain('gp-shared');

  // The PHONE completes it and pushes. The Mac is "tucked" — it never pulls this.
  await phone.evaluate(() => {
    const B = window.__buddy;
    const it = B.state.items.find(i => i.id === 'gp-shared');
    it.state = 'done'; it.doneAt = Date.now(); it.v = (it.v | 0) + 1;
    B.state.savedAt = Date.now(); B.flush(); return B.syncNow('harness');
  });

  // Midnight: the MAC rolls over WITHOUT having pulled, carrying its still-active copy forward.
  await mac.evaluate(() => {
    const B = window.__buddy;
    B.rolloverAndCarry();
    B.state.savedAt = Date.now(); B.flush();
  });
  expect(await mac.evaluate(() => window.__buddy.state.items.map(i => i.id)))
    .toContain('gp-shared');   // pre-merge the Mac genuinely still thinks it's live

  // Now they meet. The completion must win on BOTH devices, in either sync order.
  for (let i = 0; i < 3; i++) {
    expect(await sync(mac)).not.toBeNull();
    expect(await sync(phone)).not.toBeNull();
  }
  const active = p => p.evaluate(() =>
    window.__buddy.state.items.filter(i => i.state !== 'done').map(i => i.text));
  await expect.poll(async () => (await active(mac)).join('|'), { timeout: 25000 })
    .not.toContain('Ghost pricing pages');
  await expect.poll(async () => (await active(phone)).join('|'), { timeout: 25000 })
    .not.toContain('Ghost pricing pages');
  // …and the task the user did NOT finish is still there. Killing both would be its own bug.
  expect(await active(mac)).toContain('Ghost Navigation');
  expect(await active(phone)).toContain('Ghost Navigation');

  // The completion is preserved in history, not merely deleted.
  const archived = await mac.evaluate(d =>
    (window.__buddy.state.history.find(h => h.date === d) || { items: [] })
      .items.filter(i => i.text === 'Ghost pricing pages').map(i => i.done), day1);
  expect(archived).toContain(true);
});

// Field report 2026-09-02: the phone scanned the QR and said "sync", but the Mac sat on
// "Waiting for iPhone…" and never responded. The pairing view now ends on its own the
// first time a pass reads a blob written by another platform (the peer-join doorbell).
test('pairing view ends on its own once the phone writes the bucket', async ({ browser }) => {
  test.setTimeout(120000);
  const cfg = readSecret();
  test.skip(!cfg || !cfg.url, 'no .supabase-buddy.secret — live harness needs the backend');
  const syncKey = require('crypto').randomBytes(32).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const shots = process.env.BUDDY_SHOTS || null;

  const mac = await bootDevice(browser, cfg, syncKey);
  // Mac is showing the QR (what Connect does), Settings open so the pill is visible.
  await mac.evaluate(() => { const B = window.__buddy; B.syncShowQR = true; B.openDrawer(); B.openSettings(); B.renderSyncUI(); });
  const pill = () => mac.evaluate(() => document.getElementById('syncStatus').textContent);
  const qrHidden = () => mac.evaluate(() => document.getElementById('syncPairing').classList.contains('hidden'));
  expect(await pill()).toBe('Waiting for iPhone…');
  expect(await qrHidden()).toBe(false);
  if (shots) { await mac.waitForTimeout(800); await mac.evaluate(() => document.getElementById('syncStatus').scrollIntoView({ block: 'center' })); await mac.waitForTimeout(400); await mac.screenshot({ path: `${shots}/pair-before.png` }); }

  // The Mac's own echo must NOT ring the doorbell.
  await sync(mac);
  expect(await pill()).toBe('Waiting for iPhone…');

  // The phone scans, joins the same bucket, and writes as 'ios'.
  const phone = await bootDevice(browser, cfg, syncKey);
  await phone.evaluate(() => window.__buddy.setWirePlatform('ios'));
  await phone.evaluate(() => { const B = window.__buddy; B.state.items.push({ id: 'PHONE1', text: 'From the phone', state: 'neutral', v: 1 }); B.render(); });
  await sync(phone);

  // The Mac's next pass sees an ios-written blob → QR gone, pill says Synced.
  await sync(mac);
  expect(await mac.evaluate(() => window.__buddy.syncPeerPlat)).toBe('ios');
  expect(await mac.evaluate(() => window.__buddy.syncShowQR)).toBe(false);
  expect(await qrHidden()).toBe(true);
  expect(await pill()).toMatch(/^Synced \d\d:\d\d · /);
  expect((await texts(mac)).some(t => t.text === 'From the phone')).toBe(true);
  if (shots) { await mac.waitForTimeout(800); await mac.evaluate(() => document.getElementById('syncStatus').scrollIntoView({ block: 'center' })); await mac.waitForTimeout(400); await mac.screenshot({ path: `${shots}/pair-after.png` }); }
});

test('live task limit sync and offline edit survive manual parking without losing tasks', async ({ browser }) => {
  test.setTimeout(120000);
  const cfg = readSecret();
  test.skip(!cfg || !cfg.url, 'no backend configuration');
  const key = require('crypto').randomBytes(32).toString('base64url');
  const mac = await bootDevice(browser, cfg, key);
  const phone = await bootDevice(browser, cfg, key);
  try {
    await mac.evaluate(() => {
      const b=window.__buddy;
      b.state.items=Array.from({length:6},(_,i)=>({id:'limit-live-'+i,text:'Test item '+i,state:'neutral',v:1}));
      b.state.savedAt=Date.now();b.flush();return b.syncNow('capacity-seed');
    });
    await expect.poll(async()=>{await sync(phone);return (await texts(phone)).length;},{timeout:20000}).toBe(6);
    await phone.context().setOffline(true);
    await phone.evaluate(()=>{const b=window.__buddy;const i=b.state.items.find(i=>i.id==='limit-live-5');i.text='Edited while offline';i.v++;b.state.savedAt=Date.now();b.flush();});
    await mac.evaluate(()=>{const b=window.__buddy; const moved=b.state.items.splice(3); b.state.deferred.push(...moved.map(i=>({...i,wake:''}))); b.commitTaskLimit(3,b.activeSignature());return b.syncNow('capacity-reduce');});
    await settle(mac, 3500);
    await phone.context().setOffline(false);
    await expect.poll(async()=>{
      await sync(phone);await sync(mac);
      return mac.evaluate(()=>{const b=window.__buddy;return {limit:b.taskLimit(),active:b.activeCount(),future:b.state.deferred.filter(d=>!d.sent).length,edited:b.state.deferred.some(d=>d.text==='Edited while offline')};});
    },{timeout:30000}).toEqual({limit:3,active:3,future:3,edited:true});
    for(const limit of [4,5,6]) {
      await phone.evaluate(L=>{const b=window.__buddy;b.commitTaskLimit(L,b.activeSignature());return b.syncNow('capacity-raise');},limit);
      await expect.poll(async()=>{await sync(mac);return mac.evaluate(()=>window.__buddy.taskLimit());},{timeout:20000}).toBe(limit);
      expect((await texts(mac)).length).toBe(3); // increasing never silently restores Future
    }
    await sync(phone);await sync(mac);await settle(mac,3500);
    const snapshot=p=>p.evaluate(()=>{const b=window.__buddy;return {limit:b.taskLimit(),all:[...b.state.items,...b.state.deferred.filter(d=>!d.sent)].map(i=>i.id+':'+i.text).sort()};});
    expect(await snapshot(mac)).toEqual(await snapshot(phone));
    expect((await snapshot(mac)).all).toHaveLength(6);
  } finally {await mac.context().close();await phone.context().close();}
});
