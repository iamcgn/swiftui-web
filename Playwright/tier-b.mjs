// Tier B: for every fixture with a golden, open the gallery page, read probe frames through the
// debug bridge and compare with frames.json; screenshot the canvas and report the pixel
// difference against image@2x.png. Frames must match exactly (Tier A parity); pixels are
// reported with a tolerance because text rasterisation differs per browser.
//   node tier-b.mjs http://127.0.0.1:8766/index.html [--filter layout/] [--out ../.build/tier-b] [--pixel-tolerance 0.02]
import { chromium, webkit, firefox } from 'playwright';
import { readFileSync, writeFileSync, mkdirSync, existsSync, readdirSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const filter = opt('--filter', '');
const out = opt('--out', join(root, '.build', 'tier-b'));
const browserName = opt('--browser', 'chromium');
// Firefox hints glyphs differently on macOS; its text fixtures land around 3.5 % differing pixels.
const pixelTolerance = Number(opt('--pixel-tolerance', browserName === 'firefox' ? 0.05 : 0.03));
// Browser font fallbacks (weights 300/900, rounded, serif, monospaced) legitimately differ from
// SF on macOS; those fixtures are held to a looser bound and listed as approximate.
// splitview/*: Apple's capture drops the sidebar's rows and selection and fills the 8 pt bands
// beside the sidebar panel with a black-to-clear gradient (about 3.4 % of a 480 × 300 window).
// texteditor/basic: NSTextView sets SF tighter between letters and wider at spaces than SwiftUI's
// Text does, so its paragraph keeps one more word on the first line.
const approximate = ['text/system-fonts', 'button/styles', 'progress/indeterminate', 'splitview/basic', 'splitview/widths', 'splitview/three',
  'splitview/columns', 'splitview/sized', 'splitview/selection', 'splitview/visibility', 'texteditor/basic'];
const frameCount = () => page.evaluate(() => window.__swiftuiwebDebug.frameCount());
const frameTolerance = (name, key, expected) => name.startsWith('text/') && (key === 'width' || key === 'x')
  ? Math.max(0.5, Math.abs(expected) * 0.03) : name === 'symbol/basic' ? 2 : name.startsWith('symbol/') ? 0.5 : 1e-6;
// Symbol fixtures draw open-icon stand-ins for SF Symbols: their frames are checked (the basic
// fixture's last row holds scaled sizes, allowed 2 pt like Tier A) and their pixels are not.
const framesOnly = (name) => name.startsWith('symbol/') || name === 'effects/shadow-offset';
mkdirSync(out, { recursive: true });

function goldens(dir, prefix = '') {
  const result = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      if (existsSync(join(path, 'frames.json'))) result.push(prefix + entry);
      else result.push(...goldens(path, prefix + entry + '/'));
    }
  }
  return result;
}

// Goldens recorded ahead of their implementation (Docs/elements/Text.md: height pressure) are skipped.
const pending = [];
const names = goldens(join(root, 'Fixtures', 'Goldens')).filter(n => n.startsWith(filter) && !pending.some(p => n.startsWith(p))).sort();
const engine = { chromium, webkit, firefox }[opt('--browser', 'chromium')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
const errors = [];
// Every console message of the current fixture, printed when the fixture never paints.
let transcript = [];
page.on('pageerror', e => { errors.push('pageerror: ' + e.message); transcript.push('pageerror: ' + e.message); });
// The AsyncImage fixture loads an unreachable URL on purpose; the browser's load failure is not an error of ours.
const expectedConsoleError = text => /never\.png|Failed to load resource/.test(text);
page.on('console', m => { if (m.type() === 'error' && !expectedConsoleError(m.text())) errors.push('console: ' + m.text()); transcript.push(m.type() + ': ' + m.text()); });

let failures = 0;
const report = [];

// Probes Apple reports but nothing reproduces: a hidden tab's content keeps its stale frame.
// A collapsed sidebar in Apple's offscreen window keeps its frame and the detail its place.
const ignoredProbes = { 'tabview/basic/second': ['first'], 'splitview/visibility': ['sidebar', 'row1', 'detail'], 'splitview/visibility/detailOnly': ['sidebar', 'row1', 'detail'],
  'table/sorting/byCount': ['name2', 'name3', 'count2', 'count3'] };
function compareFrames(name, frames, goldenFrames) {
  const mismatches = [];
  const ignored = ignoredProbes[name] || [];
  for (const [id, expected] of Object.entries(goldenFrames)) {
    if (ignored.includes(id)) continue;
    const actual = frames[id];
    if (!actual) { mismatches.push(`${id}: missing`); continue; }
    for (const key of ['x', 'y', 'width', 'height']) {
      if (Math.abs(actual[key] - expected[key]) > frameTolerance(name, key, expected[key])) { mismatches.push(`${id}.${key}: ${actual[key]} != ${expected[key]}`); }
    }
  }
  return mismatches;
}

// Screenshots the canvas at DPR 2 and returns the fraction of differing pixels vs the golden.
async function comparePixels(shotPath, goldenPng) {
  const canvas = page.locator('#app canvas');
  try { await canvas.screenshot({ path: shotPath, omitBackground: true }); }
  catch { await canvas.screenshot({ path: shotPath }); }   // Firefox: element screenshots cannot omit the background
  if (!existsSync(goldenPng)) return null;
  const a = PNG.sync.read(readFileSync(shotPath));
  const b = PNG.sync.read(readFileSync(goldenPng));
  if (a.width !== b.width || a.height !== b.height) return `size ${a.width}x${a.height} vs ${b.width}x${b.height}`;
  let differing = 0;
  const diff = new PNG({ width: a.width, height: a.height });
  // Compare composited onto white: the goldens have a transparent background, the canvas is opaque.
  const over = (data, i, c) => { const alpha = data[i + 3] / 255; return Math.round(data[i + c] * alpha + 255 * (1 - alpha)); };
  for (let i = 0; i < a.data.length; i += 4) {
    const d = Math.max(Math.abs(over(a.data, i, 0) - over(b.data, i, 0)), Math.abs(over(a.data, i, 1) - over(b.data, i, 1)),
                       Math.abs(over(a.data, i, 2) - over(b.data, i, 2)));
    const bad = d > 32;
    if (bad) differing++;
    diff.data[i] = bad ? 255 : a.data[i]; diff.data[i + 1] = bad ? 0 : a.data[i + 1]; diff.data[i + 2] = bad ? 0 : a.data[i + 2]; diff.data[i + 3] = bad ? 255 : Math.max(40, a.data[i + 3]);
  }
  writeFileSync(shotPath.replace(/\.png$/, '.diff.png'), PNG.sync.write(diff));
  return differing / (a.width * a.height);
}

// Catalog images load asynchronously: wait until none is pending, then for the repaint.
async function settleImages() {
  const before = await frameCount();
  await page.waitForFunction(() => window.__swiftuiwebDebug.pendingImages() === 0, null, { timeout: 30000 });
  await page.waitForFunction(b => window.__swiftuiwebDebug.pendingImages() === 0 && window.__swiftuiwebDebug.frameCount() >= b, before, { timeout: 10000 });
  await page.waitForTimeout(50);
}

// One comparison (the initial render, or the render after a behaviour step).
async function check(name, label, goldenFrames, goldenPng, shotPath) {
  await settleImages();
  const frames = await page.evaluate(() => window.__galleryFrames || window.__swiftuiwebDebug.frames());
  const mismatches = compareFrames(label, frames, goldenFrames);
  const pixelDiff = framesOnly(name) ? 'skipped' : await comparePixels(shotPath, goldenPng);
  const pixelOK = framesOnly(name) || (typeof pixelDiff === 'number' ? pixelDiff <= (approximate.includes(name) ? pixelTolerance * 3 : pixelTolerance) : false);
  const ok = mismatches.length === 0 && pixelOK;
  if (!ok) failures++;
  report.push({ name: label, frames: ok ? 'exact' : mismatches, pixelDiff, pixelOK });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${label} frames=${ok ? 'exact' : mismatches.length + ' mismatches'} pixels=${typeof pixelDiff === 'number' ? (pixelDiff * 100).toFixed(2) + '%' : pixelDiff}${pixelOK ? '' : ' (over tolerance)'}`);
  for (const m of mismatches) console.log('   ' + m);
}

// The gallery's syntax highlighter comes from a CDN the fixtures do not need: answer it with an
// empty file so a slow or stalled CDN never holds a navigation (the WASI shim from jsdelivr is
// needed and stays).
await page.route('https://cdnjs.cloudflare.com/**', route => route.fulfill({ status: 200, contentType: route.request().url().endsWith('.css') ? 'text/css' : 'application/javascript', body: '' }));
// The first navigation fetches and compiles the debug wasm (80+ MB) through a single-threaded
// server, which took a CI runner more than Playwright's default 30 s: wait for the first frame,
// not the load event, with a generous budget for the first fixture.
// Later fixtures are selected in place, as a click on the gallery's list would (the URL is pushed
// and the popstate handler mounts the fixture on the same host), so the wasm loads once.
// Loads the page fresh on `name`; the first load fetches and compiles the wasm.
async function load(name, budget) {
  await page.goto(`${url}?fixture=${encodeURIComponent(name)}`, { waitUntil: 'commit', timeout: budget });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: budget });
}
// Selects `name` in place and waits for the gallery to publish its frames (a hung mount leaves
// them undefined even when a stale frame still paints).
async function select(name) {
  await page.evaluate(n => {
    history.pushState(null, '', '?fixture=' + encodeURIComponent(n));
    dispatchEvent(new PopStateEvent('popstate'));
  }, name);
  await page.waitForFunction(() => window.__galleryFrames !== undefined, null, { timeout: 60000 });
}
let firstLoad = true;
for (const name of names) {
  const goldenDir = join(root, 'Fixtures', 'Goldens', name);
  const golden = JSON.parse(readFileSync(join(goldenDir, 'frames.json'), 'utf8'));
  const started = Date.now();
  const base = join(out, name.replace(/\//g, '_'));
  transcript = [];
  try {
    if (firstLoad) {
      await load(name, 180000);
      console.log(`first fixture ready after ${((Date.now() - started) / 1000).toFixed(1)} s`);
      firstLoad = false;
    } else {
      await select(name);
    }
  } catch (e) {
    // The fixture never painted: report what the page said, keep its screenshot, and reload the
    // gallery so the following fixtures run on a fresh runtime.
    failures++;
    report.push({ name, frames: 'hung', pixels: null });
    console.log(`FAIL ${name}: no frame within ${((Date.now() - started) / 1000).toFixed(0)} s (${e.message.split('\n')[0]})`);
    const state = await page.evaluate(() => ({ frames: window.__swiftuiwebDebug ? window.__swiftuiwebDebug.frameCount() : 'no runtime', published: window.__galleryFrames !== undefined })).catch(err => ({ error: err.message }));
    console.log('   state: ' + JSON.stringify(state));
    for (const line of transcript.slice(-25)) console.log('   ' + line.split('\n')[0].slice(0, 300));
    await page.screenshot({ path: base + '.hung.png' }).catch(() => {});
    try { await load(names[0], 180000); } catch (err) { console.log('   reload failed: ' + err.message.split('\n')[0]); }
    continue;
  }
  await page.waitForTimeout(50);
  await check(name, name, golden.frames, join(goldenDir, 'image@2x.png'), base + '.png');

  // Behaviour steps: apply each through the gallery hook, wait for the repaint, compare again.
  const steps = golden.steps || [];
  const stepCount = await page.evaluate(() => window.__galleryStepCount || 0);
  if (stepCount !== steps.length) { failures++; console.log(`FAIL ${name}: gallery has ${stepCount} step(s), golden has ${steps.length}`); continue; }
  for (let i = 0; i < steps.length; i++) {
    const before = await frameCount();
    await page.evaluate(i => window.__galleryStep(i), i);
    // Wait for the repaint and for any animation the step started to settle (goldens hold end states).
    await page.waitForFunction(b => window.__swiftuiwebDebug.frameCount() > b && !(window.__swiftuiwebDebug.animating && window.__swiftuiwebDebug.animating()), before, { timeout: 10000 });
    await page.waitForTimeout(50);
    await check(name, `${name}/${steps[i].name}`, steps[i].frames, join(goldenDir, `step-${i + 1}@2x.png`), `${base}_step-${i + 1}.png`);
  }
}
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
if (errors.length) console.log(errors.join('\n'));
await browser.close();
console.log(`${report.length - failures}/${report.length} renders within tolerance across ${names.length} fixtures; pixel report in ${out}`);
process.exit(failures || errors.length ? 1 : 0);
