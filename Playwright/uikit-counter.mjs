// Smoke test for Examples/UIKitCounter (UIKitWeb, decision 0014) in a headless browser: the
// first frame paints "Count: 0", clicking the "+" button through the accessibility overlay
// repaints "Count: 1", keyboard activation of "−" through the overlay brings it back, and a
// screenshot is saved.
//   node uikit-counter.mjs http://127.0.0.1:8765/index.html [--browser chromium|webkit|firefox] [--shot out.png]
import { chromium, webkit, firefox } from 'playwright';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const shot = opt('--shot', null);

const engine = { chromium, webkit, firefox }[opt('--browser', 'chromium')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 390, height: 500 } });
const page = await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
const started = Date.now();
await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
console.log(`first frame after ${((Date.now() - started) / 1000).toFixed(1)} s`);
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
const initial = await texts();
if (!initial.includes('Count: 0')) problems.push('initial frame lacks "Count: 0": ' + JSON.stringify(initial));

const plus = page.locator('button[aria-label="+"]');
const box = await plus.boundingBox();
if (!box) problems.push('no overlay button for "+"');
else {
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await page.waitForTimeout(100);
  const afterClick = await texts();
  if (!afterClick.includes('Count: 1')) problems.push('after click expected "Count: 1": ' + JSON.stringify(afterClick));
}

await page.locator('button[aria-label="−"]').focus();
await page.keyboard.press('Enter');
await page.waitForTimeout(100);
const afterKey = await texts();
if (!afterKey.includes('Count: 0')) problems.push('after keyboard expected "Count: 0": ' + JSON.stringify(afterKey));

const roles = await page.evaluate(() => window.__swiftuiwebDebug.semantics().map(n => n.role + ':' + n.label));
if (roles.join(',') !== 'text:Count: 0,button:−,button:+') problems.push('semantics: ' + JSON.stringify(roles));
if (shot) await page.screenshot({ path: shot });
await browser.close();
if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
console.log('uikit counter OK: ' + initial.join(' | ') + ' → Count: 1 → Count: 0');
