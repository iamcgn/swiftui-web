// Drives menu/basic in headless Chromium through the accessibility overlay: the pull-down opens
// its menu, a row runs its action and closes it, a submenu opens beside its row, the split
// button's label part runs the primary action, and a right click opens the context menu.
//   node menu-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('menu/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const settle = async () => { await page.waitForTimeout(150); };
const box = async (label) => page.locator(`button[aria-label="${label}"]`).first().boundingBox();
const press = async (label, dx) => {
  const b = await box(label);
  await page.mouse.click(dx === undefined ? b.x + b.width / 2 : b.x + dx, b.y + b.height / 2);
  await settle();
};
let ok = true;
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
const last = async () => (await texts()).find(t => t.startsWith('Last:'));
await press('Options');
check('pull-down opens its menu', (await texts()).includes('Cut') && (await texts()).includes('More'));
await press('Copy');
check('a row runs its action and closes the menu', (await last()) === 'Last: Copy 0' && !(await texts()).includes('Cut'));
await press('Options');
await press('More');
check('a submenu opens beside its row', (await texts()).includes('Paste'));
await press('Paste');
check('a submenu item runs and closes every menu', (await last()) === 'Last: Paste 0' && !(await texts()).includes('Cut'));
await press('Primary', 20);
check('the split button label runs the primary action', (await last()) === 'Last: Paste 1');
await press('Primary', 84);
check('the split button indicator opens the menu', (await texts()).filter(t => t === 'Cut').length === 1);
await press('Cut');
check('the split menu item runs', (await last()) === 'Last: Cut 1');
const canvas = await page.locator('canvas').first().boundingBox();
const context = await page.locator('[aria-label="Right-click me"]').first().boundingBox();
await page.mouse.click(context.x + 10, context.y + 8, { button: 'right' }); await settle();
check('a right click opens the context menu', (await texts()).includes('Action'));
await page.mouse.click(canvas.x + 8, canvas.y + 8); await settle();
check('a click outside closes it', !(await texts()).includes('Action'));
await page.mouse.click(context.x + 10, context.y + 8, { button: 'right' }); await settle();
await press('Action');
check('a context menu item runs', (await last()) === 'Last: Action 1');
await browser.close();
process.exit(ok ? 0 : 1);
