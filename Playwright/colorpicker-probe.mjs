// Colour picker probe (sw-colorpicker): a click on the well of colorpicker/steps (served from
// Examples/Gallery on 8767) opens the browser's colour input (positioned under the well, its
// value the well's colour), `input` events feed the well while it is active (the focus-blue
// frame) and `change` closes it; Space on the focused well asks again.
//   node colorpicker-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
const page = await context.newPage();
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('colorpicker/steps')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
await page.waitForFunction(() => window.__galleryFrames !== undefined, null, { timeout: 60000 });
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
const frames = await page.evaluate(() => window.__galleryFrames);
const canvas = await page.locator('canvas').first().boundingBox();
const picker = frames.picker;
// The well is the 48 × 24 at the picker's trailing end.
const wellX = canvas.x + picker.x + picker.width - 24, wellY = canvas.y + picker.y + picker.height / 2;
const wellFill = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().find(c => c.startsWith('fillPath') && (c.includes('#4791F8') || c.includes('#000000@0.098'))));
check('the well starts grey', (await wellFill())?.includes('#000000@0.098'));
// Chromium's colour picker UI is native: the click must create the input, set it and ask to open it.
await page.mouse.click(wellX, wellY);
await page.waitForTimeout(100);
const input = page.locator('input[type=color]');
check('a click creates the colour input', await input.count() === 1);
check('the input carries the well colour (#ff383c)', (await input.inputValue()) === '#ff383c');
check('the well frame turns the focus blue', (await wellFill())?.includes('#4791F8'));
const left = await input.evaluate(e => parseFloat(e.style.left));
check('the input sits under the well', Math.abs(left - (picker.x + picker.width - 48)) < 1);
// The picker's `input` and `change` events (dispatched as the native UI would).
await input.evaluate(e => { e.value = '#0080ff'; e.dispatchEvent(new Event('input', { bubbles: true })); });
await page.waitForTimeout(100);
const swatch = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('fillPath')).map(c => c.split(' ').pop()));
check('an input event recolours the swatch (#0080FF)', (await swatch()).some(c => c.startsWith('#0080FF')));
await input.evaluate(e => { e.dispatchEvent(new Event('change', { bubbles: true })); });
await page.waitForTimeout(100);
check('change closes the chooser: the frame is grey again', (await wellFill())?.includes('#000000@0.098'));
// Space on the focused well: a click in the canvas's blank corner gives it focus, Tab reaches
// the well (the first focusable control), Space asks again.
await page.mouse.click(canvas.x + 5, canvas.y + 5);
await page.keyboard.press('Tab');
await page.waitForTimeout(50);
await page.keyboard.press('Space');
await page.waitForTimeout(100);
check('Space on the focused well activates it', (await wellFill())?.includes('#4791F8'));
await browser.close();
console.log(failures === 0 ? 'colorpicker probe: all passed' : `colorpicker probe: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
