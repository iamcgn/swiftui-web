// Ember's frames, screen by screen (pf-perf, Docs/elements/Performance.md "A real app's frames"):
// every frame's phases, recorded in the page as frameCount() advances, with the reason the
// runtime laid out and the pass's measurements — the onboarding, the feed loading, a scroll of
// the feed, the top story's discussion, two scrolls of the thread. The app must be built in
// release (scripts/build-wasm.sh Apps --product Ember) and served; the drags are the host's
// scripted finger (x, y, dx, dy, seconds). Against the live API, so the story and its thread
// differ run to run; the shape of the numbers is what to compare. ENGINE=webkit runs Playwright's
// WebKit (the phone's engine: no canvas `filter`, so the painter's own blur) instead of Chrome.
//   node ember-perf.mjs http://127.0.0.1:8780/index.html?platform=ios [screenshot.png]
import { chromium, webkit } from 'playwright';
const url = process.argv[2];
const browser = process.env.ENGINE === 'webkit' ? await webkit.launch({ headless: true }) : await chromium.launch({ channel: 'chrome', chromiumSandbox: true, headless: true });
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true, deviceScaleFactor: 2 });
const page = await context.newPage();
await page.goto(url, { waitUntil: 'commit' });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
await page.evaluate(() => {
  window.__frames = []; let last = window.__swiftuiwebDebug.frameCount();
  const tick = () => { const n = window.__swiftuiwebDebug.frameCount(); if (n !== last) { last = n; const p = window.__swiftuiwebDebug.framePhases(); window.__frames.push({ n, t: performance.now(), ...p, total: window.__swiftuiwebDebug.frameMillis() }); } requestAnimationFrame(tick); };
  requestAnimationFrame(tick);
});
const drawn = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => { const m = c.match(/^drawText\("([^"]*)" (\S+) [\d.]+ w\d+ at ([-\d.]+),([-\d.]+)/); return m ? { text: m[1], x: +m[3], y: +m[4] } : { text: (c.match(/"([^"]*)"/) || [])[1] || '', x: 0, y: 0 }; }));
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 120) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const tapText = async (text, dx = 10, dy = -6) => { const hit = (await drawn()).find(d => d.text === text); if (!hit) throw new Error('no text ' + text); await page.touchscreen.tap(hit.x + dx, hit.y + dy); };
const take = async (label) => { const f = await page.evaluate(() => { const f = window.__frames; window.__frames = []; return f; }); const sum = (k) => f.reduce((a, x) => a + x[k], 0); const worst = [...f].sort((a, b) => b.total - a.total).slice(0, 5); console.log(`\n== ${label}: ${f.length} frames, layout ${sum('layout').toFixed(0)} ms, render ${sum('render').toFixed(0)} ms, encode ${sum('encode').toFixed(0)}, paint ${sum('paint').toFixed(0)}, semantics ${sum('semantics').toFixed(0)}, overlay ${sum('overlay').toFixed(0)} ms`); for (const w of worst) console.log(`   frame ${w.n}: total ${w.total.toFixed(0)} ms (layout ${w.layout.toFixed(0)}, render ${w.render.toFixed(0)}, encode ${w.encode.toFixed(0)}, paint ${w.paint.toFixed(0)}, semantics ${w.semantics.toFixed(0)}, overlay ${w.overlay.toFixed(0)}, ops ${w.ops}) ${w.reason} measures ${w.measures} computes ${w.computes}`); const reasons = {}; for (const x of f) reasons[x.reason] = (reasons[x.reason] || 0) + 1; console.log('   reasons:', JSON.stringify(reasons)); return f; };
const scrollStats = (f) => { const t = f.map(x => x.total).sort((a, b) => a - b); const q = (p) => t[Math.min(t.length - 1, Math.floor(p * t.length))]; console.log(`   scroll frames: ${t.length}, median ${q(0.5).toFixed(1)} ms, p90 ${q(0.9).toFixed(1)}, max ${t[t.length - 1].toFixed(1)}`); };
const rows = (t) => { const ranks = []; for (let i = 0; i < t.length; i++) if (/^\d+$/.test(t[i]) && +t[i] >= 1 && +t[i] <= 30 && (ranks.length === 0 || +t[i] === ranks[ranks.length - 1].rank + 1)) ranks.push({ rank: +t[i], index: i }); return ranks; };

await settle(t => t.includes('Welcome to Ember'));
await take('launch (onboarding cover)');
for (let i = 0; i < 10; i++) { const t = await texts(); const b = t.includes('Start Reading') ? 'Start Reading' : t.includes('Continue') ? 'Continue' : null; if (!b) break; await tapText(b); await page.waitForTimeout(500); if (b === 'Start Reading') break; }
let shown = await settle(t => rows(t).length >= 5, 200);
await take('onboarding taps + feed load');
const feedRows = rows(shown);
const title = shown.slice(feedRows[0].index + 1, feedRows[1].index).find(s => s.length > 8);
await page.waitForTimeout(1500); await take('feed idle 1.5 s');
await page.evaluate(() => window.__swiftuiwebDebug.drag(195, 700, 0, -400, 0.6));
await page.waitForFunction(() => !window.__swiftuiwebDebug.dragging(), null, { timeout: 30000 }); await page.waitForTimeout(1200);
scrollStats(await take('feed scroll (400 px drag, 0.6 s)'));
await page.evaluate(() => window.__swiftuiwebDebug.drag(195, 300, 0, 400, 0.6));
await page.waitForFunction(() => !window.__swiftuiwebDebug.dragging(), null, { timeout: 30000 }); await page.waitForTimeout(1200);
await take('feed scroll back');
await tapText(title, 40, 4);
shown = await settle(t => !t.includes('Top') && t.length > 12, 200);
await page.waitForTimeout(6000);
const f = await take('open discussion (+6 s idle)');
const t = await texts(); console.log('   texts on screen:', t.length, '| sample:', JSON.stringify(t.slice(0, 6)));
await page.evaluate(() => window.__swiftuiwebDebug.drag(195, 700, 0, -500, 0.6));
await page.waitForFunction(() => !window.__swiftuiwebDebug.dragging(), null, { timeout: 60000 }); await page.waitForTimeout(3000);
scrollStats(await take('thread scroll (500 px drag)'));
await page.evaluate(() => window.__swiftuiwebDebug.drag(195, 700, 0, -500, 0.6));
await page.waitForFunction(() => !window.__swiftuiwebDebug.dragging(), null, { timeout: 60000 }); await page.waitForTimeout(3000);
scrollStats(await take('thread scroll again'));
if (process.argv[3]) await page.screenshot({ path: process.argv[3] });
await browser.close();
