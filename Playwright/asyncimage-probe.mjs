// AsyncImage probe: the gallery's own asset serves as a real image URL; a missing file fails.
//   node asyncimage-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('probe/asyncimage')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
const labels = () => page.evaluate(() => window.__swiftuiwebDebug.semantics().map(n => n.label));
const drawn = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawImage')));
await page.waitForFunction(() => window.__swiftuiwebDebug.displayList().some(c => c.startsWith('drawImage') && c.includes('badge')), null, { timeout: 15000 }).catch(() => {});
const images = await drawn();
check('served image loads and draws', images.some(c => c.includes('badge')));
await page.waitForFunction(() => window.__swiftuiwebDebug.semantics().some(n => n.label === 'Failed'), null, { timeout: 15000 }).catch(() => {});
check('a missing file reports failure', (await labels()).includes('Failed'));
check('nil URL keeps the placeholder', (await labels()).includes('No URL'));
await browser.close();
console.log(failures === 0 ? 'asyncimage probe: all passed' : `asyncimage probe: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
