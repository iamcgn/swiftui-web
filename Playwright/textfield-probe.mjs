// Types into a text field through the overlay's <input> and checks the runtime saw it: the
// textfield/steps fixture echoes "On" once its text is non-empty, and the field's painted text
// appears in the display list. Usage: node textfield-probe.mjs http://127.0.0.1:8766/index.html
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 900, height: 700 } });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(`${url}?fixture=${encodeURIComponent('textfield/steps')}`, { timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
// Polls until `ok` holds: a CI runner can take more than one frame to repaint (issue 201).
const until = async (ok, ms = 3000) => { const end = Date.now() + ms; let v = await ok(); while (!v && Date.now() < end) { await page.waitForTimeout(50); v = await ok(); } return v; };
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
const input = page.locator('input[type=text]');
await input.click();
await page.keyboard.type('Hi');
const typed = await until(async () => (await list()).some(c => c.includes('drawText("Hi"')));
const echoOn = await until(async () => (await list()).some(c => c.includes('drawText("On"')));
const focused = (await list()).some(c => c.startsWith('strokePath'));
const frames = await page.evaluate(() => window.__swiftuiwebDebug.frames());
await page.keyboard.press('Enter');
await page.keyboard.press('Tab');
const blurred = await until(async () => !(await list()).some(c => c.startsWith('strokePath')));
console.log(JSON.stringify({ typed, echoOn, focused, blurred, echoWidth: frames.echo && frames.echo.width, errors }));
await browser.close();
process.exit(typed && echoOn && focused && blurred && errors.length === 0 ? 0 : 1);
