// Toolbar probe: opens the toolbar fixture with the gallery's chrome on (`?chrome=1`), checks the
// bar's geometry through the semantics overlay, that the content sits below it, and that a
// toolbar button's action runs.
//   node toolbar-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('toolbar/basic')}&chrome=1`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const labels = () => page.evaluate(() => window.__swiftuiwebDebug.semantics().map(n => n.label));
const box = async (label) => (await page.locator(`[aria-label="${label}"]`).boundingBox());
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };

const canvas = await page.locator('canvas').first().boundingBox();
const back = await box('Back'), action = await box('Action'), two = await box('Two'), taps = await box('Taps: 0');
check('bar items exist', back && action && two);
check('bar is 52 pt tall with 36 pt platters centred', Math.abs(back.y + back.height / 2 - (canvas.y + 26)) < 1);
check('navigation item leads', back.x - canvas.x < 40 && action.x > back.x);
check('trailing items end at the right margin', Math.abs(canvas.x + canvas.width - 8 - (two.x + two.width)) < 1);
check('content sits below the bar', taps.y > canvas.y + 52);
await page.mouse.click(action.x + action.width / 2, action.y + action.height / 2);
await page.waitForTimeout(100);
check('toolbar button action runs', (await labels()).includes('Taps: 1'));
await page.mouse.click(two.x + two.width / 2, two.y + two.height / 2);
await page.waitForTimeout(100);
check('group button action runs', (await labels()).includes('Taps: 1001'));

// searchable: the field in the bar filters the list through its binding.
await page.goto(`${url}?fixture=${encodeURIComponent('toolbar/searchable')}&chrome=1`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const field = page.locator('input[aria-label="Find fruit"]');
check('search field in the bar', await field.count() === 1);
const fieldBox = await field.boundingBox();
const canvas2 = await page.locator('canvas').first().boundingBox();
check('search field trails in the bar', fieldBox.y < canvas2.y + 52 && fieldBox.x + fieldBox.width > canvas2.x + canvas2.width - 60);
check('all rows before searching', (await labels()).includes('Elderberry'));
await field.click();
await page.keyboard.type('an');
await page.waitForTimeout(150);
const filtered = await labels();
check('typing filters the list', filtered.includes('Banana') && !filtered.includes('Cherry'));
await browser.close();
console.log(failures === 0 ? 'toolbar probe: all passed' : `toolbar probe: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
