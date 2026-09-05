// Scroll-performance probe for the landing page: frame times, display-list size, overlay element
// count and a CPU profile (top self-time functions) during a burst of wheel events.
// Usage: node landing-perf.mjs http://127.0.0.1:8769/
import { chromium } from 'playwright';
const [url] = process.argv.slice(2);
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
await page.goto(url);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(500);
const stats = await page.evaluate(() => ({
  ops: window.__swiftuiwebDebug.displayList().length,
  overlay: document.querySelectorAll('#app *').length,
  firstFrameMs: window.__swiftuiwebDebug.frameMillis(),
}));
console.log('at rest:', JSON.stringify(stats));
const cdp = await page.context().newCDPSession(page);
await cdp.send('Profiler.enable');
await cdp.send('Profiler.start');
const frames0 = await page.evaluate(() => window.__swiftuiwebDebug.frameCount());
const t0 = Date.now();
const times = [], phases = [];
for (let i = 0; i < 24; i++) {
  await page.mouse.move(640, 450);
  await page.mouse.wheel(0, i < 12 ? 120 : -120);
  await page.waitForTimeout(50);
  times.push(await page.evaluate(() => window.__swiftuiwebDebug.frameMillis()));
  phases.push(await page.evaluate(() => window.__swiftuiwebDebug.framePhases ? window.__swiftuiwebDebug.framePhases() : null));
}
const wall = Date.now() - t0;
const frames1 = await page.evaluate(() => window.__swiftuiwebDebug.frameCount());
const { profile } = await cdp.send('Profiler.stop');
console.log(`scroll burst: ${frames1 - frames0} frames in ${wall} ms; frameMillis samples (layout+paint per frame):`, times.map(t => t.toFixed(0)).join(' '));
if (phases[0]) {
  const mean = (key) => (phases.reduce((sum, p) => sum + p[key], 0) / phases.length).toFixed(2);
  console.log(`mean per frame: total ${(times.reduce((a, b) => a + b, 0) / times.length).toFixed(2)} ms; layout ${mean('layout')}, render ${mean('render')}, paint ${mean('paint')}, semantics ${mean('semantics')}, overlay ${mean('overlay')}`);
}
// Self time per function from the profile.
const self = new Map();
const byId = new Map(profile.nodes.map(n => [n.id, n]));
const dt = profile.timeDeltas; let total = 0;
for (let i = 0; i < profile.samples.length; i++) {
  const n = byId.get(profile.samples[i]); const d = dt[i] || 0; total += d;
  const key = `${n.callFrame.functionName || '(anon)'} ${n.callFrame.url.split('/').pop()}:${n.callFrame.lineNumber}`;
  self.set(key, (self.get(key) || 0) + d);
}
const top = [...self.entries()].sort((a, b) => b[1] - a[1]).slice(0, 25);
console.log(`profile total ${(total / 1000).toFixed(0)} ms; top self time:`);
for (const [k, v] of top) console.log(`  ${(v / 1000).toFixed(1).padStart(7)} ms  ${(100 * v / total).toFixed(1).padStart(5)}%  ${k}`);
await browser.close();
