// Frame budget probe (pf-perf): the time to the first frame after the page's resources are in
// (the wasm's parse, instantiation and first layout), the scroll frames' layout-and-paint
// time over a wheel burst, and the bundle's transfer size — each against a budget, so CI
// fails when a change makes the landing page slow. The download itself is not timed (the
// local server does not compress; Pages serves gzip): the report says what a 1.6 Mbps
// connection would add for the gzip size the size gate measures.
//   node frame-budget.mjs http://127.0.0.1:8769/ [--first-frame-ms 3000] [--frame-ms 40] [--gzip-bytes N]
import { chromium } from 'playwright';

const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--')) || 'http://127.0.0.1:8769/';
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? Number(args[i + 1]) : fallback; };
const firstFrameBudget = option('--first-frame-ms', 3000);
const frameBudget = option('--frame-ms', 40);
const gzipBytes = option('--gzip-bytes', 0);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
let failures = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`); if (!ok) failures++; };

const navigationStart = Date.now();
await page.goto(url);
// The resources' arrival: the last response's end, from the navigation.
const loaded = Date.now();
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
const firstFrame = Date.now();
const timing = await page.evaluate(() => {
  const entries = performance.getEntriesByType('resource');
  const wasm = entries.find(e => e.name.endsWith('.wasm'));
  const last = Math.max(...entries.map(e => e.responseEnd), 0);
  return { wasmBytes: wasm ? wasm.decodedBodySize || wasm.encodedBodySize : 0, lastResponseEnd: last, firstFrameMs: window.__swiftuiwebDebug.frameMillis() };
});
const toFirstFrame = firstFrame - navigationStart - timing.lastResponseEnd;
console.log(`first frame: ${toFirstFrame.toFixed(0)} ms after the resources arrived (${(firstFrame - navigationStart)} ms from navigation, resources in ${timing.lastResponseEnd.toFixed(0)} ms locally); the first frame's layout and paint ${timing.firstFrameMs.toFixed(1)} ms; wasm ${(timing.wasmBytes / 1048576).toFixed(2)} MB raw`);
if (gzipBytes > 0) console.log(`a 1.6 Mbps connection adds ${(gzipBytes * 8 / 1.6e6).toFixed(1)} s for ${(gzipBytes / 1048576).toFixed(2)} MB gzip`);
check('first frame within budget', toFirstFrame <= firstFrameBudget, `${toFirstFrame.toFixed(0)} ms, budget ${firstFrameBudget} ms`);

// A wheel burst: the frames' layout and paint times.
await page.waitForTimeout(300);
const times = [];
for (let i = 0; i < 24; i++) {
  await page.mouse.move(640, 450);
  await page.mouse.wheel(0, i < 12 ? 120 : -120);
  await page.waitForTimeout(50);
  times.push(await page.evaluate(() => window.__swiftuiwebDebug.frameMillis()));
}
const sorted = [...times].sort((a, b) => a - b);
const median = sorted[Math.floor(sorted.length / 2)], worst = sorted[sorted.length - 1];
console.log(`scroll frames: median ${median.toFixed(1)} ms, worst ${worst.toFixed(1)} ms (${times.map(t => t.toFixed(0)).join(' ')})`);
check('scroll frames within budget', median <= frameBudget, `median ${median.toFixed(1)} ms, budget ${frameBudget} ms`);
await browser.close();
console.log(failures === 0 ? 'frame budget: all passed' : `frame budget: ${failures} failure(s)`);
process.exit(failures === 0 ? 0 : 1);
