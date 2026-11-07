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
const report = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
await page.locator('[role="listbox"]').first().focus(); await settle();
await key('ArrowDown');
await check('ArrowDown selects the first row of the focused list', async () => (await selected()) === 'Selected: 1');
await key('ArrowDown'); await key('ArrowDown'); await key('ArrowDown');
await check('ArrowDown stops at the last row', async () => (await selected()) === 'Selected: 3');
await key('Home');
await check('Home selects the first row', async () => (await selected()) === 'Selected: 1');
await key('Tab');
await check('Tab moves the runtime focus to the next element, mirrored into the overlay', async () => await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('aria-label')) === 'Focus me');
await key('ArrowUp');
await check('onKeyPress handles ArrowUp on the focused view', async () => (await log()) === 'Log: up');
await key('ArrowRight');
await check('onMoveCommand takes the arrow onKeyPress ignores', async () => (await log()) === 'Log: move right');
await key('Meta+s');
await check('⌘S runs the shortcut button', async () => (await log()) === 'Log: save');
await key('Enter');
await check('Return runs the default action', async () => (await log()) === 'Log: go');
await key('Escape');
await check('Escape runs the cancel action', async () => (await log()) === 'Log: cancel');
await key('Meta+s');
const sheet = await page.locator('button[aria-label="Sheet"]').first().boundingBox();
await page.mouse.click(sheet.x + sheet.width / 2, sheet.y + sheet.height / 2); await settle();
await check('the sheet presents', async () => (await texts()).includes('Sheet content'));
await key('Escape');
await check('Escape closes the sheet instead of running the cancel action', async () => !(await texts()).includes('Sheet content') && (await log()) === 'Log: save');
await page.locator('button[aria-label="Options"]').first().focus(); await settle();
await key('Space');
await check('Space opens the focused menu', async () => (await texts()).includes('Copy'));
await key('ArrowDown'); await key('ArrowDown'); await key('Enter');
await check('arrows and Return pick the second item', async () => (await log()) === 'Log: copy' && !(await texts()).includes('Cut'));
await browser.close();
process.exit(ok ? 0 : 1);
