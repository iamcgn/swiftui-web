// Paint time, Canvas2D against WebGL, on a page whose index.html loads painter-gl.js (inject.sh
// with no mode). Two measures:
//   bench   the page's last frame repainted 30 times by each painter, waiting for the pixels
//           each time: the same content both ways, nothing else in the time.
//   scroll  a wheel burst over the page, each painter in turn (?webgl=2d, ?webgl=overlay, both
//           with ?webglSync): every frame's paint phase and its whole frame time.
//   node perf.mjs <url> [--label name] [--json out.json] [--no-scroll] [--click "text"]...
import { chromium } from 'playwright';
import { writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--') && !args[args.indexOf(a) - 1]?.startsWith('--'));
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const label = opt('--label', url), jsonPath = opt('--json', null);
const clicks = args.flatMap((a, i) => a === '--click' ? [args[i + 1]] : []);
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
const browser = await chromium.launch({ args: (process.env.WEBGL_CHROME_ARGS || '').split(' ').filter(Boolean) });
const stat = xs => { const s = xs.slice().sort((a, b) => a - b); return s.length ? { median: s[Math.floor(s.length / 2)], p90: s[Math.floor(s.length * 0.9)], max: s[s.length - 1], n: s.length } : null; };
const f = v => v == null ? '-' : v.toFixed(2);
const result = { label, url };

async function open(mode) {
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  page.on('pageerror', e => errors.push(String(e)));
  await page.goto(withQuery(url, `webgl=${mode}&webglSync`), { waitUntil: 'commit' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(1500);
  for (const text of clicks) {
    try { await page.getByText(text, { exact: false }).first().click({ timeout: 5000 }); } catch { await clickCanvasText(page, text); }
    await page.waitForTimeout(1200);
  }
  return { page, errors };
}
// The app draws on a canvas: a label is found through the semantics tree when it is not DOM text.
async function clickCanvasText(page, text) {
  const box = await page.evaluate(t => {
    const s = window.__swiftuiwebDebug.semantics && window.__swiftuiwebDebug.semantics();
    const all = []; const walk = n => { if (!n) return; all.push(n); (n.children || []).forEach(walk); };
    (Array.isArray(s) ? s : [s]).forEach(walk);
    const hit = all.find(n => n && typeof n.label === 'string' && n.label.includes(t) && n.frame);
    return hit ? hit.frame : null;
  }, text);
  if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
}

{
  const { page, errors } = await open('overlay');
  result.info = await page.evaluate(() => { const i = window.__swiftuiwebGL; return i && { active: i.active, reason: i.reason, renderer: i.renderer, samples: i.samples, fallbacks: i.fallbacks, errors: i.errors.slice(0, 3) }; });
  result.bench = await page.evaluate(() => window.__swiftuiwebGL && window.__swiftuiwebGL.bench(30));
  result.benchErrors = errors.slice(0, 5);
  await page.close();
}
if (!args.includes('--no-scroll')) {
  result.scroll = {};
  for (const mode of ['2d', 'overlay']) {
    const { page, errors } = await open(mode);
    await page.evaluate(() => {
      const d = window.__swiftuiwebDebug; window.__perfFrames = [];
      let seen = d.frameCount();
      const tick = () => { const c = d.frameCount(); if (c !== seen) { seen = c; const p = d.framePhases(); window.__perfFrames.push({ paint: p.paint, frame: d.frameMillis(), ops: p.ops }); } requestAnimationFrame(tick); };
      requestAnimationFrame(tick);
    });
    await page.mouse.move(640, 500);
    for (let i = 0; i < 40; i++) { await page.mouse.wheel(0, i < 20 ? 100 : -100); await page.waitForTimeout(40); }
    await page.waitForTimeout(600);
    const frames = await page.evaluate(() => window.__perfFrames);
    const gl = await page.evaluate(() => { const i = window.__swiftuiwebGL; return i && { glFrames: i.glFrames, fallbacks: i.fallbacks }; });
    result.scroll[mode] = { frames: frames.length, paint: stat(frames.map(x => x.paint)), frame: stat(frames.map(x => x.frame)), ops: stat(frames.map(x => x.ops)), gl, errors: errors.slice(0, 5) };
    await page.close();
  }
}
await browser.close();
const b = result.bench;
console.log(`== ${label}`);
if (result.info) console.log(`   webgl: ${result.info.active ? 'active' : 'inactive ' + result.info.reason} renderer=${result.info.renderer} samples=${result.info.samples} fallbacks=${result.info.fallbacks}${result.info.errors.length ? ' errors=' + JSON.stringify(result.info.errors) : ''}`);
if (b) console.log(`   bench (same frame x${b.canvas2d.n}, ${b.ops} op values): canvas2d median ${f(b.canvas2d.median)} ms p90 ${f(b.canvas2d.p90)} | webgl median ${f(b.webgl?.median)} ms p90 ${f(b.webgl?.p90)} | draws ${b.stats?.draws} stencil paths ${b.stats?.stencilPaths} groups ${b.stats?.groups} texts ${b.stats?.texts}`);
else console.log('   bench: no frame recorded');
for (const [mode, s] of Object.entries(result.scroll || {})) console.log(`   scroll ${mode.padEnd(7)}: ${s.frames} frames, paint median ${f(s.paint?.median)} p90 ${f(s.paint?.p90)} ms, whole frame median ${f(s.frame?.median)} p90 ${f(s.frame?.p90)} ms${s.gl ? `, gl frames ${s.gl.glFrames} fallbacks ${s.gl.fallbacks}` : ''}${s.errors.length ? ' errors ' + JSON.stringify(s.errors) : ''}`);
if (result.benchErrors?.length) console.log('   console errors: ' + JSON.stringify(result.benchErrors));
if (jsonPath) writeFileSync(jsonPath, JSON.stringify(result, null, 2));
