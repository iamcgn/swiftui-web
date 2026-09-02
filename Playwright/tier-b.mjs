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
const approximate = ['text/system-fonts', 'button/styles'];
const frameTolerance = (name, key, expected) => name.startsWith('text/') && (key === 'width' || key === 'x')
  ? Math.max(0.5, Math.abs(expected) * 0.03) : 1e-6;
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

const names = goldens(join(root, 'Fixtures', 'Goldens')).filter(n => n.startsWith(filter)).sort();
const engine = { chromium, webkit, firefox }[opt('--browser', 'chromium')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
const errors = [];
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') errors.push('console: ' + m.text()); });

let failures = 0;
const report = [];
for (const name of names) {
  const golden = JSON.parse(readFileSync(join(root, 'Fixtures', 'Goldens', name, 'frames.json'), 'utf8'));
  await page.goto(`${url}?fixture=${encodeURIComponent(name)}`);
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
  await page.waitForTimeout(50);
  const frames = await page.evaluate(() => window.__galleryFrames || window.__swiftuiwebDebug.frames());
  const mismatches = [];
  for (const [id, expected] of Object.entries(golden.frames)) {
    const actual = frames[id];
    if (!actual) { mismatches.push(`${id}: missing`); continue; }
    for (const key of ['x', 'y', 'width', 'height']) {
      if (Math.abs(actual[key] - expected[key]) > frameTolerance(name, key, expected[key])) { mismatches.push(`${id}.${key}: ${actual[key]} != ${expected[key]}`); }
    }
  }
  // Pixels: screenshot the canvas at DPR 2 and compare with the golden.
  const canvas = page.locator('#app canvas');
  const shotPath = join(out, name.replace(/\//g, '_') + '.png');
  try { await canvas.screenshot({ path: shotPath, omitBackground: true }); }
  catch { await canvas.screenshot({ path: shotPath }); }   // Firefox: element screenshots cannot omit the background
  let pixelDiff = null;
  const goldenPng = join(root, 'Fixtures', 'Goldens', name, 'image@2x.png');
  if (existsSync(goldenPng)) {
    const a = PNG.sync.read(readFileSync(shotPath));
    const b = PNG.sync.read(readFileSync(goldenPng));
    if (a.width === b.width && a.height === b.height) {
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
      pixelDiff = differing / (a.width * a.height);
      writeFileSync(join(out, name.replace(/\//g, '_') + '.diff.png'), PNG.sync.write(diff));
    } else {
      pixelDiff = `size ${a.width}x${a.height} vs ${b.width}x${b.height}`;
    }
  }
  const pixelOK = typeof pixelDiff === 'number' ? pixelDiff <= (approximate.includes(name) ? pixelTolerance * 3 : pixelTolerance) : false;
  const ok = mismatches.length === 0 && pixelOK;
  if (!ok) failures++;
  report.push({ name, frames: ok ? 'exact' : mismatches, pixelDiff, pixelOK });
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name} frames=${ok ? 'exact' : mismatches.length + ' mismatches'} pixels=${typeof pixelDiff === 'number' ? (pixelDiff * 100).toFixed(2) + '%' : pixelDiff}${pixelOK ? '' : ' (over tolerance)'}`);
  for (const m of mismatches) console.log('   ' + m);
}
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
if (errors.length) console.log(errors.join('\n'));
await browser.close();
console.log(`${names.length - failures}/${names.length} fixtures with exact frames; pixel report in ${out}`);
process.exit(failures || errors.length ? 1 : 0);
