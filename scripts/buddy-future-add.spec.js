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
  await page.getByText('Done', { exact: true }).click(); await settle(page);
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

test('long text grows the row while editing, back to 110px after', async ({ page }) => {
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
  expect(heights).toEqual([110, 110, 110]);
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
