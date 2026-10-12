// Frame times on a real phone: drives Safari on an iPhone through safaridriver (WebDriver, not
// Playwright), samples every animation frame while a finger drag and its momentum run, and
// prints the frame-time split the host records (`__swiftuiwebDebug`), the rAF gaps (a dropped
// frame shows as a gap over one vsync even when the CPU time was short), and the canvas facts.
// Setup (once): on the iPhone, Settings > Apps > Safari > Advanced > Remote Automation on; on the
// Mac `safaridriver -p 4444`. The page must be reachable from the phone (serve the dist on the
// LAN: `python3 -m http.server 8787 --bind 0.0.0.0 --directory Examples/Landing/dist`).
// Usage: node device-perf.mjs <url> [--udid <udid>] [--driver http://127.0.0.1:4444]
//        [--drag <px>] [--repeat <n>] [--json <file>] [--keep]
import { writeFileSync } from 'node:fs';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--') && !args[args.indexOf(a) - 1]?.startsWith('--'));
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const driver = option('--driver', 'http://127.0.0.1:4444');
const udid = option('--udid', process.env.DEVICE_UDID);
const dragPixels = Number(option('--drag', '500'));
const repeat = Number(option('--repeat', '1'));
const jsonOut = option('--json', null);
if (!url) { console.error('usage: node device-perf.mjs <url> [--udid <udid>]'); process.exit(2); }

const request = async (method, path, body) => {
  const response = await fetch(driver + path, { method, headers: { 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const json = await response.json();
  if (json.value && json.value.error) throw new Error(`${method} ${path}: ${json.value.error}: ${json.value.message}`);
  return json.value;
};
const alwaysMatch = { browserName: 'Safari' };
if (udid) { alwaysMatch.platformName = 'iOS'; alwaysMatch['safari:deviceUDID'] = udid; }
const session = await request('POST', '/session', { capabilities: { alwaysMatch } });
const id = session.sessionId;
const run = (script, ...scriptArgs) => request('POST', `/session/${id}/execute/sync`, { script, args: scriptArgs });
const sleep = ms => new Promise(r => setTimeout(r, ms));
try {
  await request('POST', `/session/${id}/url`, { url });
  // The first frame: the loading screen goes when the host has painted once.
  for (let i = 0; i < 600; i++) {
    const ready = await run('return !!(window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0)');
    if (ready) break;
    await sleep(250);
  }
  await sleep(800);
  const facts = await run(`
    const c = document.querySelector('canvas');
    const probe = (() => { try { const p = new OffscreenCanvas(1, 1).getContext('2d'); p.filter = 'blur(1px)'; return { offscreen: true, filter: p.filter !== 'none' && p.filter !== '', reset: typeof p.reset === 'function', letterSpacing: 'letterSpacing' in p }; } catch (e) { return { offscreen: false, error: String(e) }; } })();
    return { ua: navigator.userAgent, dpr: devicePixelRatio, viewport: [innerWidth, innerHeight], canvas: [c.width, c.height],
             ops: window.__swiftuiwebDebug.displayList().length, firstFrameMs: window.__swiftuiwebDebug.frameMillis(), ...probe };`);
  console.log('device:', JSON.stringify(facts));
  // The engine's speed: Safari's WebDriver session on iOS runs without the JIT (a tab opened
  // by hand on the same phone ran this loop in 8 ms, the session in 200 ms, 2026-10-12), so
  // the times below are proportions, not the device's absolute ones.
  const speed = await run(`const n = 5000000; const t0 = performance.now(); const values = new Float64Array(1024).fill(1); let acc = 0; for (let i = 0; i < n; i++) { const j = i & 1023; values[j] = values[j] * 0.5 + (i & 255) * 0.25; acc += Math.sqrt(values[j]); } return { js: performance.now() - t0 + (isNaN(acc) ? 1 : 0), wasm: window.__swiftuiwebDebug.bench ? window.__swiftuiwebDebug.bench(n) : null };`);
  console.log(`engine: js ${speed.js.toFixed(0)} ms, wasm ${speed.wasm === null ? '-' : speed.wasm.toFixed(0) + ' ms'} for the 5 M loop${speed.js > 50 ? ' — a JIT-less session: times are proportions, the ?perf HUD by hand gives the device\'s own' : ''}`);
  // The sampler: every rAF records the gap since the previous one and, when the host painted a
  // frame in between, that frame's split; it runs until stopped.
  await run(`
    const d = window.__swiftuiwebDebug;
    const s = window.__perfSampler = { gaps: [], frames: [], lastCount: d.frameCount(), lastT: null, running: true };
    const tick = t => {
      if (!s.running) return;
      if (s.lastT !== null) s.gaps.push(t - s.lastT);
      s.lastT = t;
      const count = d.frameCount();
      if (count !== s.lastCount) {
        const p = d.framePhases();
        s.frames.push({ t: t, ms: d.frameMillis(), layout: p.layout, render: p.render, encode: p.encode, paint: p.paint, semantics: p.semantics, overlay: p.overlay, ops: p.ops, gap: p.gap });
        s.lastCount = count;
      }
      requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);`);
  // A finger drag up the middle of the screen, `dragPixels` over 400 ms, then release: the
  // momentum scroll follows. The host's scripted drag feeds the scene the way a finger does
  // (W3C touch actions reach the page but hardly the canvas on iOS); a bundle without it
  // gets the actions.
  const x = Math.round(facts.viewport[0] / 2), y0 = Math.round(facts.viewport[1] * 0.75);
  const scripted = await run('return typeof window.__swiftuiwebDebug.drag === "function"');
  for (let r = 0; r < repeat; r++) {
    if (scripted) {
      await run('window.__swiftuiwebDebug.drag(arguments[0], arguments[1], 0, -arguments[2], 0.4)', x, y0, dragPixels);
      for (let i = 0; i < 40; i++) { await sleep(100); if (!(await run('return window.__swiftuiwebDebug.dragging()'))) break; }
    } else {
      await request('POST', `/session/${id}/actions`, { actions: [{ type: 'pointer', id: 'finger', parameters: { pointerType: 'touch' }, actions: [
        { type: 'pointerMove', duration: 0, x, y: y0 },
        { type: 'pointerDown', button: 0 },
        { type: 'pointerMove', duration: 400, x, y: y0 - dragPixels },
        { type: 'pointerUp', button: 0 }] }] });
    }
    await sleep(1500);
  }
  const sample = await run('window.__perfSampler.running = false; return window.__perfSampler;');
  const stat = values => {
    if (!values.length) return { n: 0 };
    const sorted = [...values].sort((a, b) => a - b);
    const q = p => sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
    return { n: values.length, mean: +(values.reduce((a, b) => a + b, 0) / values.length).toFixed(2), p50: +q(0.5).toFixed(2), p90: +q(0.9).toFixed(2), max: +sorted[sorted.length - 1].toFixed(2) };
  };
  const frames = sample.frames;
  const report = {
    url, device: facts,
    frames: stat(frames.map(f => f.ms)),
    phases: Object.fromEntries(['layout', 'render', 'encode', 'paint', 'semantics', 'overlay'].map(k => [k, stat(frames.map(f => f[k]).filter(v => v !== undefined))])),
    rafGaps: stat(sample.gaps),
    droppedFrames: sample.gaps.filter(g => g > 25).length,
    longFrames: frames.filter(f => f.ms > 16).length,
    frameCount: await run('return window.__swiftuiwebDebug.frameCount()'),
  };
  console.log(`frames painted: ${report.frames.n}; frame ms mean ${report.frames.mean} p50 ${report.frames.p50} p90 ${report.frames.p90} max ${report.frames.max}; >16 ms: ${report.longFrames}`);
  console.log('phases (p50/p90):', Object.entries(report.phases).filter(([, v]) => v.n).map(([k, v]) => `${k} ${v.p50}/${v.p90}`).join('  '));
  console.log(`rAF gaps: mean ${report.rafGaps.mean} p90 ${report.rafGaps.p90} max ${report.rafGaps.max} (${report.droppedFrames} gaps over 25 ms of ${report.rafGaps.n})`);
  const worst = [...frames].sort((a, b) => b.ms - a.ms).slice(0, 5);
  console.log('worst frames:', worst.map(f => `${f.ms.toFixed(1)} (layout ${f.layout.toFixed(1)} render ${f.render.toFixed(1)}${f.encode !== undefined ? ` encode ${f.encode.toFixed(1)}` : ''} paint ${f.paint.toFixed(1)} overlay ${f.overlay.toFixed(1)})`).join('; '));
  if (jsonOut) writeFileSync(jsonOut, JSON.stringify({ ...report, samples: sample }, null, 1));
} finally {
  if (!args.includes('--keep')) await request('DELETE', `/session/${id}`);
}
