// Runs the in-app merge/sync suites and prints EVERY failing assertion by name.
// `pnpm sync:validate` only reports the aggregate, which is useless while iterating on
// merge logic. Usage: pnpm test:merge
const { test, expect } = require('@playwright/test');
const path = require('path');

for (const suite of ['mergeTest', 'syncTest', 'skewTest']) {
  test(`__buddy.${suite}`, async ({ page }) => {
    const pageErrors = [];
    page.on('pageerror', e => pageErrors.push(e.message));
    await page.goto('file://' + path.resolve(__dirname, '../dist/index.html'));
    await page.waitForFunction(s => !!(window.__buddy && window.__buddy[s]), suite);
    const r = await page.evaluate(s => window.__buddy[s](), suite);
    const fails = (r.results || []).filter(x => !x.pass);
    const detail = fails.map(f => `\n  ✗ ${f.name}\n    ${f.detail}`).join('')
      + (pageErrors.length ? `\n  page errors: ${pageErrors.join(' | ')}` : '');
    expect(r.ok, `${suite}: ${fails.length}/${r.total} failed${detail}`).toBeTruthy();
  });
}
