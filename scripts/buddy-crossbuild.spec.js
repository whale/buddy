// CROSS-BUILD convergence — the gap that let a real blocker through review.
//
// Every other suite runs ONE build against itself, so it is structurally incapable of catching
// a divergence between an updated Mac and a peer still on the old build. That window is real
// and it is measured in DAYS: the Mac auto-releases on merge to main, while iOS ships only when
// someone runs `fastlane beta` (RULE 5). If the two builds disagree about whether a row is
// live, each one "corrects" the other and they push at each other every 1.5s — with the task
// visibly flickering — until the phone is updated. That is strictly worse than the bug being
// fixed, so it has to be pinned.
//
// This boots one page on origin/main's dist/index.html and one on the working tree's, feeds
// both the SAME wire blobs, and asserts they agree on what survives.
//
// Run: pnpm test:crossbuild
const { test, expect } = require('@playwright/test');
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const REPO = path.join(__dirname, '..');
let oldBuildPath;

test.beforeAll(() => {
  const html = execFileSync('git', ['-C', REPO, 'show', 'origin/main:dist/index.html'], {
    encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
  });
  oldBuildPath = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'buddy-old-')), 'index.html');
  fs.writeFileSync(oldBuildPath, html);
});

async function open(page, file) {
  await page.goto('file://' + file);
  await page.waitForFunction(() => typeof window.mergeWire === 'function');
}

// Yesterday's list, as each side actually holds it at the moment they meet.
const ROLLED = {                       // the device that rolled over WITHOUT seeing the completion
  version: 1, savedAt: 1000,
  today: { date: '2026-06-20', morningDone: true, items: [
    { id: 'gp', text: 'Ghost pricing pages', state: 'neutral', v: 3 },
    { id: 'nav', text: 'Ghost Navigation', state: 'neutral', v: 1 }] },
  history: [], deferred: [], settings: { celebrate: 100, reserveSpace: false },
  pinned: false, tombstones: {}, erasedAt: null,
};
const COMPLETED = {                    // the device that completed it and has NOT rolled yet
  version: 1, savedAt: 2000,
  today: { date: '2026-06-19', morningDone: true, items: [
    { id: 'gp', text: 'Ghost pricing pages', state: 'done', v: 4, doneAt: 1500 },
    { id: 'nav', text: 'Ghost Navigation', state: 'neutral', v: 1 }] },
  history: [], deferred: [], settings: { celebrate: 100, reserveSpace: false },
  pinned: false, tombstones: {}, erasedAt: null,
};

const activeIds = blob => (blob.today.items || []).filter(i => i.state !== 'done').map(i => i.id).sort();

test('an OLD peer converges on the new build\'s merge instead of push-fighting it', async ({ browser }) => {
  const newPage = await (await browser.newContext()).newPage();
  const oldPage = await (await browser.newContext()).newPage();
  await open(newPage, path.join(REPO, 'dist/index.html'));
  await open(oldPage, oldBuildPath);

  // The NEW build merges the two days. This is what lands in the shared bucket.
  const merged = await newPage.evaluate(([a, b]) => window.mergeWire(a, b), [ROLLED, COMPLETED]);
  expect(activeIds(merged), 'new build should retire the completed task').toEqual(['nav']);

  // Now the OLD build pulls that row and merges its own (stale, still-active) copy against it.
  // If it re-adds the task, it pushes, the new build retires it again, and round they go.
  const oldResult = await oldPage.evaluate(([a, b]) => window.mergeWire(a, b), [ROLLED, merged]);
  expect(activeIds(oldResult),
    'OLD build re-added the completed task → the two builds push-fight until the phone updates')
    .toEqual(['nav']);

  // And it must be a FIXED POINT: feeding the old build's output back to the new one changes
  // nothing. Otherwise the loop is just slower, not absent.
  const settled = await newPage.evaluate(([a, b]) => window.mergeWire(a, b), [oldResult, merged]);
  expect(activeIds(settled)).toEqual(['nav']);
});

test('an old peer does not strip the new build\'s history ordering into oblivion', async ({ browser }) => {
  const newPage = await (await browser.newContext()).newPage();
  const oldPage = await (await browser.newContext()).newPage();
  await open(newPage, path.join(REPO, 'dist/index.html'));
  await open(oldPage, oldBuildPath);

  const withOrd = {
    version: 1, savedAt: 2000,
    today: { date: '2026-06-20', morningDone: true, items: [] },
    history: [{ date: '2026-06-19', weekday: 'Friday', items: [
      { id: 'zzz', ord: 0, text: 'first', done: false },
      { id: 'aaa', ord: 1, text: 'second', done: false }] }],
    deferred: [], settings: { celebrate: 100, reserveSpace: false },
    pinned: false, tombstones: {}, erasedAt: null,
  };
  const empty = { ...withOrd, savedAt: 1000, history: [] };

  // Round-trip through the old build, then merge back on the new one.
  const viaOld = await oldPage.evaluate(([a, b]) => window.mergeWire(a, b), [withOrd, empty]);
  const back = await newPage.evaluate(([a, b]) => window.mergeWire(a, b), [viaOld, withOrd]);
  const rec = back.history.find(h => h.date === '2026-06-19');
  expect(rec.items.map(i => i.id), 'planner order survived the old peer').toEqual(['zzz', 'aaa']);
});
