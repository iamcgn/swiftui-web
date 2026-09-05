// Hover probe: moves the mouse over the hover fixture (served from Examples/Gallery on 8767),
// checks onHover / onContinuousHover through the semantics overlay's labels, the cursor set by
// pointerStyle, and that a tooltip appears after the pointer rests on a `help` view.
//   node hover-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
await page.goto(`${url}?fixture=${encodeURIComponent('hover/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
const labels = () => page.evaluate(() => window.__swiftuiwebDebug.semantics().map(n => n.label));
const box = async (label) => (await page.locator(`[aria-label="${label}"]`).boundingBox());
const centre = (b) => ({ x: b.x + b.width / 2, y: b.y + b.height / 2 });
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
// The cursor of the canvas under a point (the gallery has more than one canvas).
const cursorAt = (p) => page.evaluate(({ x, y }) => {
  const canvases = [...document.querySelectorAll('canvas')];
  const hit = canvases.find(c => { const r = c.getBoundingClientRect(); return x >= r.left && x <= r.right && y >= r.top && y <= r.bottom; });
  return hit ? getComputedStyle(hit).cursor : 'no canvas';
}, p);

check('resting: Outside', (await labels()).includes('Outside'));
const outside = centre(await box('Outside'));
await page.mouse.move(outside.x, outside.y);
await page.waitForTimeout(100);
check('onHover enters', (await labels()).includes('Inside') && (await labels()).includes('Entries: 1'));
const cont = centre(await box('No pointer'));
await page.mouse.move(cont.x, cont.y);
await page.waitForTimeout(100);
let now = await labels();
check('onHover leaves', now.includes('Outside'));
check('continuous hover reports a point', now.some(l => /^At \d+, \d+$/.test(l)));
if (!now.some(l => /^At \d+, \d+$/.test(l))) console.log('  labels:', now.join(' | '));
await page.mouse.move(outside.x, outside.y);
await page.waitForTimeout(100);
check('continuous hover ends', (await labels()).includes('No pointer'));

const link = centre(await box('Link'));
await page.mouse.move(link.x, link.y);
await page.waitForTimeout(50);
check('pointerStyle link → pointer cursor', await cursorAt(link) === 'pointer');
if (await cursorAt(link) !== 'pointer') console.log('  cursor:', await cursorAt(link));
const ibeam = centre(await box('Text'));
await page.mouse.move(ibeam.x, ibeam.y);
await page.waitForTimeout(50);
check('pointerStyle horizontalText → text cursor', await cursorAt(ibeam) === 'text');
await page.mouse.move(outside.x, outside.y);
await page.waitForTimeout(50);
check('cursor restored', ['auto', 'default'].includes(await cursorAt(outside)));

// Tooltip: the pixels below the pointer change once it has rested for a second.
const help = centre(await box('Help me'));
const region = { x: Math.round(help.x), y: Math.round(help.y + 18), width: 60, height: 24 };
const before = await page.screenshot({ clip: region });
await page.mouse.move(help.x, help.y);
await page.waitForTimeout(300);
const early = await page.screenshot({ clip: region });
check('no tooltip before the delay', Buffer.compare(before, early) === 0);
await page.waitForTimeout(1200);
const after = await page.screenshot({ clip: region });
check('tooltip after the delay', Buffer.compare(before, after) !== 0);
// Leave towards a view whose hover changes nothing in the region (the link only sets the cursor).
await page.mouse.move(link.x, link.y);
await page.waitForTimeout(150);
const gone = await page.screenshot({ clip: region });
check('tooltip hides on leave', Buffer.compare(before, gone) === 0);
await browser.close();
console.log(failures === 0 ? 'hover probe: all passed' : `hover probe: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
