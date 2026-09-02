// Smoke test for Examples/Counter in headless Chromium: first frame paints "Count: 0", clicking
// the "+" button (through the accessibility overlay's position) repaints "Count: 1", keyboard
// activation via the overlay works, and a screenshot is saved.
//   node counter.mjs http://127.0.0.1:8765/index.html [--shot counter.png]
import { chromium, webkit, firefox } from 'playwright';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const shot = opt('--shot', null);

const engine = { chromium, webkit, firefox }[opt('--browser', 'chromium')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 600, height: 400 } });
const page = await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
await page.goto(url);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
const initial = await texts();
if (!initial.includes('Count: 0')) problems.push('initial frame lacks "Count: 0": ' + JSON.stringify(initial));

const plus = page.locator('button[aria-label="+"]');
const box = await plus.boundingBox();
await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
await page.waitForFunction(f => window.__swiftuiwebDebug.frameCount() > f, await page.evaluate(() => window.__swiftuiwebDebug.frameCount()) - 1, { timeout: 5000 });
await page.waitForTimeout(50);
const afterClick = await texts();
if (!afterClick.includes('Count: 1')) problems.push('after click expected "Count: 1": ' + JSON.stringify(afterClick));

// Keyboard: focus the "−" overlay button and press Enter.
await page.locator('button[aria-label="−"]').focus();
await page.keyboard.press('Enter');
await page.waitForTimeout(100);
const afterKey = await texts();
if (!afterKey.includes('Count: 0')) problems.push('after keyboard expected "Count: 0": ' + JSON.stringify(afterKey));

const buttons = await page.locator('#app button').allTextContents();
if (buttons.join(',') !== '−,+') problems.push('overlay buttons: ' + JSON.stringify(buttons));
if (shot) await page.screenshot({ path: shot });
console.log(problems.length ? problems.join('\n') : `counter OK: ${initial.join(' | ')} → ${afterClick.filter(t => t.startsWith('Count')).join('')} → ${afterKey.filter(t => t.startsWith('Count')).join('')}`);
await browser.close();
process.exit(problems.length ? 1 : 0);
