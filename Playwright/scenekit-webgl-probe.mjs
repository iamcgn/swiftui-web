// SceneKit's WebGL mesh renderer (Examples/SceneDemo), as CI's gate for it:
//   - WebGL available: the meshes are drawn by WebGL (stats.gl > 0) and the view is not blank;
//   - WebGL turned off in Chromium (--disable-3d-apis): the 2D fallback draws instead;
//   - ?mesh=cpu: today's CPU path still draws;
//   - the Globe's live texture (replaced every 0.1 s) keeps reaching the GPU;
//   - leaving the Globe for Spheres lets go of the Globe's material slots and textures once the
//     eviction window passes (shortened with ?meshEvict=60), as a replaced geometry's are (#380).
// Every case: no page errors, and a screenshot in --out.
//   node scenekit-webgl-probe.mjs <url> [--out dir]
import { chromium } from 'playwright';
import { webglLaunch } from './webgl-launch.mjs';
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

async function pickScene(page, scene, always = false) {
  if (scene === 'Spheres' && !always) return;
  const names = ['Spheres', 'Waves', 'Globe'];
  const picker = page.locator('[role="radiogroup"]').first();
  const picked = () => picker.getAttribute('aria-valuetext').catch(() => null);
  // A busy page can miss a click: click again until the picker shows the scene, a few times.
  for (let tries = 0; tries < 4; tries++) {
    const box = await picker.boundingBox().catch(() => null);
    if (box) await page.mouse.click(box.x + box.width * (names.indexOf(scene) + 0.5) / names.length, box.y + box.height / 2);
    await page.waitForTimeout(800);
    const now = await picked();
    if (now === scene || now === null) return;
  }
}

// CI's Mac VMs have no GPU of their own: launch Chromium the way webgl-launch.mjs found to give WebGL2.
const launch = await webglLaunch();
console.log(`SceneKit WebGL probe launches Chromium as: ${launch.name} (${launch.renderer})`);

async function run(name, { extraArgs = [], query = '', scene = 'Spheres', act = (page) => page.waitForTimeout(3000), check }) {
  const browser = await chromium.launch({ headless: launch.headless, args: [...launch.args, ...extraArgs] });
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
    await act(page, before);
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
    (a ? `  active=${a.active} gl=${a.gl} 2d=${a.fallback} tris=${a.triangles} uploads=${a.uploads} slots=${a.slots} textures=${a.textures} forgotten=${a.forgotten} ${a.renderer}` : '') +
    (result.litShare != null ? `  lit ${(result.litShare * 100).toFixed(1)}%` : '') +
    (result.errors && result.errors.length ? '  errors ' + JSON.stringify(result.errors.slice(0, 3)) : ''));
}

const drawn = share => share > 0.05 ? '' : `view looks blank (${(share * 100).toFixed(1)}% lit)`;
// What Spheres holds by itself: the slots and textures its own meshes draw.
let spheres = null;
await run('WebGL draws the meshes', {
  check: (b, a, s) => { spheres = a; return !a ? 'no mesh renderer on the page' : !a.active ? 'WebGL not active' : a.gl <= b.gl ? 'no WebGL frames' : a.triangles <= 0 ? 'no triangles' : drawn(s); },
});
await run('WebGL turned off: the 2D fallback draws', {
  extraArgs: ['--disable-3d-apis'],
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
// The Globe's sphere and its live texture leave with it: after 60 frames (and the check every
// 30) its slots, textures and data URLs are let go, leaving what Spheres holds by itself.
let globe = null, framesAfter = 0, switched = null;
await run('Leaving the Globe lets go of its slots and textures', {
  scene: 'Globe', query: 'meshEvict=60',
  act: async (page) => {
    // A second on the Globe is enough for its live texture to replace itself several times; much
    // longer and its per-frame texture work slows the page (tracked on its own).
    await page.waitForTimeout(1000);
    globe = await page.evaluate(() => Object.assign({}, window.__swiftuiwebMesh.stats));
    const look = () => page.evaluate(() => ({
      app: window.__swiftuiwebDebug.frameCount(), gl: window.__swiftuiwebMesh.stats.gl, fallback: window.__swiftuiwebMesh.stats.fallback,
      picked: [...document.querySelectorAll('[role="radiogroup"]')].map(e => e.getAttribute('aria-valuetext')).find(v => v !== null) ?? null,
    }));
    const was = await look();
    await pickScene(page, 'Spheres', true);
    const start = await page.evaluate(() => window.__swiftuiwebMesh.stats.gl);
    await page.waitForFunction((start) => window.__swiftuiwebMesh.stats.gl - start >= 150, start, { timeout: 60000 }).catch(() => {});
    framesAfter = (await page.evaluate(() => window.__swiftuiwebMesh.stats.gl)) - start;
    // What the page did around the switch, for a failure's detail.
    switched = { before: was, after: await look() };
  },
  check: (b, a, s) => !a || !a.active ? 'WebGL not active' : !spheres ? 'no Spheres baseline' :
    framesAfter < 150 ? `only ${framesAfter} WebGL frames after leaving the Globe (needs 150 for the eviction window); around the switch ${JSON.stringify(switched)}` :
    a.slots > spheres.slots ? `${a.slots} slots after leaving the Globe (Spheres alone holds ${spheres.slots}; the Globe held ${globe && globe.slots})` :
    a.textures > spheres.textures ? `${a.textures} textures after leaving the Globe (Spheres alone holds ${spheres.textures}; the Globe held ${globe && globe.textures})` :
    a.forgotten <= (globe ? globe.forgotten : 0) ? `no data-URL image let go after leaving the Globe (${a.forgotten} in all)` : drawn(s),
});
writeFileSync(`${out}/report.json`, JSON.stringify(report, null, 2));
console.log(failures ? `scenekit webgl: ${failures} failure(s)` : 'scenekit webgl: all passed');
process.exit(failures ? 1 : 0);
