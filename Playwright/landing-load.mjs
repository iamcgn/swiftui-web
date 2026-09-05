// Loading-screen probe for the landing page: the statuses the screen shows while the bundle
// downloads, compiles and starts, in Chromium (network throttled so the bar is visible; a
// screenshot mid-download), WebKit and Firefox, and that the screen leaves on the first frame.
// Usage: node landing-load.mjs <url> [out-dir]
import { chromium, webkit, firefox } from 'playwright';
import { mkdirSync } from 'node:fs';
const [url, out = '.'] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
for (const [name, type] of [['chromium', chromium], ['webkit', webkit], ['firefox', firefox]]) {
  const browser = await type.launch();
  const context = await browser.newContext({ viewport: { width: 900, height: 700 } });
  const page = await context.newPage();
  const errors = []; page.on('pageerror', e => errors.push(String(e)));
  if (name === 'chromium') {
    const cdp = await context.newCDPSession(page);
    await cdp.send('Network.enable');
    await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 20, downloadThroughput: 6 * 1024 * 1024, uploadThroughput: 1024 * 1024 });
  }
  const t0 = Date.now();
  await page.goto(url);
  const seen = []; let shot = false;
  while (Date.now() - t0 < 120000) {
    const status = await page.evaluate(() => { const s = document.querySelector('#loading .status'); return s ? s.textContent : null; });
    if (status === null) break;
    if (seen[seen.length - 1] !== status) seen.push(status);
    if (!shot && /Downloading [3-7]\d%/.test(status)) { await page.screenshot({ path: `${out}/loading-${name}.png` }); shot = true; }
    await page.waitForTimeout(20);
  }
  const gone = Date.now() - t0;
  const frames = await page.evaluate(() => window.__swiftuiwebDebug ? window.__swiftuiwebDebug.frameCount() : -1);
  const compact = seen.filter((s, i) => !s.startsWith('Downloading') || i === 0 || i === seen.length - 1 || !seen[i + 1]?.startsWith('Downloading'));
  console.log(`${name}: screen gone after ${gone} ms, frames ${frames}, ${seen.length} statuses: ${compact.join(' → ')}${errors.length ? '  ERRORS: ' + errors.join('; ') : ''}`);
  await browser.close();
}
