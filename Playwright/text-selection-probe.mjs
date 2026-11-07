// Text selection probe (sw-text-selection): drags over the selectable text of
// textscale/selection (served from Examples/Gallery on 8767), checks the highlight in the display
// list, ⌘C writing the selection to the clipboard, and a press elsewhere clearing it.
//   node text-selection-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2, permissions: ['clipboard-read', 'clipboard-write'] });
const page = await context.newPage();
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('textscale/selection')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
let failures = 0;
const report = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
// The selection highlight: the text field's selection colour (the gallery paints a white ground first).
const highlights = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('fillRect') && c.endsWith('#B3D7FF')));
const frames = () => page.evaluate(() => window.__galleryFrames);
await page.waitForFunction(() => window.__galleryFrames !== undefined, null, { timeout: 60000 });
const all = await frames();
const canvas = await page.locator('canvas').first().boundingBox();
const f = all.enabled, g = all.disabled;
const y = canvas.y + f.y + f.height / 2;
// Drag across the middle of "Selectable text".
await page.mouse.move(canvas.x + f.x + 10, y);
await page.mouse.down();
await page.mouse.move(canvas.x + f.x + 40, y, { steps: 4 });
await page.mouse.move(canvas.x + f.x + 70, y, { steps: 4 });
await page.waitForTimeout(100);
await check('a drag paints a selection highlight', async () => (await highlights()).length === 1);
await page.mouse.up();
await page.waitForTimeout(50);
await check('the highlight stays after the release', async () => (await highlights()).length === 1);
await page.keyboard.press('Meta+c');
await page.waitForTimeout(100);
const copied = await page.evaluate(() => navigator.clipboard.readText()).catch(() => '');
await check('⌘C copies the selected characters', async () => copied.length > 0 && 'Selectable text'.includes(copied));
// A press on the plain text clears it, and the plain text takes no selection.
await page.mouse.move(canvas.x + g.x + 10, canvas.y + g.y + g.height / 2);
await page.mouse.down();
await page.mouse.move(canvas.x + g.x + 60, canvas.y + g.y + g.height / 2, { steps: 4 });
await page.mouse.up();
await page.waitForTimeout(100);
await check('a press elsewhere clears the selection; disabled text selects nothing', async () => (await highlights()).length === 0);
await browser.close();
console.log(failures === 0 ? 'text selection probe: all passed' : `text selection probe: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
