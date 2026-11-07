// Drives presentation/basic in headless Chromium through the accessibility overlay: the buttons
// present a sheet (dismissed by its Done button), a popover (dismissed by a click outside) and an
// alert (dismissed by OK); the pop-up picker opens a menu and picking a row changes its title.
//   node presentation-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('presentation/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const settle = async () => { await page.waitForTimeout(150); };
const press = async (label) => {
  const box = await page.locator(`button[aria-label="${label}"]`).first().boundingBox();
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await settle();
};
let ok = true;
const report = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
await press('Sheet');
await check('sheet presents', async () => (await texts()).includes('Sheet content'));
await press('Done');
await check('sheet dismisses through the environment', async () => !(await texts()).includes('Sheet content'));
await press('Popover');
await check('popover presents', async () => (await texts()).includes('Popover content'));
const canvas = await page.locator('canvas').first().boundingBox();
await page.mouse.click(canvas.x + 8, canvas.y + 8); await settle();
await check('popover dismisses on a click outside', async () => !(await texts()).includes('Popover content'));
await press('Alert');
await check('alert presents', async () => (await texts()).includes('Alert title'));
await press('OK');
await check('alert OK dismisses', async () => !(await texts()).includes('Alert title'));
await press('Fruit');
await check('pop-up picker opens its menu', async () => (await texts()).filter(t => t === 'Banana').length === 1);
await press('✓ Banana');
const after = await texts();
await check('picking Banana changes the title and closes the menu', async () => after.filter(t => t === 'Banana').length === 1 && !after.includes('✓'));
await browser.close();
process.exit(ok ? 0 : 1);
