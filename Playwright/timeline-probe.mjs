// timeline/basic in headless Chromium: the periodic timeline's tick counter advances over a
// second, the animation timeline reports the live cadence.
//   node timeline-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('timeline/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
const ticks = async () => { const t = (await texts()).find(t => t.startsWith('Ticks: ')); return t ? Number(t.slice(7)) : -1; };
const first = await ticks();
await page.waitForTimeout(2200);
const later = await ticks();
const live = (await texts()).includes('Live');
await browser.close();
const ok = first >= 0 && later >= first + 3 && live;
console.log(`ticks ${first} → ${later} after 2.2 s, animation cadence live: ${live}`);
console.log(ok ? 'PASS timeline/basic ticks in the browser' : 'FAIL timeline/basic');
process.exit(ok ? 0 : 1);
