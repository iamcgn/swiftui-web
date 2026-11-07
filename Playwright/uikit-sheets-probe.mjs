// UIKit system sheets probe (uk-system-sheets), on uikit/sheets/pickers served from
// Examples/Gallery on 8767: "Share" calls Web Share with the items (stubbed here, and absent
// makes the sheet complete uncompleted), "Open document" opens the browser's file input whose
// chosen file reaches the document picker's delegate, "Choose photo" opens an image/* input
// whose picture reaches the image picker's delegate with its size.
//   node uikit-sheets-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
const page = await context.newPage();
page.on('pageerror', e => console.error('page error', e));
await page.addInitScript(() => {
  window.__shares = [];
  navigator.share = (data) => { window.__shares.push({ text: data.text, url: data.url, title: data.title }); return Promise.resolve(); };
  navigator.canShare = () => true;
});
await page.goto(`${url}?fixture=${encodeURIComponent('uikit/sheets/pickers')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
await page.waitForFunction(() => window.__galleryFrames !== undefined, null, { timeout: 60000 });
let failures = 0;
const report = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
const frames = await page.evaluate(() => window.__galleryFrames);
const canvas = await page.locator('canvas').first().boundingBox();
const centre = (f) => ({ x: canvas.x + f.x + f.width / 2, y: canvas.y + f.y + f.height / 2 });
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
const status = async () => (await list()).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10))).find(t => /^(Nothing|Shared|Share |Picked|Cancelled|Image|No image)/.test(t));
const tap = async (f) => { const p = centre(f); await page.mouse.click(p.x, p.y); await page.waitForTimeout(150); };

await check('the status starts empty', async () => (await status()) === 'Nothing yet');
// 1. Share through Web Share.
await tap(frames.share);
const shares = await page.evaluate(() => window.__shares);
await check('Web Share was called with the text and the link', async () => shares.length === 1 && shares[0].text === 'Shared text' && shares[0].url === 'https://example.com');
await check('the sheet completed', async () => (await status()) === 'Shared');
// 2. The document picker through the file input.
await tap(frames.document);
const input = page.locator('input[type=file]');
await check('a file input accepts the picker\'s extensions', async () => (await input.getAttribute('accept')) === '.txt,.json');
await input.setInputFiles({ name: 'notes.txt', mimeType: 'text/plain', buffer: Buffer.from('hello') });
await page.waitForTimeout(300);
await check('the picked document reaches the delegate', async () => (await status()) === 'Picked UIKitWeb-notes.txt');
// 3. The image picker through an image/* input.
await tap(frames.photo);
await check('the image picker asks for images', async () => (await input.getAttribute('accept')) === 'image/*');
const png = Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0x0D, 0x49, 0x48, 0x44, 0x52, 0, 0, 0, 3, 0, 0, 0, 2, 8, 6, 0, 0, 0, 0x72, 0xB6, 0x0D, 0x24, 0, 0, 0, 0, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]);
await input.setInputFiles({ name: 'photo.png', mimeType: 'image/png', buffer: png });
await page.waitForTimeout(300);
await check('the picked image reaches the delegate with its size', async () => (await status()) === 'Image 3 × 2');
await browser.close();
console.log(failures === 0 ? 'uikit sheets probe: all passed' : `uikit sheets probe: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
