// iPhone-sized check of the landing page: screenshot at 390 x 844 (DPR 3, touch) and a touch
// scroll driven through CDP, reporting frame times and the scroll distance.
// Usage: node landing-mobile.mjs <url> <out-dir>
import { chromium, devices } from 'playwright';
import { mkdirSync } from 'node:fs';
const [url, out = '.'] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const context = await browser.newContext({ ...devices['iPhone 14'] });
const page = await context.newPage();
const errors = []; page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { waitUntil: 'load', timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/mobile-top.png` });
const stats = () => page.evaluate(() => ({ frames: window.__swiftuiwebDebug.frameCount(), frameMs: Math.round(window.__swiftuiwebDebug.frameMillis()), ops: window.__swiftuiwebDebug.displayList().length, w: innerWidth, h: innerHeight, dpr: devicePixelRatio, canvas: [document.querySelector('canvas').width, document.querySelector('canvas').height], scrollY }));
console.log('at rest:', JSON.stringify(await stats()));
// A finger drag: 12 moves of 40 px upwards over ~200 ms, then release (momentum should follow).
const cdp = await context.newCDPSession(page);
const x = 195; let y = 600;
await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x, y }] });
const t0 = Date.now(); const times = [];
for (let i = 0; i < 12; i++) { y -= 40; await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x, y }] }); await page.waitForTimeout(16); times.push((await stats()).frameMs); }
await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
await page.waitForTimeout(1200);
console.log(`drag: ${Date.now() - t0} ms, frameMs during drag: ${times.join(' ')}`);
console.log('after momentum:', JSON.stringify(await stats()), 'errors:', errors.slice(0, 3));
await page.screenshot({ path: `${out}/mobile-scrolled.png` });
await browser.close();
