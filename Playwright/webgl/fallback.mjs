// Without WebGL the shim must leave the page to Canvas2D: Chromium with WebGL turned off
// (--disable-3d-apis), and ?webgl=off, each still paint the page. With WebGL the painter must
// be active and paint the same thing.
//   node fallback.mjs <url of a page that loads painter-gl.js, no fixed mode>
import { chromium } from 'playwright';
import { PNG } from 'pngjs';
const url = process.argv[2];
const withQuery = (u, q) => u + (u.includes('?') ? '&' : '?') + q;
let failures = 0;
async function run(name, launchArgs, query, expectActive) {
  const browser = await chromium.launch({ args: launchArgs });
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('pageerror', e => errors.push(String(e)));
  page.on('console', m => { if (m.type() === 'error' && !/Failed to load resource/.test(m.text())) errors.push(m.text()); });
  await page.goto(query ? withQuery(url, query) : url, { waitUntil: 'commit' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(1500);
  const info = await page.evaluate(() => { const i = window.__swiftuiwebGL; return i && { active: i.active, reason: i.reason, glFrames: i.glFrames, frames: i.frames, fallbacks: i.fallbacks }; });
  const shot = PNG.sync.read(await page.screenshot());
  let painted = 0;
  for (let i = 0; i < shot.data.length; i += 4) if (shot.data[i] < 250 || shot.data[i + 1] < 250 || shot.data[i + 2] < 250) painted++;
  const share = painted / (shot.width * shot.height);
  const ok = info && !!info.active === expectActive && (expectActive ? info.glFrames > 0 : info.glFrames === 0) && share > 0.01 && errors.length === 0;
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}: ${JSON.stringify(info)}, ${(share * 100).toFixed(1)}% of the page not white${errors.length ? ', errors ' + JSON.stringify(errors.slice(0, 3)) : ''}`);
  if (!ok) failures++;
  await browser.close();
}
await run('WebGL available', [], '', true);
await run('WebGL turned off in Chromium (--disable-3d-apis)', ['--disable-3d-apis'], '', false);
await run('?webgl=off', [], 'webgl=off', false);
console.log(failures ? `fallback: ${failures} failure(s)` : 'fallback: all passed');
process.exit(failures ? 1 : 0);
