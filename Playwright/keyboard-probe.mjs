// Drives keyboard/basic in headless Chromium through the accessibility overlay: arrow keys
// select list rows once the listbox has focus, a focusable view takes onKeyPress and
// onMoveCommand, ⌘S / Return / Escape trigger the shortcut buttons, Escape closes a sheet, and
// arrows plus Return pick a menu item.
//   node keyboard-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('keyboard/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const settle = async () => { await page.waitForTimeout(150); };
const log = async () => (await texts()).find(t => t.startsWith('Log:'));
const selected = async () => (await texts()).find(t => t.startsWith('Selected:'));
const key = async (k) => { await page.keyboard.press(k); await settle(); };
let ok = true;
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
await page.locator('[role="listbox"]').first().focus(); await settle();
await key('ArrowDown');
check('ArrowDown selects the first row of the focused list', (await selected()) === 'Selected: 1');
await key('ArrowDown'); await key('ArrowDown'); await key('ArrowDown');
check('ArrowDown stops at the last row', (await selected()) === 'Selected: 3');
await key('Home');
check('Home selects the first row', (await selected()) === 'Selected: 1');
await page.locator('[aria-label="Focus me"]').first().focus(); await settle();
await key('ArrowUp');
check('onKeyPress handles ArrowUp on the focused view', (await log()) === 'Log: up');
await key('ArrowRight');
check('onMoveCommand takes the arrow onKeyPress ignores', (await log()) === 'Log: move right');
await key('Meta+s');
check('⌘S runs the shortcut button', (await log()) === 'Log: save');
await key('Enter');
check('Return runs the default action', (await log()) === 'Log: go');
await key('Escape');
check('Escape runs the cancel action', (await log()) === 'Log: cancel');
await key('Meta+s');
const sheet = await page.locator('button[aria-label="Sheet"]').first().boundingBox();
await page.mouse.click(sheet.x + sheet.width / 2, sheet.y + sheet.height / 2); await settle();
check('the sheet presents', (await texts()).includes('Sheet content'));
await key('Escape');
check('Escape closes the sheet instead of running the cancel action', !(await texts()).includes('Sheet content') && (await log()) === 'Log: save');
await page.locator('button[aria-label="Options"]').first().focus(); await settle();
await key('Space');
check('Space opens the focused menu', (await texts()).includes('Copy'));
await key('ArrowDown'); await key('ArrowDown'); await key('Enter');
check('arrows and Return pick the second item', (await log()) === 'Log: copy' && !(await texts()).includes('Cut'));
await browser.close();
process.exit(ok ? 0 : 1);
