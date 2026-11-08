// Drives menu/basic in headless Chromium through the accessibility overlay: the pull-down opens
// its menu, a row runs its action and closes it, a submenu opens beside its row, the split
// button's label part runs the primary action, and a right click opens the context menu.
//   node menu-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('menu/basic')}`, { timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const settle = async () => { await page.waitForTimeout(150); };
const box = async (label) => page.locator(`button[aria-label="${label}"]`).first().boundingBox();
const press = async (label, dx) => {
  const b = await box(label);
  await page.mouse.click(dx === undefined ? b.x + b.width / 2 : b.x + dx, b.y + b.height / 2);
  await settle();
};
let ok = true;
const report = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
const last = async () => (await texts()).find(t => t.startsWith('Last:'));
await press('Options');
await check('pull-down opens its menu', async () => (await texts()).includes('Cut') && (await texts()).includes('More'));
await press('Copy');
await check('a row runs its action and closes the menu', async () => (await last()) === 'Last: Copy 0' && !(await texts()).includes('Cut'));
await press('Options');
await press('More');
await check('a submenu opens beside its row', async () => (await texts()).includes('Paste'));
await press('Paste');
await check('a submenu item runs and closes every menu', async () => (await last()) === 'Last: Paste 0' && !(await texts()).includes('Cut'));
await press('Primary', 20);
await check('the split button label runs the primary action', async () => (await last()) === 'Last: Paste 1');
await press('Primary', 84);
await check('the split button indicator opens the menu', async () => (await texts()).filter(t => t === 'Cut').length === 1);
await press('Cut');
await check('the split menu item runs', async () => (await last()) === 'Last: Cut 1');
const canvas = await page.locator('canvas').first().boundingBox();
const context = await page.locator('[aria-label="Right-click me"]').first().boundingBox();
await page.mouse.click(context.x + 10, context.y + 8, { button: 'right' }); await settle();
await check('a right click opens the context menu', async () => (await texts()).includes('Action'));
await page.mouse.click(canvas.x + 8, canvas.y + 8); await settle();
await check('a click outside closes it', async () => !(await texts()).includes('Action'));
await page.mouse.click(context.x + 10, context.y + 8, { button: 'right' }); await settle();
await press('Action');
await check('a context menu item runs', async () => (await last()) === 'Last: Action 1');
await browser.close();
process.exit(ok ? 0 : 1);
