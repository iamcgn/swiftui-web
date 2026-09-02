// Scrolling probe: opens a scroll fixture in the gallery, sends wheel events over the canvas,
// checks the content moved (via the debug bridge) and reports frames per wheel event plus the
// mean frame interval while scrolling; saves a screenshot mid-scroll (indicator visible).
//   node scroll-probe.mjs http://127.0.0.1:8090/index.html [--fixture scroll/long] [--browser chromium] [--out ../.build/scroll-probe]
import { chromium, webkit, firefox } from 'playwright';
import { mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const fixture = opt('--fixture', 'scroll/long');
const out = opt('--out', join(here, '..', '.build', 'scroll-probe'));
mkdirSync(out, { recursive: true });

const browser = await { chromium, webkit, firefox }[opt('--browser', 'chromium')].launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 1280, height: 900 } });
const errors = [];
page.on('pageerror', e => errors.push(e.message));
await page.goto(`${url}?fixture=${encodeURIComponent(fixture)}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
await page.waitForTimeout(100);

const canvas = page.locator('#app canvas');
const box = await canvas.boundingBox();
const frames = () => page.evaluate(() => window.__galleryFrames);
const frameCount = () => page.evaluate(() => window.__swiftuiwebDebug.frameCount());
const before = await frames();
await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);

// One real wheel event through the browser (checks the listener and preventDefault), then 60
// synthetic 40 px ticks dispatched in the page, one per animation frame, collecting the host's
// own layout + paint time per frame from the debug bridge.
await page.evaluate(() => { window.__wheelDeltas = []; document.querySelector('#app canvas').addEventListener('wheel', e => window.__wheelDeltas.push([e.deltaY, e.deltaMode])); });
await page.mouse.wheel(0, 40);
await page.waitForTimeout(50);
const afterOne = await frames();
console.log(`real wheel event(s) seen by the canvas: ${JSON.stringify(await page.evaluate(() => window.__wheelDeltas))}`);
const startFrames = await frameCount();
const millis = await page.evaluate(async () => {
  const canvas = document.querySelector('#app canvas');
  const rect = canvas.getBoundingClientRect();
  const samples = [];
  for (let i = 0; i < 60; i++) {
    canvas.dispatchEvent(new WheelEvent('wheel', { deltaY: 40, deltaMode: 0, bubbles: true, cancelable: true,
                                                   clientX: rect.left + rect.width / 2, clientY: rect.top + rect.height / 2 }));
    await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)));
    samples.push(window.__swiftuiwebDebug.frameMillis());
  }
  return samples;
});
await canvas.screenshot({ path: join(out, 'mid-scroll.png') });
const painted = (await frameCount()) - startFrames;
const after = await frames();
const sorted = [...millis].sort((a, b) => a - b);
console.log(`${fixture}: content.y ${before.content.y} -> ${afterOne.content.y} after one real wheel event, -> ${after.content.y} after 60 synthetic 40 px ticks (${painted} frames painted)`);
console.log(`layout + paint per frame: median ${sorted[30].toFixed(2)} ms, p90 ${sorted[54].toFixed(2)} ms, max ${sorted[59].toFixed(2)} ms`);

// Scroll back up past the top: must clamp at 0.
let ticks = 0;
while ((await frames()).content.y < 0 && ticks < 400) { await page.mouse.wheel(0, -40); ticks++; }
await page.mouse.wheel(0, -40);
await page.waitForTimeout(100);
const top = await frames();
console.log(`after scrolling back with ${ticks + 1} real wheel ticks: content.y ${top.content.y} (expected 0)`);
// The indicator fades: no fillRRect once the fade is over.
await page.waitForTimeout(1200);
const list = await page.evaluate(() => window.__swiftuiwebDebug.displayList());
console.log(`display list after the fade: ${list.length} commands, indicator ${list.some(c => c.startsWith('fillRRect')) ? 'still visible' : 'gone'}`);
await canvas.screenshot({ path: join(out, 'after-fade.png') });
if (errors.length) console.log('page errors:\n' + errors.join('\n'));
await browser.close();
process.exit(errors.length || afterOne.content.y >= before.content.y || after.content.y >= afterOne.content.y || top.content.y !== 0 || list.some(c => c.startsWith('fillRRect')) ? 1 : 0);
