// focus/basic in headless Chromium: clicking a field focuses it (the status text follows the
// @FocusState), the button moves focus programmatically (the host focuses the input), Tab moves
// to the next field, and blurring clears the state.
//   node focus-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('focus/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const status = async () => (await texts()).find(t => t.startsWith('Focused: '));
const settle = async () => { await page.waitForTimeout(150); };
let ok = true;
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
check('starts unfocused', (await status()) === 'Focused: none');
const nameInput = page.locator('input[aria-label="Name"]').first();
await nameInput.click(); await settle();
check('clicking the name field focuses it', (await status()) === 'Focused: name');
await page.keyboard.press('Tab'); await settle();
check('Tab moves focus to the email field', (await status()) === 'Focused: email');
const active = await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('aria-label'));
check('the browser focus is on the email input', active === 'Email');
await page.evaluate(() => document.activeElement && document.activeElement.blur()); await settle();
check('blurring clears the focus state', (await status()) === 'Focused: none');
const button = await page.locator('button[aria-label="Focus email"]').first().boundingBox();
await page.mouse.click(button.x + button.width / 2, button.y + button.height / 2); await settle();
check('the button focuses the email field programmatically', (await status()) === 'Focused: email');
const active2 = await page.evaluate(() => document.activeElement && document.activeElement.getAttribute('aria-label'));
check('and the host moved the browser focus with it', active2 === 'Email');
await browser.close();
process.exit(ok ? 0 : 1);
