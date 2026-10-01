// Add straight into Future, with the same UX as Today's Add row (whale 2026-10-01).
//
// Each case below is a bug the first prototype actually hit:
//  - clicking Add while typing glued two entries together ("OneTwo") and left a blank ghost
//  - clicking Add twice left a blank ghost item in state (would sync as an empty task)
//  - the blank row showed + / × that act on an empty task
//  - long text overflowed the fixed 110px row while editing
//  - Tab didn't hop rows like Today
//  - a background render mid-typing cut the text short ("Ty…")
//
// Run: pnpm test:future (WebKit = the shipping Tauri engine, and Chromium)
const { test, expect } = require('@playwright/test');
const path = require('path');

const BASE = ['Renew passport', 'Call the dentist about the crown'];
const EXTRA = ['Plan the Japan trip', 'Learn to sharpen knives', 'Fix the bike tyre', 'Frame the prints', 'Sort the garage', 'Back up old photos'];

async function boot(page, { long = false, today = 2 } = {}) {
  await page.setViewportSize({ width: 452, height: 900 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => !!(window.__buddy && window.__buddy.render));
  await page.evaluate(([deferred, n]) => {
    const B = window.__buddy; B.suppressSave(); const s = B.state;
    s.today = { date: B.localDate(), morningDone: true, items: Array.from({ length: n }, (_, i) => ({ id: 't' + i, text: 'Task ' + i, state: 'todo', v: 1 })) };
    s.deferred = deferred.map((text, i) => ({ id: 'f' + i, text, wake: '', v: 1 }));
    s.histOpen = true; s.histTab = 'future';
    document.querySelector('#morning').classList.add('hidden');
    // Browser-only dev button (absent in the Tauri app) sits over the bottom-left of the drawer —
    // right where a shrunk Add row lands — and would swallow the clicks.
    const dev = document.getElementById('devMorning'); if (dev) dev.style.display = 'none';
    B.openDrawer(); B.render();
  }, [long ? BASE.concat(EXTRA) : BASE, today]);
  await page.waitForTimeout(600);
}
const texts = page => page.evaluate(() => window.__buddy.state.deferred.map(d => d.text));
const versions = page => page.evaluate(() => window.__buddy.state.deferred.map(d => d.v | 0));
async function clickAdd(page) {
  const r = await page.locator('.future-add').boundingBox();
  await page.mouse.click(r.x + 60, r.y + r.height / 2);
  await page.waitForTimeout(120);
}
async function clickTitle(page, i) {
  const r = await page.locator('.future-title').nth(i).boundingBox();
  await page.mouse.click(r.x + r.width - 2, r.y + r.height - 6);   // bottom-right = end of the last line
  await page.waitForTimeout(120);
}
const settle = page => page.waitForTimeout(150);

test('Add opens a draft that is NOT in state and has no row actions; Enter commits it at the bottom', async ({ page }) => {
  await boot(page);
  await clickAdd(page);
  expect(await texts(page)).toEqual(BASE);                       // draft never touches state (no blank sync)
  const draft = await page.evaluate(() => {
    const el = document.activeElement, row = el.closest('.future-row');
    return { isField: !!el.dataset.fid, buttons: row.querySelectorAll('button').length };
  });
  expect(draft).toEqual({ isField: true, buttons: 0 });
  await page.keyboard.type('Plan the Japan trip');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual([...BASE, 'Plan the Japan trip']);
  const domOrder = await page.evaluate(() => [...document.querySelectorAll('.future-title')].map(e => e.textContent));
  expect(domOrder).toEqual([...BASE, 'Plan the Japan trip']);    // oldest first, new one right above Add
});

test('clicking Add while typing commits the first entry and starts a fresh one (no glue, no ghost)', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('One');
  await clickAdd(page); await page.keyboard.type('Two');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual([...BASE, 'One', 'Two']);
});

test('Add twice / empty draft / whitespace leaves nothing behind', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await clickAdd(page);
  await page.keyboard.type('   ');
  await page.keyboard.press('Escape'); await settle(page);
  expect(await texts(page)).toEqual(BASE);
});

test('closing the panel or switching tab mid-typing keeps the text', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('Half');
  await page.click('#histSheet button[title=Close]'); await settle(page);
  expect(await texts(page)).toEqual([...BASE, 'Half']);

  await boot(page);
  await clickAdd(page); await page.keyboard.type('Tabbed');
  await page.locator('#histSheet button', { hasText: /^Done/ }).click(); await settle(page);
  expect(await texts(page)).toEqual([...BASE, 'Tabbed']);
});

test('existing rows edit in place: v bumps, Esc commits without closing, emptied row deletes', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0); await page.keyboard.type(' now');
  await page.keyboard.press('Escape'); await settle(page);
  expect(await texts(page)).toEqual(['Renew passport now', BASE[1]]);
  expect(await versions(page)).toEqual([2, 1]);
  expect(await page.evaluate(() => window.__buddy.state.histOpen)).toBe(true);

  await clickTitle(page, 1);
  await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.press('Backspace');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual(['Renew passport now']);
  expect(await page.evaluate(() => !!window.__buddy.state.tombstones.f1)).toBe(true);   // tombstoned so sync can't resurrect it
});

test('click from one field straight into another commits both', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('Draft');
  await clickTitle(page, 0); await page.keyboard.type('!');
  await clickTitle(page, 1); await page.keyboard.type('?');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual(['Renew passport!', BASE[1] + '?', 'Draft']);
});

test('Tab hops rows like Today and chains a new Add past the last row', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0);
  await page.keyboard.press('Tab'); await page.keyboard.type('+');
  await page.keyboard.press('Tab'); await page.keyboard.type('New via tab');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual([BASE[0], BASE[1] + '+', 'New via tab']);
});

test('typing survives constant background renders and never triggers shortcuts', async ({ page }) => {
  await boot(page);
  await clickAdd(page);
  await page.evaluate(() => { window.__storm = setInterval(() => window.__buddy.render(), 30); });
  await page.keyboard.type('Typed during constant renders b n t', { delay: 15 });
  await page.evaluate(() => clearInterval(window.__storm));
  expect(await texts(page)).toEqual(BASE);                       // shortcuts (b/n/t) did nothing
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual([...BASE, 'Typed during constant renders b n t']);
});

test('long text grows the row while editing, back to equal filling rows after', async ({ page }) => {
  await boot(page);
  await clickAdd(page);
  await page.keyboard.type('A very long future task that wraps onto many many lines to see what happens with the row height here');
  const fit = await page.evaluate(() => {
    const el = document.activeElement, row = el.closest('.future-row');
    return el.getBoundingClientRect().bottom <= row.getBoundingClientRect().bottom;
  });
  expect(fit).toBe(true);
  await page.keyboard.press('Enter'); await settle(page);
  const heights = await page.evaluate(() => [...document.querySelectorAll('.future-row')].map(r => r.offsetHeight));
  expect(new Set(heights).size).toBe(1);                         // the 2-line clamp keeps rows equal again
  expect(heights[0]).toBeGreaterThanOrEqual(110);
});

test('long list: Add is pinned to the bottom and the new row scrolls into view above it', async ({ page }) => {
  await boot(page, { long: true });
  const pinned = await page.evaluate(() => {
    const a = document.querySelector('.future-add').getBoundingClientRect();
    const sheet = document.querySelector('#histSheet').getBoundingClientRect();
    return Math.round(a.bottom) === Math.round(sheet.bottom);
  });
  expect(pinned).toBe(true);
  await clickAdd(page); await page.keyboard.type('New at bottom');
  const visible = await page.evaluate(() => {
    const r = document.activeElement.getBoundingClientRect(), a = document.querySelector('.future-add').getBoundingClientRect();
    return r.top > 0 && r.bottom <= a.top + 1;
  });
  expect(visible).toBe(true);
});

test('+ on a row mid-edit sends the typed text to today', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0); await page.keyboard.type(' (renewed)');
  const row = page.locator('.future-row').first();
  await row.hover(); await row.locator('button[title="Add to today"]').click(); await settle(page);
  const today = await page.evaluate(() => window.__buddy.state.items.map(i => i.text));
  expect(today).toContain('Renew passport (renewed)');
});

// ---- Adversarial review round (skeptic 2026-10-01) ----

test('caret stays where you clicked — across row-to-row clicks and background renders', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0);
  const t = page.locator('.future-title').nth(1);
  const r = await t.boundingBox();
  await page.mouse.click(r.x + 3, r.y + 12);                     // just inside the start of row 1
  await page.waitForTimeout(150);
  await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight'); await page.keyboard.press('ArrowRight');
  await page.keyboard.type('X');
  await page.evaluate(() => window.__buddy.render());
  await page.keyboard.type('Y');
  await page.keyboard.press('Enter'); await settle(page);
  expect((await texts(page))[1]).toBe('CallXY the dentist about the crown');
});

test('a leftover Tab ring does not let a second Enter send a row to today', async ({ page }) => {
  await boot(page);
  await page.locator('.future-add').hover();
  await page.keyboard.press('Tab');                              // ring on row 0
  await clickAdd(page); await page.keyboard.type('New');
  await page.keyboard.press('Enter'); await settle(page);
  await page.keyboard.press('Enter'); await settle(page);
  expect(await page.evaluate(() => window.__buddy.state.items.map(i => i.text))).toEqual(['Task 0', 'Task 1']);
});

test('the draft row does not replay its entrance animation on re-render', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('Draft');
  await page.waitForTimeout(300);
  await page.evaluate(() => window.__buddy.render());
  const animating = await page.evaluate(() => document.activeElement.closest('.future-row').classList.contains('item-enter'));
  expect(animating).toBe(false);
});

test('hiding the window mid-typing saves the draft and the edit', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0); await page.keyboard.type(' soon');
  await page.evaluate(() => { Object.defineProperty(document, 'visibilityState', { value: 'hidden', configurable: true }); window.dispatchEvent(new Event('visibilitychange')); });
  expect(await texts(page)).toEqual(['Renew passport soon', BASE[1]]);

  await boot(page);
  await clickAdd(page); await page.keyboard.type('Unsaved draft');
  await page.evaluate(() => window.dispatchEvent(new Event('beforeunload')));
  expect(await texts(page)).toEqual([...BASE, 'Unsaved draft']);
});

test('an IME confirm-Enter (keyCode 229) does not commit the field', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('nihon');
  await page.evaluate(() => document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', keyCode: 229, bubbles: true, cancelable: true })));
  await settle(page);
  const stillEditing = await page.evaluate(() => !!document.activeElement.dataset.fid);
  expect(stillEditing).toBe(true);
  expect(await texts(page)).toEqual(BASE);
});

test('clicking + on a row you just emptied removes it instead of leaving a blank', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 0);
  await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.press('Backspace');
  const row = page.locator('.future-row').first();
  await row.hover(); await row.locator('button[title="Add to today"]').click(); await settle(page);
  expect(await texts(page)).toEqual([BASE[1]]);
  expect(await page.evaluate(() => document.querySelectorAll('.future-title').length)).toBe(1);
  expect(await page.evaluate(() => window.__buddy.state.items.length)).toBe(2);   // nothing blank sent to today
});

// ---- Second adversarial round (fresh reviewers 2026-10-01) ----

// A real press takes ~90ms; Playwright's instant click hid the two-click bug.
async function humanClick(page, locator) {
  const r = await locator.boundingBox();
  await page.mouse.move(r.x + r.width / 2, r.y + r.height / 2);
  await page.mouse.down(); await page.waitForTimeout(90); await page.mouse.up();
  await page.waitForTimeout(150);
}

test('adding a title that is already in Future does not create a twin (sync would drop one)', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('  renew   PASSPORT ');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual(BASE);                       // nothing new, nothing lost
  const ringed = await page.evaluate(() => document.querySelector('[data-fid="f0"]').closest('.future-row').classList.contains('cursor-ring'));
  expect(ringed).toBe(true);                                      // the existing row is pointed out
  await page.waitForTimeout(1400);
  expect(await page.evaluate(() => document.querySelectorAll('.future-row.cursor-ring').length)).toBe(0);
});

test('renaming a row to match another keeps the renamed one and tombstones the twin', async ({ page }) => {
  await boot(page);
  await clickTitle(page, 1);
  await page.keyboard.press('ControlOrMeta+A'); await page.keyboard.type('Renew Passport');
  await page.keyboard.press('Enter'); await settle(page);
  expect(await texts(page)).toEqual(['Renew Passport']);
  expect(await page.evaluate(() => window.__buddy.state.deferred[0].id)).toBe('f1');
  expect(await page.evaluate(() => !!window.__buddy.state.tombstones.f0)).toBe(true);
});

test('long typing in a long list stays visible above the sticky Add row', async ({ page }) => {
  await boot(page, { long: true });
  await clickAdd(page);
  await page.keyboard.type('A very long future task that keeps going and going so it wraps onto four lines under the add row');
  const ok = await page.evaluate(() => {
    const r = document.activeElement.getBoundingClientRect(), a = document.querySelector('.future-add').getBoundingClientRect();
    return r.bottom <= a.top + 1;
  });
  expect(ok).toBe(true);
});

test('mid-edit, the Done tab and the close button work on the FIRST human-speed click', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('Via tab');
  await humanClick(page, page.locator('#histSheet button', { hasText: /^Done/ }));
  expect(await page.evaluate(() => window.__buddy.state.histTab)).toBe('past');
  expect(await texts(page)).toEqual([...BASE, 'Via tab']);

  await boot(page);
  await clickTitle(page, 0); await page.keyboard.type('!');
  await humanClick(page, page.locator('#histSheet button[title=Close]'));
  expect(await page.evaluate(() => window.__buddy.state.histOpen)).toBe(false);
  expect(await texts(page)).toEqual(['Renew passport!', BASE[1]]);
});

test('a render landing right after Enter does not pull focus back into the field', async ({ page }) => {
  await boot(page);
  await clickAdd(page); await page.keyboard.type('Done typing');
  await page.evaluate(() => {
    const el = document.activeElement;
    el.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true }));
    window.__buddy.render();
  });
  await settle(page);
  expect(await page.evaluate(() => !!document.activeElement.dataset.fid)).toBe(false);
  expect(await texts(page)).toEqual([...BASE, 'Done typing']);
});

// ---- Layout (whale 2026-10-01): fill like Today until it can't, then scroll under a sticky Add ----

const rowHeights = page => page.evaluate(() => [...document.querySelectorAll('.future-list > .future-row, .future-list > .future-add')]
  .map(r => ({ kind: r.classList.contains('future-sent') ? 'sent' : r.classList.contains('future-add') ? 'add' : 'row', h: Math.round(r.getBoundingClientRect().height) })));

test('few items: rows + Add share the panel equally, no empty band at the bottom', async ({ page }) => {
  await boot(page);
  const rows = await rowHeights(page);
  expect(rows.map(r => r.kind)).toEqual(['row', 'row', 'add']);
  expect(new Set(rows.map(r => r.h)).size).toBe(1);              // equal, exactly like Today
  expect(rows[0].h).toBeGreaterThan(110);
  const gap = await page.evaluate(() => Math.round(document.querySelector('#histSheet').getBoundingClientRect().bottom - document.querySelector('.future-add').getBoundingClientRect().bottom));
  expect(gap).toBe(0);
});

test('sent rows sit on top and stay thin; plain rows still fill', async ({ page }) => {
  await boot(page, { today: 3 });
  await page.evaluate(() => {
    const s = window.__buddy.state;
    s.deferred.push({ id: 'fs', text: 'Ghost Navigation', wake: '', v: 2, sent: true, sentTid: 't0' });
    window.__buddy.render();
  });
  const rows = await rowHeights(page);
  expect(rows.map(r => r.kind)).toEqual(['sent', 'row', 'row', 'add']);
  expect(rows[0].h).toBeLessThan(80);
  expect(rows[1].h).toBe(rows[2].h);
  expect(rows[1].h).toBeGreaterThan(110);
});

test('too many items: rows shrink to the sent-row size, then the list scrolls with Add pinned', async ({ page }) => {
  await boot(page, { long: true });
  await page.evaluate(() => { const s = window.__buddy.state; for (let i = 0; i < 6; i++) s.deferred.push({ id: 'x' + i, text: 'Extra ' + i, wake: '', v: 1 }); window.__buddy.render(); });
  const rows = await rowHeights(page);
  const fit = await page.evaluate(() => { const l = document.querySelector('.future-list'); return { ffs: l.style.getPropertyValue('--ffs'), fmin: l.style.getPropertyValue('--fmin') }; });
  expect(fit).toEqual({ ffs: '18.00px', fmin: '59px' });          // smallest step = the "Sent to today!" row
  expect(rows.filter(r => r.kind === 'row').every(r => r.h >= 59)).toBe(true);
  const pinned = await page.evaluate(async () => {
    const scroller = document.querySelector('.future-body').parentElement;
    const before = document.querySelector('.future-add').getBoundingClientRect().bottom;
    scroller.scrollTop = 120; await new Promise(r => requestAnimationFrame(r));
    return { scrolls: scroller.scrollHeight > scroller.clientHeight, still: document.querySelector('.future-add').getBoundingClientRect().bottom === before };
  });
  expect(pinned).toEqual({ scrolls: true, still: true });
});

test('as Future fills, text and rows shrink step by step before anything scrolls', async ({ page }) => {
  const steps = [];
  for (const n of [2, 5, 7]) {
    await boot(page);
    await page.evaluate(n => { const s = window.__buddy.state; s.deferred = Array.from({ length: n }, (_, i) => ({ id: 'f' + i, text: 'Item ' + i, wake: '', v: 1 })); window.__buddy.render(); }, n);
    steps.push(await page.evaluate(() => {
      const l = document.querySelector('.future-list'), sc = document.querySelector('.future-body').parentElement;
      return { fs: parseFloat(l.style.getPropertyValue('--ffs')), scrolls: sc.scrollHeight > sc.clientHeight + 1 };
    }));
  }
  expect(steps[0].fs).toBe(24);
  expect(steps[1].fs).toBeLessThan(24);
  expect(steps[2].fs).toBeLessThan(steps[1].fs);
  expect(steps.every(x => !x.scrolls)).toBe(true);                // all of these still fit — no scrolling yet
});

test('tabs show Future (n) / Done (n), with a quieter count that stays on one line', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => {
    const s = window.__buddy.state;
    s.today.items[0].state = 'done';
    s.history = [{ date: '2026-09-30', weekday: 'Tue', items: [{ id: 'h1', text: 'old', done: true }, { id: 'h2', text: 'not done', done: false }] }];
    s.deferred.push({ id: 'fs', text: 'Sent one', wake: '', v: 2, sent: true, sentTid: 't0' });
    window.__buddy.render();
  });
  const tabs = await page.evaluate(() => [...document.querySelectorAll('#histSheet button')].filter(b => /\(\d+\)/.test(b.textContent))
    .map(b => ({ text: b.textContent, oneLine: b.getBoundingClientRect().height < 45, quiet: getComputedStyle(b.querySelector('.seg-count')).opacity })));
  expect(tabs.map(t => t.text)).toEqual(['Future (2)', 'Done (2)']);   // sent rows aren't waiting; undone history isn't done
  expect(tabs.every(t => t.oneLine && t.quiet === '0.55')).toBe(true);
});

// ---- "N more ↓" in the sticky Add row (whale 2026-10-01: chose the quiet count) ----

test('quiet count: shows how many rows hide under Add, click scrolls (does not add), fades out at the bottom', async ({ page }) => {
  await boot(page);
  const on = () => page.evaluate(() => document.querySelector('.future-more').classList.contains('on'));
  const label = () => page.evaluate(() => document.querySelector('.future-more').textContent.replace(/\s+/g, ' ').trim());
  expect(await on()).toBe(false);                                 // short list: nothing hidden
  await page.evaluate(() => { const s = window.__buddy.state; s.deferred = Array.from({ length: 16 }, (_, i) => ({ id: 'f' + i, text: 'Item ' + i, wake: '', v: 1 })); window.__buddy.render(); });
  await page.waitForTimeout(600);
  expect(await on()).toBe(true);
  const n = parseInt(await label(), 10);
  expect(n).toBeGreaterThan(0);
  expect(await label()).toBe(n + ' more ↓');
  await page.locator('.future-more').click(); await page.waitForTimeout(900);
  expect(await texts(page)).toHaveLength(16);                    // the click scrolled — no draft, no new item
  expect(await page.evaluate(() => !!document.activeElement.dataset.fid)).toBe(false);
  expect(await on()).toBe(false);                                 // at the bottom: fading out
  expect(await page.evaluate(() => getComputedStyle(document.querySelector('.future-more')).pointerEvents)).toBe('none');
});

test('quiet count: changes once per row (half-hidden rule), and a render does not replay its fade', async ({ page }) => {
  await boot(page);
  await page.evaluate(() => { const s = window.__buddy.state; s.deferred = Array.from({ length: 16 }, (_, i) => ({ id: 'f' + i, text: 'Item ' + i, wake: '', v: 1 })); window.__buddy.render(); });
  await page.waitForTimeout(600);
  // Scroll in small steps across ~2 rows and record every distinct value seen.
  const seen = await page.evaluate(async () => {
    const sc = document.querySelector('.future-body').parentElement, vals = [];
    const read = () => parseInt(document.querySelector('.future-more .fm-num > span:last-child').textContent, 10);
    for (let y = 0; y <= 120; y += 4) { sc.scrollTop = y; await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))); const v = read(); if (vals[vals.length - 1] !== v) vals.push(v); }
    return vals;
  });
  for (let i = 1; i < seen.length; i++) expect(seen[i - 1] - seen[i]).toBe(1);   // steps of one, never back-and-forth
  const replay = await page.evaluate(async () => {
    window.__buddy.render();
    const m = document.querySelector('.future-more');
    return { on: m.classList.contains('on'), still: m.classList.contains('still') };
  });
  expect(replay).toEqual({ on: true, still: true });              // reborn already showing, without a fade
});
