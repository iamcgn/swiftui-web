// Prints the bundled fonts' load state in the gallery: `document.fonts` entries, the network
// status of the font files, and a measurement with the custom face. Usage:
// node font-probe.mjs http://127.0.0.1:8766/index.html
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2, viewport: { width: 900, height: 700 } });
const requests = [];
page.on('response', r => { if (/\.(ttf|otf|woff2?)(\?|$)/i.test(r.url())) requests.push(r.status() + ' ' + r.url()); });
page.on('console', m => console.log('console', m.type() + ':', m.text().slice(0, 300)));
page.on('pageerror', e => console.log('pageerror:', e.message.slice(0, 600)));
await page.addInitScript(() => { window.__errs = []; window.addEventListener('error', e => window.__errs.push(String(e.message) + ' @' + e.filename + ':' + e.lineno)); window.addEventListener('unhandledrejection', e => window.__errs.push('rejection: ' + String(e.reason && (e.reason.stack || e.reason)).slice(0, 400))); });
await page.goto(`${url}?fixture=${encodeURIComponent('text/custom-font')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(300);
const state = await page.evaluate(() => {
  const faces = [...document.fonts].map(f => `${f.family}:${f.status}`);
  const manifest = window.__swiftuiwebAssets && Object.keys(window.__swiftuiwebAssets.fonts || {});
  const canvas = document.createElement('canvas').getContext('2d');
  canvas.font = "20px 'Abel-Regular'"; const abel = canvas.measureText('Custom').width;
  canvas.font = "20px -apple-system"; const system = canvas.measureText('Custom').width;
  const frames = window.__swiftuiwebDebug.frames();
  return { faces, manifest, base: window.__swiftuiwebAssets && window.__swiftuiwebAssets.base, check: document.fonts.check("20px 'Abel-Regular'"), abel, system,
           frameCount: window.__swiftuiwebDebug.frameCount(), keys: Object.keys(frames), customBase: frames.customBase, column: frames.column, list: window.__swiftuiwebDebug.displayList().length };
});
console.log(JSON.stringify({ state, requests }));
page.on('crash', () => console.log('page crashed'));
await page.setViewportSize({ width: 901, height: 700 });
await page.waitForTimeout(400);
const after = await page.evaluate(() => { const f = window.__swiftuiwebDebug.frames(); return { frameCount: window.__swiftuiwebDebug.frameCount(), keys: Object.keys(f).length, customBase: f.customBase, list: window.__swiftuiwebDebug.displayList().slice(0, 3) }; });
console.log('after resize', JSON.stringify(after));
console.log('errors', JSON.stringify(await page.evaluate(() => window.__errs)));
await browser.close();
