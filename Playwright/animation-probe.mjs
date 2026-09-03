// Samples the gallery's display list while animation/frame expands: the red box's painted
// width must grow over time and settle at 200.
//   node animation-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('animation/frame')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const widths = [];
const sample = async () => {
  const list = await page.evaluate(() => window.__swiftuiwebDebug.displayList());
  const rect = list.find(c => c.startsWith('fillRect(') && c.includes('#FF383C'));
  const m = rect && rect.match(/fillRect\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)/);
  return m ? Number(m[3]) : null;
};
await page.evaluate(() => window.__galleryStep(0));
const start = Date.now();
while (Date.now() - start < 700) { widths.push(await sample()); await page.waitForTimeout(40); }
const animating = await page.evaluate(() => window.__swiftuiwebDebug.animating());
await browser.close();
const seen = widths.filter(w => w !== null);
const monotonic = seen.every((w, i) => i === 0 || w >= seen[i - 1]);
const intermediate = seen.some(w => w > 100 && w < 200);
console.log('widths:', seen.join(' '), '| animating at end:', animating);
const ok = monotonic && intermediate && seen[seen.length - 1] === 200 && !animating;
console.log(ok ? 'PASS animation/frame grows 100 → 200 over 0.3 s' : 'FAIL animation/frame');
process.exit(ok ? 0 : 1);
