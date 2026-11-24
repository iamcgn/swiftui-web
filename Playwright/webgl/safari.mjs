// SceneKit's renderers in real Safari, driven through safaridriver (WebDriver), with the same
// measurements as scene.mjs: frames in 4 s, frame gaps, frame phases, mesh stats, and a coarse
// comparison of each screenshot with the cpu one. safaridriver must be on (once, by the Mac's
// owner: Safari > Settings > Developer > Allow remote automation, or `safaridriver --enable`);
// if it isn't, this prints why and exits 0.
//   node safari.mjs <url> [--out dir] [--json out.json] [--modes cpu,gl,2d] [--scenes Spheres,Waves,Globe]
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { PNG } from 'pngjs';
const args = process.argv.slice(2);
const url = args[0];
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = opt('--out', '../.build/webgl-scene');
const jsonPath = opt('--json', null);
const modes = opt('--modes', 'cpu,gl,2d').split(',');
const scenes = opt('--scenes', 'Spheres,Waves,Globe').split(',');
mkdirSync(out, { recursive: true });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const port = 4471;
const driver = spawn('safaridriver', ['-p', String(port)], { stdio: 'inherit' });
await sleep(1500);
const base = `http://127.0.0.1:${port}`;
async function wd(method, path, body) {
  const r = await fetch(base + path, { method, headers: { 'content-type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(`${method} ${path}: ${r.status} ${JSON.stringify(j.value ?? j).slice(0, 400)}`);
  return j.value;
}
let sid;
try {
  const s = await wd('POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari' } } });
  sid = s.sessionId;
  console.log(`browser safari ${s.capabilities?.browserVersion ?? '?'}`);
} catch (e) {
  console.log('safari: no session: ' + e.message);
  driver.kill(); process.exit(0);
}
const S = p => `/session/${sid}${p}`;
const exec = (fn, ...a) => wd('POST', S('/execute/sync'), { script: `return (${fn}).apply(null, arguments)`, args: a });
const stat = xs => { const s = xs.filter(x => x != null).sort((a, b) => a - b); return s.length ? { median: +s[Math.floor(s.length / 2)].toFixed(2), p90: +s[Math.floor(s.length * 0.9)].toFixed(2), max: +s[s.length - 1].toFixed(2), n: s.length } : null; };
const grid = buf => {
  const p = PNG.sync.read(buf); const W = 40, H = 30, cells = new Float64Array(W * H * 3), n = new Float64Array(W * H);
  const bg = [p.data[0], p.data[1], p.data[2]]; let fg = 0;
  for (let y = 0; y < p.height; y += 2) for (let x = 0; x < p.width; x += 2) {
    const i = (y * p.width + x) * 4, c = Math.min(W - 1, Math.floor(x * W / p.width)) + W * Math.min(H - 1, Math.floor(y * H / p.height));
    for (let k = 0; k < 3; k++) cells[c * 3 + k] += p.data[i + k];
    n[c]++;
    if (Math.abs(p.data[i] - bg[0]) + Math.abs(p.data[i + 1] - bg[1]) + Math.abs(p.data[i + 2] - bg[2]) > 48) fg++;
  }
  for (let c = 0; c < W * H; c++) for (let k = 0; k < 3; k++) cells[c * 3 + k] /= n[c] || 1;
  return { cells, fg: fg / (p.width * p.height / 4) };
};
const compare = (a, b) => {
  let sum = 0, max = 0;
  for (let c = 0; c < a.cells.length / 3; c++) {
    const d = (Math.abs(a.cells[c * 3] - b.cells[c * 3]) + Math.abs(a.cells[c * 3 + 1] - b.cells[c * 3 + 1]) + Math.abs(a.cells[c * 3 + 2] - b.cells[c * 3 + 2])) / 3;
    sum += d; if (d > max) max = d;
  }
  return { mean: +(sum / (a.cells.length / 3)).toFixed(1), worst: +max.toFixed(0) };
};
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
const results = [], shots = {};
try {
  await wd('POST', S('/window/rect'), { width: 1000, height: 860 }).catch(() => {});
  await wd('POST', S('/url'), { url: 'about:blank' });
  console.log('renderer: ' + await exec(() => {
    const c = document.createElement('canvas'); const g = c.getContext('webgl2');
    if (!g) return 'no WebGL2';
    const e = g.getExtension('WEBGL_debug_renderer_info');
    return 'WebGL2 ' + (e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER));
  }));
  for (const scene of scenes) {
    for (const mode of modes) {
      const q = mode === 'gl' ? '' : `mesh=${mode}`;
      await wd('POST', S('/url'), { url: q ? withQuery(url, q) : url });
      const t0 = Date.now();
      while (Date.now() - t0 < 180000) {
        const ok = await exec(() => !!(window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0)).catch(() => false);
        if (ok) break; await sleep(500);
      }
      await sleep(1000);
      let clicked = scene === 'Spheres';
      if (!clicked) {
        const names = ['Spheres', 'Waves', 'Globe'];
        const box = await exec(() => { const e = document.querySelector('[role="radiogroup"]'); if (!e) return null; const r = e.getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height }; });
        if (box) {
          const x = Math.round(box.x + box.w * (names.indexOf(scene) + 0.5) / names.length), y = Math.round(box.y + box.h / 2);
          await wd('POST', S('/actions'), { actions: [{ type: 'pointer', id: 'm', parameters: { pointerType: 'mouse' }, actions: [{ type: 'pointerMove', x, y, origin: 'viewport', duration: 0 }, { type: 'pointerDown', button: 0 }, { type: 'pause', duration: 60 }, { type: 'pointerUp', button: 0 }] }] }).catch(e => console.log('click: ' + e.message));
          await sleep(400);
        }
        clicked = (await exec(() => [...document.querySelectorAll('[role="radiogroup"]')].map(e => e.getAttribute('aria-valuetext')).find(v => v !== null) ?? null)) === scene;
      }
      await sleep(2500);
      await exec(() => {
        const d = window.__swiftuiwebDebug; window.__sceneFrames = [];
        let seen = d.frameCount(); window.__sceneStop = false;
        const tick = (t) => {
          const c = d.frameCount();
          if (c !== seen) { seen = c; const p = d.framePhases(); window.__sceneFrames.push({ t, frame: d.frameMillis(), render: p.render, encode: p.encode, paint: p.paint, ops: p.ops }); }
          if (!window.__sceneStop) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
      });
      await sleep(4000);
      const r = await exec(() => {
        window.__sceneStop = true;
        const f = window.__sceneFrames; const gaps = []; for (let k = 1; k < f.length; k++) gaps.push(f[k].t - f[k - 1].t);
        const mesh = window.__swiftuiwebMesh ? Object.assign({}, window.__swiftuiwebMesh.stats, { active: window.__swiftuiwebMesh.active }) : null;
        return { frames: f, gaps, mesh };
      });
      const res = {
        browser: 'safari', scene, mode, clicked, framesIn4s: r.frames.length, fps: +(r.frames.length / 4).toFixed(1),
        frameGap: stat(r.gaps), frameMs: stat(r.frames.map(x => x.frame)), render: stat(r.frames.map(x => x.render)),
        encode: stat(r.frames.map(x => x.encode)), paint: stat(r.frames.map(x => x.paint)), ops: stat(r.frames.map(x => x.ops)), mesh: r.mesh,
      };
      const b64 = await wd('GET', S('/screenshot'));
      const buf = Buffer.from(b64, 'base64'); writeFileSync(`${out}/${scene.toLowerCase()}-${mode}-safari.png`, buf);
      const g = grid(buf); shots[scene + mode] = g; res.covered = +g.fg.toFixed(3);
      if (mode !== 'cpu' && shots[scene + 'cpu']) res.vsCpu = compare(shots[scene + 'cpu'], g);
      results.push(res);
      const s = v => v ? `${v.median}/${v.p90}` : '-';
      console.log(`${scene.padEnd(8)} ${mode.padEnd(8)} ${String(res.fps).padStart(5)} fps  gap med/p90 ${s(res.frameGap)} ms  frame ${s(res.frameMs)}  render ${s(res.render)}  encode ${s(res.encode)}  paint ${s(res.paint)}  ops ${res.ops?.median ?? '-'}` +
        (r.mesh ? `  mesh gl=${r.mesh.gl} 2d=${r.mesh.fallback} tris=${r.mesh.triangles} uploads=${r.mesh.uploads} ${r.mesh.renderer}` : '') +
        `  covered ${res.covered}` + (res.vsCpu ? ` vs cpu mean ${res.vsCpu.mean} worst ${res.vsCpu.worst}` : '') + (clicked ? '' : '  (scene button not found)'));
    }
  }
} catch (e) {
  console.log('safari: ' + e.message);
} finally {
  await wd('DELETE', S('')).catch(() => {});
  driver.kill();
  if (jsonPath) writeFileSync(jsonPath, JSON.stringify(results, null, 2));
}
