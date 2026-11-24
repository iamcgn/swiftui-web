// SceneKit's WebGL mesh renderer (Examples/SceneDemo), as CI's gate for it:
//   - WebGL available: the meshes are drawn by WebGL (stats.gl > 0) and the view is not blank;
//   - WebGL turned off in Chromium (--disable-3d-apis): the 2D fallback draws instead;
//   - ?mesh=cpu: today's CPU path still draws;
//   - the Globe's live texture (replaced every 0.1 s) keeps reaching the GPU.
// Every case: no page errors, and a screenshot in --out.
//   node scenekit-webgl-probe.mjs <url> [--out dir]
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
import { mkdirSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const url = args[0];
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = opt('--out', '../.build/scenekit-webgl');
mkdirSync(out, { recursive: true });
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
const report = [];
let failures = 0;

async function pickScene(page, scene) {
  if (scene === 'Spheres') return;
  const names = ['Spheres', 'Waves', 'Globe'];
  const box = await page.locator('[role="radiogroup"]').first().boundingBox().catch(() => null);
  if (box) await page.mouse.click(box.x + box.width * (names.indexOf(scene) + 0.5) / names.length, box.y + box.height / 2);
  await page.waitForTimeout(800);
}

async function run(name, { launchArgs = [], query = '', scene = 'Spheres', check }) {
  const browser = await chromium.launch({ args: launchArgs });
  const page = await browser.newPage({ viewport: { width: 1000, height: 760 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 300)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text().slice(0, 300)); });
  let result;
  try {
    await page.goto(query ? withQuery(url, query) : url, { waitUntil: 'commit' });
    await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
    await pickScene(page, scene);
    await page.waitForTimeout(1500);
    const before = await page.evaluate(() => window.__swiftuiwebMesh ? Object.assign({ active: window.__swiftuiwebMesh.active }, window.__swiftuiwebMesh.stats) : null);
    await page.waitForTimeout(3000);
    const after = await page.evaluate(() => window.__swiftuiwebMesh ? Object.assign({ active: window.__swiftuiwebMesh.active }, window.__swiftuiwebMesh.stats) : null);
    const png = await page.screenshot({ path: `${out}/${name.replace(/[^a-z0-9]+/gi, '-').toLowerCase()}.png` });
    const shot = PNG.sync.read(png);
    // The page is black: count pixels that are not.
    let lit = 0;
    for (let i = 0; i < shot.data.length; i += 4) if (shot.data[i] > 24 || shot.data[i + 1] > 24 || shot.data[i + 2] > 24) lit++;
    const share = lit / (shot.width * shot.height);
    const why = check(before, after, share);
    result = { name, ok: !why && errors.length === 0, why: why || (errors.length ? 'page errors' : ''), before, after, litShare: +share.toFixed(3), errors: errors.slice(0, 5) };
  } catch (e) {
    result = { name, ok: false, why: String(e).slice(0, 300), errors };
  }
  await browser.close();
  report.push(result);
  if (!result.ok) failures++;
  const a = result.after;
  console.log(`${result.ok ? 'PASS' : 'FAIL'} ${name}${result.why ? ': ' + result.why : ''}` +
    (a ? `  active=${a.active} gl=${a.gl} 2d=${a.fallback} tris=${a.triangles} uploads=${a.uploads} ${a.renderer}` : '') +
    (result.litShare != null ? `  lit ${(result.litShare * 100).toFixed(1)}%` : '') +
    (result.errors && result.errors.length ? '  errors ' + JSON.stringify(result.errors.slice(0, 3)) : ''));
}

const drawn = share => share > 0.05 ? '' : `view looks blank (${(share * 100).toFixed(1)}% lit)`;
await run('WebGL draws the meshes', {
  check: (b, a, s) => !a ? 'no mesh renderer on the page' : !a.active ? 'WebGL not active' : a.gl <= b.gl ? 'no WebGL frames' : a.triangles <= 0 ? 'no triangles' : drawn(s),
});
await run('WebGL turned off: the 2D fallback draws', {
  launchArgs: ['--disable-3d-apis'],
  check: (b, a, s) => !a ? 'no mesh renderer on the page' : a.active ? 'WebGL active with 3D APIs off' : a.fallback <= b.fallback ? 'no fallback frames' : drawn(s),
});
await run('?mesh=cpu: the CPU path draws', {
  query: 'mesh=cpu',
  check: (b, a, s) => a && (a.gl > 0 || a.fallback > 0) ? 'mesh renderer used with mesh=cpu' : drawn(s),
});
await run('Globe: the live texture keeps reaching the GPU', {
  scene: 'Globe',
  check: (b, a, s) => !a || !a.active ? 'WebGL not active' : a.uploads - b.uploads < 5 ? `only ${a.uploads - b.uploads} uploads in 3 s` : drawn(s),
});
writeFileSync(`${out}/report.json`, JSON.stringify(report, null, 2));
console.log(failures ? `scenekit webgl: ${failures} failure(s)` : 'scenekit webgl: all passed');
process.exit(failures ? 1 : 0);
