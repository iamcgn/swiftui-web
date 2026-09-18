// Hover through a representable (ios/representable/hover, served from Examples/Gallery): the
// pointer over the hosted view turns it red through its UIHoverGestureRecognizer and sets a text
// cursor through its UIPointerInteraction; over the system button with the pointer effect the
// cursor is a hand; away from both the view is blue again and the cursor default.
//   node representable-hover-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('ios/representable/hover')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const canvas = page.locator('canvas').first();
const box = await canvas.boundingBox();
const frames = await page.evaluate(() => window.__galleryFrames);
const host = frames.box;   // 200 × 120: the hover view in its top half, the button below
let failures = 0;
const check = (name, ok, detail) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) { failures++; if (detail) console.log('  ' + detail); } };
const shots = mkdtempSync(join(tmpdir(), 'hover-probe-'));
const sample = async (name, x, y) => {
  const path = join(shots, name + '.png');
  await canvas.screenshot({ path });
  const png = PNG.sync.read(readFileSync(path));
  const px = Math.round(x * png.width / box.width), py = Math.round(y * png.height / box.height);
  const i = (py * png.width + px) * 4;
  return [png.data[i], png.data[i + 1], png.data[i + 2]];
};
const near = (c, r, g, b) => Math.abs(c[0] - r) < 12 && Math.abs(c[1] - g) < 12 && Math.abs(c[2] - b) < 12;
const cursor = () => page.evaluate(() => getComputedStyle(document.querySelector('canvas')).cursor);
const viewPoint = { x: host.x + 100, y: host.y + 30 };
const buttonPoint = { x: host.x + 100, y: host.y + 90 };

check('the view is blue at rest', near(await sample('rest', viewPoint.x, viewPoint.y), 0, 136, 255));
await page.mouse.move(box.x + viewPoint.x, box.y + viewPoint.y);
await page.waitForTimeout(150);
check('hovering the view turns it red', near(await sample('over', viewPoint.x, viewPoint.y), 255, 56, 60));
check('the pointer interaction sets a text cursor', (await cursor()) === 'text', `cursor: ${await cursor()}`);
await page.mouse.move(box.x + buttonPoint.x, box.y + buttonPoint.y);
await page.waitForTimeout(150);
check('leaving the view turns it blue again', near(await sample('button', viewPoint.x, viewPoint.y), 0, 136, 255));
check("the button's pointer effect shows a hand", (await cursor()) === 'pointer', `cursor: ${await cursor()}`);
await page.mouse.move(box.x + 10, box.y + 10);
await page.waitForTimeout(150);
check('away from both the cursor is the default', ['default', 'auto', ''].includes(await cursor()), `cursor: ${await cursor()}`);
await browser.close();
console.log(failures === 0 ? 'representable hover probe: all passed' : `representable hover probe: ${failures} failed`);
