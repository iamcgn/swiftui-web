// iPhone-sized check of the landing page: screenshot at 390 x 844 (DPR 3, touch) and a finger
// drag, reporting the frame-time split and the rAF gaps. The drag is the host's scripted one
// (`__swiftuiwebDebug.drag`, the same one the `?perf` HUD and device-perf.mjs use), so the
// script runs in Chromium and in WebKit alike; a bundle without it gets a CDP touch drag.
// Usage: node landing-mobile.mjs <url> <out-dir> [--webkit]
import { chromium, webkit, devices } from 'playwright';
import { mkdirSync } from 'node:fs';
const args = process.argv.slice(2);
const useWebKit = args.includes('--webkit');
const [url, out = '.'] = args.filter(a => !a.startsWith('--'));
mkdirSync(out, { recursive: true });
const browser = await (useWebKit ? webkit : chromium).launch();
const context = await browser.newContext({ ...devices['iPhone 14'] });
const page = await context.newPage();
const errors = []; page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load', timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/mobile-top.png` });
const stats = () => page.evaluate(() => ({ frames: window.__swiftuiwebDebug.frameCount(), frameMs: Math.round(window.__swiftuiwebDebug.frameMillis()), ops: window.__swiftuiwebDebug.displayList().length, w: innerWidth, h: innerHeight, dpr: devicePixelRatio, canvas: [document.querySelector('canvas').width, document.querySelector('canvas').height] }));
console.log(`${useWebKit ? 'webkit' : 'chromium'} at rest:`, JSON.stringify(await stats()));
// The sampler: every animation frame records the gap since the previous one and, when the
// host painted a frame in between, its split.
await page.evaluate(() => {
  const d = window.__swiftuiwebDebug;
  const s = window.__perfSampler = { gaps: [], frames: [], lastCount: d.frameCount(), lastT: null, running: true };
  const tick = t => {
    if (!s.running) return;
    if (s.lastT !== null) s.gaps.push(t - s.lastT);
    s.lastT = t;
    const count = d.frameCount();
    if (count !== s.lastCount) { s.frames.push({ ms: d.frameMillis(), ...d.framePhases() }); s.lastCount = count; }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
});
const t0 = Date.now();
const scripted = await page.evaluate(() => typeof window.__swiftuiwebDebug.drag === 'function');
if (scripted) {
  // 500 px up the middle of the screen over 400 ms, then release: momentum follows.
  await page.evaluate(() => window.__swiftuiwebDebug.drag(innerWidth / 2, innerHeight * 0.75, 0, -500, 0.4));
  await page.waitForFunction(() => !window.__swiftuiwebDebug.dragging(), null, { timeout: 10000 });
} else {
  const cdp = await context.newCDPSession(page);
  const x = 195; let y = 600;
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
  for (let i = 0; i < 12; i++) { y -= 40; await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] }); await page.waitForTimeout(16); }
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
}
await page.waitForTimeout(1500);
const sample = await page.evaluate(() => { window.__perfSampler.running = false; return window.__perfSampler; });
const stat = values => {
  if (!values.length) return '-';
  const sorted = [...values].sort((a, b) => a - b);
  const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
  return `${q(0.5).toFixed(1)}/${q(0.9).toFixed(1)}/${sorted[sorted.length - 1].toFixed(1)}`;
};
const frames = sample.frames;
console.log(`drag + momentum: ${Date.now() - t0} ms, ${frames.length} frames painted; frame ms p50/p90/max ${stat(frames.map(f => f.ms))}; >16 ms: ${frames.filter(f => f.ms > 16).length}`);
console.log('phases p50/p90/max:', ['layout', 'render', 'encode', 'paint', 'semantics', 'overlay'].filter(k => frames.some(f => f[k] !== undefined)).map(k => `${k} ${stat(frames.map(f => f[k]))}`).join('  '));
console.log(`rAF gaps p50/p90/max ${stat(sample.gaps)}; gaps over 25 ms: ${sample.gaps.filter(g => g > 25).length}/${sample.gaps.length}`);
console.log('after momentum:', JSON.stringify(await stats()), 'errors:', errors.slice(0, 3));
await page.screenshot({ path: `${out}/mobile-scrolled.png` });
await browser.close();
