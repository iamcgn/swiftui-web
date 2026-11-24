// SceneKit's renderers side by side (Examples/SceneDemo): each scene drawn by the CPU path
// (?mesh=cpu, today), by the WebGL mesh renderer (default), and by its no-WebGL fallback
// (?mesh=2d); with --gl the page also loads painter-gl.js (the WebGL painter for everything).
// For each: frames drawn in 4 s, the time between frames (smoothness), the host's frame phases
// (render holds SCNView.draw), and a screenshot of the view.
//   node scene.mjs <url> [--out dir] [--json out.json] [--modes cpu,gl,2d] [--scenes Spheres,Waves,Globe]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const url = args[0];
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = opt('--out', '../.build/webgl-scene');
const jsonPath = opt('--json', null);
const modes = opt('--modes', 'cpu,gl,2d').split(',');
const scenes = opt('--scenes', 'Spheres,Waves,Globe').split(',');
const label = opt('--label', '');
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ args: (process.env.WEBGL_CHROME_ARGS || '').split(' ').filter(Boolean) });
const stat = xs => { const s = xs.filter(x => x != null).sort((a, b) => a - b); return s.length ? { median: +s[Math.floor(s.length / 2)].toFixed(2), p90: +s[Math.floor(s.length * 0.9)].toFixed(2), max: +s[s.length - 1].toFixed(2), n: s.length } : null; };
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
const results = [];

async function clickLabel(page, text) {
  const box = await page.evaluate(t => {
    const s = window.__swiftuiwebDebug.semantics && window.__swiftuiwebDebug.semantics();
    const all = []; const walk = n => { if (!n) return; all.push(n); (n.children || []).forEach(walk); };
    (Array.isArray(s) ? s : [s]).forEach(walk);
    const hit = all.find(n => n && typeof n.label === 'string' && n.label.trim() === t && n.frame);
    return hit ? hit.frame : null;
  }, text);
  if (box) { await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2); return true; }
  try { await page.getByText(text, { exact: true }).first().click({ timeout: 3000 }); return true; } catch { return false; }
}

for (const scene of scenes) {
  for (const mode of modes) {
    const page = await browser.newPage({ viewport: { width: 1000, height: 760 }, deviceScaleFactor: 2 });
    const errors = [];
    page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 300)); });
    page.on('pageerror', e => errors.push(String(e).slice(0, 300)));
    const q = mode === 'gl' ? '' : `mesh=${mode}`;
    await page.goto(q ? withQuery(url, q) : url, { waitUntil: 'commit' });
    await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
    await page.waitForTimeout(1000);
    let clicked = scene === 'Spheres' ? true : false;
    if (!clicked) {
      // The segmented picker is one radiogroup element: click its segment by position.
      const names = ['Spheres', 'Waves', 'Globe'];
      const box = await page.locator('[role="radiogroup"]').first().boundingBox().catch(() => null);
      if (box) { await page.mouse.click(box.x + box.width * (names.indexOf(scene) + 0.5) / names.length, box.y + box.height / 2); await page.waitForTimeout(400); }
      const sel = await page.evaluate(() => [...document.querySelectorAll('[role="radiogroup"]')].map(e => e.getAttribute('aria-valuetext')).find(v => v !== null) ?? null);
      clicked = sel === scene || (await clickLabel(page, scene));
    }
    await page.waitForTimeout(2500);
    await page.evaluate(() => {
      const d = window.__swiftuiwebDebug; window.__sceneFrames = []; window.__raf = [];
      let seen = d.frameCount(), last = performance.now();
      window.__sceneStop = false;
      const tick = (t) => {
        window.__raf.push(t - last); last = t;
        const c = d.frameCount();
        if (c !== seen) { seen = c; const p = d.framePhases(); window.__sceneFrames.push({ t, frame: d.frameMillis(), layout: p.layout, render: p.render, encode: p.encode, paint: p.paint, ops: p.ops }); }
        if (!window.__sceneStop) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
    await page.waitForTimeout(4000);
    const r = await page.evaluate(() => {
      window.__sceneStop = true;
      const f = window.__sceneFrames;
      const gaps = []; for (let k = 1; k < f.length; k++) gaps.push(f[k].t - f[k - 1].t);
      const mesh = window.__swiftuiwebMesh ? Object.assign({}, window.__swiftuiwebMesh.stats, { active: window.__swiftuiwebMesh.active }) : null;
      const gl = window.__swiftuiwebGL ? { active: window.__swiftuiwebGL.active, glFrames: window.__swiftuiwebGL.glFrames, fallbacks: window.__swiftuiwebGL.fallbacks } : null;
      return { frames: f, gaps, mesh, gl };
    });
    const res = {
      scene, mode, label, clicked,
      framesIn4s: r.frames.length,
      fps: +(r.frames.length / 4).toFixed(1),
      frameGap: stat(r.gaps), frameMs: stat(r.frames.map(x => x.frame)),
      render: stat(r.frames.map(x => x.render)), encode: stat(r.frames.map(x => x.encode)), paint: stat(r.frames.map(x => x.paint)),
      ops: stat(r.frames.map(x => x.ops)), mesh: r.mesh, gl: r.gl, errors: errors.slice(0, 5),
    };
    await page.screenshot({ path: `${out}/${scene.toLowerCase()}-${mode}${label ? '-' + label : ''}.png` });
    results.push(res);
    const s = v => v ? `${v.median}/${v.p90}` : '-';
    console.log(`${scene.padEnd(8)} ${(mode + (label ? '+' + label : '')).padEnd(8)} ${String(res.fps).padStart(5)} fps  gap med/p90 ${s(res.frameGap)} ms  frame ${s(res.frameMs)}  render ${s(res.render)}  encode ${s(res.encode)}  paint ${s(res.paint)}  ops ${res.ops?.median ?? '-'}` +
      (r.mesh ? `  mesh gl=${r.mesh.gl} 2d=${r.mesh.fallback} tris=${r.mesh.triangles} uploads=${r.mesh.uploads} ${r.mesh.renderer}` : '') + (clicked ? '' : '  (scene button not found)') + (errors.length ? '  errors ' + JSON.stringify(errors) : ''));
    await page.close();
  }
}
await browser.close();
if (jsonPath) writeFileSync(jsonPath, JSON.stringify(results, null, 2));
