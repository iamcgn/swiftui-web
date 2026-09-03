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
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
await press('Sheet');
check('sheet presents', (await texts()).includes('Sheet content'));
await press('Done');
check('sheet dismisses through the environment', !(await texts()).includes('Sheet content'));
await press('Popover');
check('popover presents', (await texts()).includes('Popover content'));
const canvas = await page.locator('canvas').first().boundingBox();
await page.mouse.click(canvas.x + 8, canvas.y + 8); await settle();
check('popover dismisses on a click outside', !(await texts()).includes('Popover content'));
await press('Alert');
check('alert presents', (await texts()).includes('Alert title'));
await press('OK');
check('alert OK dismisses', !(await texts()).includes('Alert title'));
await press('Fruit');
check('pop-up picker opens its menu', (await texts()).filter(t => t === 'Banana').length === 1);
await press('✓ Banana');
const after = await texts();
check('picking Banana changes the title and closes the menu', after.filter(t => t === 'Banana').length === 1 && !after.includes('✓'));
await browser.close();
process.exit(ok ? 0 : 1);
