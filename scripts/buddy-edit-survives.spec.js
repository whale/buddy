// Field report 2026-08-09: "I was at 5 tasks and it wouldn't let me add the 6th."
//
// One cause, three faces. renderToday() rebuilds every row from scratch, and the ONLY thing
// that captures typed text or cleans up a blank row is the contenteditable's `blur` handler —
// which WebKit does not fire when the focused node is REMOVED rather than left. So any render
// triggered by something else (ticking ✓ on another row, the Donezo morph 1.2s later, a sync
// adopt) used to: throw away the typing, strand the row in state with text:'', and leak
// editingId — which makes the global key layer inert, so Return itself stops working.
//
// The stranded blank then ate a HARD_CAP slot while escalationCount() (which trims) ignored it,
// so the drawer showed FIVE tasks and refused a sixth.
//
// Run: pnpm test:edit
const { test, expect } = require('@playwright/test');
const path = require('path');

async function boot(page, items) {
  await page.setViewportSize({ width: 452, height: 900 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => !!(window.__buddy && window.__buddy.render));
  await page.evaluate(list => {
    const B = window.__buddy;
    B.suppressSave();
    document.getElementById('morning').classList.add('hidden');
    B.state.today = { date: B.localDate(), morningDone: true, items: list.map((t, i) => (
      { id: 'seed' + i, text: t, state: 'neutral', v: 1, src: null, doneAt: null, doneWord: null })) };
    B.openDrawer(); B.render();
  }, items);
}
// Deliberately built from state + the DOM only — NO accessor this branch adds. A test that fails
// on main merely because `__buddy.activeCount` is undefined proves nothing about behaviour.
// (Also: never call editingActive() to inspect the guard — it HEALS it as a side effect, so any
// check that touches it is self-fulfilling.)
const snap = page => page.evaluate(() => {
  const items = window.__buddy.state.items;
  const inMorning = el => !!el.closest('#morning');
  const addRows = [...document.querySelectorAll('.addrow')].filter(el => !inMorning(el));
  return {
    texts: items.map(i => i.text),
    active: items.filter(i => i.state !== 'done').length,
    blanks: items.filter(i => i.state !== 'done' && !String(i.text || '').trim()).length,
    addRow: addRows.length > 0,
  };
});

test('text typed BEFORE a foreign re-render is never lost', async ({ page }) => {
  await boot(page, ['one', 'two', 'three']);
  await page.evaluate(() => window.addAndEdit());
  await page.waitForTimeout(120);
  await page.keyboard.type('My new task');
  // Something else re-renders mid-edit — what happens when you tick ✓ on another row, or the
  // Donezo morph fires ~1.2s after a completion, or a sync pass adopts.
  await page.evaluate(() => window.__buddy.render());
  await page.waitForTimeout(80);
  const s = await snap(page);
  expect(s.texts, 'the row being edited was swept while it still had text').toContain('My new task');
});

test('a REAL stranded row is swept even though editingId still points at it', async ({ page }) => {
  await boot(page, ['one', 'two', 'three', 'four', 'five']);
  // Reproduce the strand the way the app actually creates one: add a row (so the editor is
  // live), then let a foreign render tear it out. In WebKit no blur fires, so editingId is left
  // pointing AT THE CORPSE — which is exactly why guarding the sweep on editingId made it a
  // no-op in the only case that matters.
  await page.evaluate(() => window.addAndEdit());
  await page.waitForTimeout(150);
  await page.evaluate(() => { document.activeElement.blur(); });   // focus gone, row not committed
  const s = await page.evaluate(() => {
    const B = window.__buddy;
    B.state.items.push({ id:'corpse', text:'', state:'neutral', v:1, src:null, doneAt:null, doneWord:null });
    B.render();
    return null;
  });
  const after = await snap(page);
  expect(after.blanks, 'a stranded untitled row survived the render').toBe(0);
  expect(after.active, 'the cap slot was never freed').toBe(5);
  expect(after.addRow, 'still no way to add a 6th task').toBeTruthy();
  // A dangling guard makes the global key layer inert — prove it behaviourally rather than by
  // reading editingId, so this asserts what the USER experiences.
  await page.keyboard.press('a');            // 'a' opens a new task row
  await page.waitForTimeout(150);
  await page.keyboard.type('sixth');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  expect((await snap(page)).texts, 'the keyboard was dead after the strand').toContain('sixth');
});

test('what you SEE and what the cap counts never disagree', async ({ page }) => {
  await boot(page, ['one', 'two', 'three', 'four', 'five']);
  // Exactly the reported state: five real tasks plus one stranded untitled row.
  await page.evaluate(() => {
    const B = window.__buddy;
    B.state.items.push({ id: 'ghost', text: '', state: 'neutral', v: 1, src: null, doneAt: null, doneWord: null });
    B.render();
  });
  const s = await snap(page);
  expect(s.active, 'cap counter disagrees with what the user sees').toBe(5);
  expect(s.addRow, 'the Add row vanished with 5 visible tasks').toBeTruthy();
});

test('the untitled placeholder is not gated on being focused', async ({ page }) => {
  await boot(page, ['one']);
  // Gated on [contenteditable] the placeholder only showed WHILE editing, so a row that lost its
  // editor was a blank white band the eye reads as padding. Assert the RULE, not a timing window.
  const ph = await page.evaluate(() => {
    const el = document.createElement('div');
    el.className = 'empty';
    el.setAttribute('data-ph', 'Untitled');
    document.querySelector('.buddy-row').parentNode.appendChild(el);
    const c = getComputedStyle(el, '::before');
    return { content: c.content, color: c.color };
  });
  expect(ph.content, 'an untitled row renders nothing at all — an invisible band').not.toBe('none');
  // RULE 1: it must ride the token, not a hardcoded dark colour that vanishes on red.
  expect(ph.color, 'placeholder must ride --ink-dim, not a hardcoded dark').toBe('rgba(0, 0, 0, 0.45)');
});

// THE ACTUAL REPORTED GESTURE, mouse only: you're editing a task, you click Add, you type.
// The Add row's mousedown is preventDefault'ed so the row you were editing never blurs — which
// means anything that re-focuses "the row that was being edited" races the new row's editor.
test('click a task, click Add, type — the new task keeps every character', async ({ page }) => {
  await boot(page, ['one', 'two', 'three', 'four', 'five']);
  await page.locator('[data-tid="seed4"]').click();          // start editing "five"
  await page.waitForTimeout(120);
  await page.evaluate(() => window.__buddy.todayWrap.querySelector('.addrow').click());
  await page.waitForTimeout(180);
  await page.keyboard.type('sixth task');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(200);
  const s = await snap(page);
  expect(s.texts).toEqual(['one', 'two', 'three', 'four', 'five', 'sixth task']);
});

// A sync pass landing in the one frame between addAndEdit() and startEdit() must not delete the
// row being added. editingActive() HEALS the guard in that frame (no contenteditable exists yet),
// so anything relying on editingId to protect the new row deletes it — and the keystrokes then
// fall through to the global key layer as SHORTCUTS.
test('a sync heal between add and focus does not eat the new row', async ({ page }) => {
  await boot(page, ['aaa']);
  await page.evaluate(() => { window.addAndEdit(); window.editingActive(); window.__buddy.render(); });
  await page.waitForTimeout(150);
  await page.keyboard.type('typed after the race');
  await page.keyboard.press('Enter');
  await page.waitForTimeout(150);
  expect((await snap(page)).texts).toEqual(['aaa', 'typed after the race']);
});
