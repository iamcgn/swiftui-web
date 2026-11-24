// The WebGL painter (decision 0026) on Examples/Counter, as CI's gate for it:
//   - auto (the default) on a machine with only software WebGL leaves every frame to Canvas2D;
//   - ?webgl=overlay forces WebGL: it paints, and its frame matches Canvas2D's (Tier B's test:
//     under 3% of pixels differing by more than 32 in a channel);
//   - auto switches to WebGL when Canvas2D is slow (switch threshold 0 ms, software allowed);
//   - WebGL turned off in Chromium (--disable-3d-apis) and ?webgl=off paint with Canvas2D.
// Each case clicks "+" so the page paints after the painter has loaded, and checks for no page
// errors and a painted page. CI's Mac VMs have no GPU, and Chromium gives no WebGL at all there
// unless SwiftShader is allowed, so every case but the 3D-off one launches with it.
//   node webgl-painter-probe.mjs <url> [--out dir]
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { mkdirSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const url = args[0];
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = opt('--out', '../.build/webgl-painter');
mkdirSync(out, { recursive: true });
const SOFTWARE_GL = ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'];
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
const report = [];
let failures = 0;

async function open(name, { launchArgs = SOFTWARE_GL, query = '' }) {
  const browser = await chromium.launch({ args: launchArgs });
  const page = await browser.newPage({ viewport: { width: 600, height: 400 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 300)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text().slice(0, 300)); });
  await page.goto(query ? withQuery(url, query) : url, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  // The host installs the painter when the browser has WebGL2: wait for it (or its absence).
  await page.waitForFunction(() => window.__swiftuiwebGL !== undefined || !window.WebGL2RenderingContext, null, { timeout: 30000 }).catch(() => {});
  const plus = page.locator('button[aria-label="+"]');
  for (let k = 0; k < 4; k++) {
    const box = await plus.boundingBox();
    if (box) await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
    await page.waitForTimeout(250);
  }
  await page.waitForTimeout(500);
  const info = await page.evaluate(() => { const i = window.__swiftuiwebGL; return i ? { mode: i.mode, active: i.active, reason: i.reason, renderer: i.renderer, frames: i.frames, glFrames: i.glFrames, switches: i.switches, using: i.using, fallbacks: i.fallbacks, errors: i.errors.slice(0, 3) } : null; });
  const png = await page.screenshot({ path: `${out}/${name}.png` });
  await browser.close();
  return { info, shot: PNG.sync.read(png), errors };
}

function painted(shot) {
  let n = 0;
  for (let i = 0; i < shot.data.length; i += 4) if (shot.data[i] < 250 || shot.data[i + 1] < 250 || shot.data[i + 2] < 250) n++;
  return n / (shot.width * shot.height);
}
function differing(a, b) {
  if (a.width !== b.width || a.height !== b.height) return 1;
  let n = 0;
  for (let i = 0; i < a.data.length; i += 4) {
    let m = 0;
    for (let c = 0; c < 4; c++) m = Math.max(m, Math.abs(a.data[i + c] - b.data[i + c]));
    if (m > 32) n++;
  }
  return n / (a.width * a.height);
}
function record(name, r, why) {
  const share = painted(r.shot);
  if (!why && share < 0.001) why = `page looks blank (${(share * 100).toFixed(2)}% painted)`;
  if (!why && r.errors.length) why = 'page errors';
  report.push({ name, ok: !why, why: why || '', info: r.info, painted: +share.toFixed(4), errors: r.errors.slice(0, 5) });
  if (why) failures++;
  console.log(`${why ? 'FAIL' : 'PASS'} ${name}${why ? ': ' + why : ''}  ${JSON.stringify(r.info)}  ${(share * 100).toFixed(1)}% painted${r.errors.length ? '  errors ' + JSON.stringify(r.errors.slice(0, 3)) : ''}`);
}

const base = await open('canvas2d', { query: 'webgl=off' });
record('?webgl=off: Canvas2D only', base, !base.info ? 'painter not loaded' : base.info.glFrames > 0 ? 'WebGL painted with webgl=off' : '');

const auto = await open('auto', {});
record('auto: no WebGL frames with software WebGL only', auto,
  !auto.info ? 'painter not loaded' :
  auto.info.active ? (/swiftshader|llvmpipe|software/i.test(auto.info.renderer) ? `software renderer taken: ${auto.info.renderer}` : '') :
  auto.info.glFrames > 0 ? 'WebGL frames while inactive' : '');

const forced = await open('webgl', { query: 'webgl=overlay' });
const diff = differing(base.shot, forced.shot);
record('?webgl=overlay: WebGL paints, matching Canvas2D', forced,
  !forced.info ? 'painter not loaded' : !forced.info.active ? `WebGL not active (${forced.info.reason})` :
  forced.info.glFrames === 0 ? 'no WebGL frames' : forced.info.fallbacks > 0 ? `${forced.info.fallbacks} frames fell back` :
  diff > 0.03 ? `${(diff * 100).toFixed(2)}% of pixels differ from Canvas2D` : '');
console.log(`   WebGL against Canvas2D: ${(diff * 100).toFixed(3)}% of pixels differ by more than 32`);

const switching = await open('auto-switch', { query: 'webglSoftware&webglSwitchMs=0' });
record('auto: a slow frame goes to WebGL (threshold 0 ms)', switching,
  !switching.info ? 'painter not loaded' : !switching.info.active ? `WebGL not active (${switching.info.reason})` :
  switching.info.switches < 1 || switching.info.glFrames === 0 ? 'auto never switched to WebGL' : '');

const off = await open('no-3d', { launchArgs: ['--disable-3d-apis'] });
record('WebGL turned off in Chromium: Canvas2D paints', off,
  off.info && (off.info.active || off.info.glFrames > 0) ? 'WebGL used with 3D APIs off' : '');

writeFileSync(`${out}/report.json`, JSON.stringify({ webglVsCanvas2d: diff, cases: report }, null, 2));
console.log(failures ? `webgl painter: ${failures} failure(s)` : 'webgl painter: all passed');
process.exit(failures ? 1 : 0);
