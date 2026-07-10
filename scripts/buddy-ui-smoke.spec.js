const { test, expect } = require('@playwright/test');
const path = require('path');

test('Buddy UI smoke, persistence and hit targets', async ({ page }) => {
  await page.setViewportSize({ width: 452, height: 900 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => window.__buddy && window.__buddy.smokeTest);
  const smoke = await page.evaluate(() => window.__buddy.smokeTest());
  expect(smoke.ok, JSON.stringify(smoke.results.filter(r => !r.pass), null, 2)).toBeTruthy();
});

test('Mac morning Skip aligns with task text column', async ({ page }) => {
  await page.setViewportSize({ width: 584, height: 946 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => window.__buddy && window.__buddy.showMorning);
  await page.evaluate(() => window.__buddy.showMorning());
  await page.waitForSelector('#morning:not(.hidden)');

  const positions = await page.evaluate(() => {
    const rangeLeft = sel => {
      const range = document.createRange();
      range.selectNodeContents(document.querySelector(sel));
      return range.getBoundingClientRect().left;
    };
    return {
      taskTextLeft: rangeLeft('#morningList .buddy-row .cursor-text, #morningList .addrow .addtxt'),
      skipTextLeft: rangeLeft('#skipToday'),
    };
  });

  expect(Math.abs(positions.skipTextLeft - positions.taskTextLeft)).toBeLessThanOrEqual(1);
});

test('Future uses Today-style fixed rows without an extra heading', async ({ page }) => {
  await page.setViewportSize({ width: 452, height: 900 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => window.__buddy && window.__buddy.render);
  await page.evaluate(() => {
    window.__buddy.suppressSave();
    const state = window.__buddy.state;
    state.today = { date: window.__buddy.localDate(), morningDone: true, items: [] };
    state.deferred = [
      { id: 'f1', text: 'Short future task' },
      { id: 'f2', text: 'Long future task that should wrap inside a fixed-height row instead of making the row flex taller forever' },
    ];
    state.histOpen = true;
    state.histTab = 'future';
    document.querySelector('#morning').classList.add('hidden');
    window.__buddy.render();
  });

  const layout = await page.evaluate(() => {
    const rows = [...document.querySelectorAll('.future-row')];
    return {
      rowCount: rows.length,
      heights: rows.map(row => getComputedStyle(row).height),
      extraFutureHeadings: [...document.querySelectorAll('#list div, #list span, #list p')]
        .filter(el => el.textContent.trim() === 'Future' && !el.closest('button')).length,
    };
  });

  expect(layout.rowCount).toBe(2);
  expect(layout.heights).toEqual(['110px', '110px']);
  expect(layout.extraFutureHeadings).toBe(0);

  const hoverActions = await page.evaluate(() => {
    const row = document.querySelector('.future-row');
    const rail = row?.querySelector('[title="Add to today"]')?.parentElement;
    return {
      add: !!row?.querySelector('[title="Add to today"]'),
      remove: !!row?.querySelector('[title="Remove"]'),
      hoverRail: !!rail?.className.includes('group-hover/h:opacity-100'),
    };
  });

  expect(hoverActions.add).toBeTruthy();
  expect(hoverActions.remove).toBeTruthy();
  expect(hoverActions.hoverRail).toBeTruthy();
});
