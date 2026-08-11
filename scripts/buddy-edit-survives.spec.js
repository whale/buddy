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
const snap = page => page.evaluate(() => ({
  texts: window.__buddy.state.items.map(i => i.text),
  active: window.__buddy.activeCount(),
  escalation: window.__buddy.escalationCount(),
  editing: window.editingActive(),
}));

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

test('an untitled row nobody is editing is swept, freeing its cap slot', async ({ page }) => {
  await boot(page, ['one', 'two', 'three', 'four', 'five']);
  // A corpse: blank, active, and NOT the row being edited (editingId is null here). This is the
  // exact state the user was stuck in — five visible tasks, cap says six.
  const s = await page.evaluate(() => {
    const B = window.__buddy;
    B.state.items.push({ id:'ghost', text:'', state:'neutral', v:1, src:null, doneAt:null, doneWord:null });
    const before = window.__buddy.activeCount();
    B.render();
    return { before, after: window.__buddy.activeCount(),
             ghostGone: !B.state.items.some(i => i.id==='ghost'),
             addRow: !!B.todayWrap.querySelector('.addrow') };
  });
  expect(s.before, 'setup wrong — the corpse should have counted').toBe(6);
  expect(s.ghostGone, 'the stranded blank row survived a render').toBeTruthy();
  expect(s.after, 'the cap slot was not freed').toBe(5);
  expect(s.addRow, 'still no way to add a 6th task').toBeTruthy();
});

test('what you SEE and what the cap counts never disagree', async ({ page }) => {
  await boot(page, ['one', 'two', 'three', 'four', 'five']);
  // Exactly the reported state: five real tasks plus one stranded untitled row.
  const s = await page.evaluate(() => {
    const B = window.__buddy;
    B.state.items.push({ id: 'ghost', text: '', state: 'neutral', v: 1, src: null, doneAt: null, doneWord: null });
    B.render();
    return {
      active: window.__buddy.activeCount(),
      escalation: window.__buddy.escalationCount(),
      // NB: the row containers are created in JS with no id, so `#todayWrap` silently matches
      // NOTHING and any assertion built on it is vacuous. Reach them through __buddy.
      addRow: !!window.__buddy.todayWrap.querySelector('.addrow'),
    };
  });
  expect(s.active, 'cap counter disagrees with what the user sees').toBe(5);
  expect(s.escalation).toBe(5);
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
    window.__buddy.todayWrap.appendChild(el);
    const c = getComputedStyle(el, '::before');
    return { content: c.content, color: c.color };
  });
  expect(ph.content, 'an untitled row renders nothing at all — an invisible band').not.toBe('none');
  // RULE 1: it must ride the token, not a hardcoded dark colour that vanishes on red.
  expect(ph.color).not.toBe('rgba(0, 0, 0, 0.2)');
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
