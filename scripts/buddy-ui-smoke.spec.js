const { test, expect } = require('@playwright/test');
const path = require('path');

test('Buddy UI smoke, persistence and hit targets', async ({ page }) => {
  await page.setViewportSize({ width: 452, height: 900 });
  await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
  await page.waitForFunction(() => window.__buddy && window.__buddy.smokeTest);
  const smoke = await page.evaluate(() => window.__buddy.smokeTest());
  expect(smoke.ok, JSON.stringify(smoke.results.filter(r => !r.pass), null, 2)).toBeTruthy();
});
