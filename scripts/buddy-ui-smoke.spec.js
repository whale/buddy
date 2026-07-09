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
