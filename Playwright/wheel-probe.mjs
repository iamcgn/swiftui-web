// Wheel probe: wheels over a UIScrollView hosted in a representable (ios/representable/wheel,
// served from Examples/Gallery), checks that its content moved by sampling the stripe under the
// pointer, then wheels past its end and checks that the outer SwiftUI scroll view took the rest
// through the probe frames.
//   node wheel-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { readFileSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('ios/representable/wheel')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
// The gallery publishes the probe frames whenever they change (a scroll included).
const probes = () => page.evaluate(() => window.__galleryFrames);
// Chromium delivers half the requested wheel delta at a device scale factor of 2 (scroll-probe.mjs).
const wheel = (points) => page.mouse.wheel(0, points * 2);
const canvas = page.locator('canvas').first();
const box = await canvas.boundingBox();
let failures = 0;
const check = (name, ok, detail) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) { failures++; if (detail) console.log('  ' + detail); } };
const shots = mkdtempSync(join(tmpdir(), 'wheel-probe-'));
// The colour of the canvas 10 pt below the inner scroll view's top at its middle.
const sample = async (name) => {
  const path = join(shots, name + '.png');
  await canvas.screenshot({ path });
  const png = PNG.sync.read(readFileSync(path));
  const x = Math.round(160 * png.width / box.width), y = Math.round(10 * png.height / box.height);
  const i = (y * png.width + x) * 4;
  return [png.data[i], png.data[i + 1], png.data[i + 2]];
};
const near = (c, r, g, b) => Math.abs(c[0] - r) < 12 && Math.abs(c[1] - g) < 12 && Math.abs(c[2] - b) < 12;
const inner = { x: box.x + 160, y: box.y + 75 };

const rest = await sample('rest');
check('the first stripe (red) shows at rest', near(rest, 255, 56, 60), `sampled ${rest}`);
await page.mouse.move(inner.x, inner.y);
await wheel(100);
await page.waitForTimeout(150);
const after = await sample('after');
check('a 100 pt wheel over the UIKit scroll view shows its third stripe (green)', near(after, 52, 199, 89), `sampled ${after}`);
check('the outer scroll view did not move', (await probes()).row0.y === 150, JSON.stringify((await probes()).row0));
// Past the inner's end (800 − 150 = 650 of travel; 100 done): the inner takes 550 of the next
// 600 and the outer the remaining 50, in the same event.
await wheel(600);
await page.waitForTimeout(150);
// The inner box has moved up 50 with the outer, so 10 pt below the canvas top is 60 into it:
// content 710, the fifteenth stripe, green.
const end = await sample('end');
check('the inner scroll view stops at its end', near(end, 52, 199, 89), `sampled ${end}`);
const row0 = (await probes()).row0;
check('what the inner leaves chains to the outer scroll view', row0 && row0.y === 100, JSON.stringify(row0));
await browser.close();
console.log(failures === 0 ? 'wheel probe: all passed' : `wheel probe: ${failures} failed`);
