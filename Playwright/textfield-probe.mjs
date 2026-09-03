// Types into a text field through the overlay's <input> and checks the runtime saw it: the
// textfield/steps fixture echoes "On" once its text is non-empty, and the field's painted text
// appears in the display list. Usage: node textfield-probe.mjs http://127.0.0.1:8766/index.html
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 900, height: 700 } });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(`${url}?fixture=${encodeURIComponent('textfield/steps')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const input = page.locator('input[type=text]');
await input.click();
await page.keyboard.type('Hi');
await page.waitForTimeout(100);
const list = await page.evaluate(() => window.__swiftuiwebDebug.displayList());
const frames = await page.evaluate(() => window.__swiftuiwebDebug.frames());
const typed = list.some(c => c.includes('drawText("Hi"'));
const echoOn = list.some(c => c.includes('drawText("On"'));
const focused = list.some(c => c.startsWith('strokePath'));
await page.keyboard.press('Enter');
await page.keyboard.press('Tab');
await page.waitForTimeout(100);
const blurred = !(await page.evaluate(() => window.__swiftuiwebDebug.displayList())).some(c => c.startsWith('strokePath'));
console.log(JSON.stringify({ typed, echoOn, focused, blurred, echoWidth: frames.echo && frames.echo.width, errors }));
await browser.close();
process.exit(typed && echoOn && focused && blurred && errors.length === 0 ? 0 : 1);
