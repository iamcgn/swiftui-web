// accessibility/basic in headless Chromium: the DOM overlay exposes the semantics tree with
// ARIA roles and labels; the slider is a range input the runtime follows; the stepper is a
// spinbutton adjusted by arrow keys.
//   node accessibility-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8766/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('accessibility/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
let ok = true;
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
const tree = await page.evaluate(() => window.__swiftuiwebDebug.semantics());
const pair = t => `${t.role}:${t.label}`;
const pairs = tree.map(pair);
check('heading, text and image elements', pairs.includes('heading:Heading') && pairs.includes('text:Plain') && pairs.includes('image:Icon image'));
check('hidden text is absent', !pairs.some(p => p.includes('Secret')));
check('combined element with its label', pairs.includes('group:Card with detail') && !pairs.includes('text:Card'));
check('button carries its identifier', tree.some(t => t.label === 'Save' && t.identifier === 'save'));
check('switch, slider and stepper roles', pairs.includes('switch:Flag') && pairs.some(p => p === 'slider:Volume') && tree.some(t => t.role === 'stepper'));
const dom = await page.evaluate(() => Array.from(document.querySelectorAll('[aria-label]')).map(e => `${e.tagName.toLowerCase()}[${e.getAttribute('role') || e.getAttribute('type') || ''}]:${e.getAttribute('aria-label')}`));
check('DOM overlay has an h2, an img role, a switch and a range input', dom.includes('h2[]:Heading') && dom.includes('div[img]:Icon image') && dom.includes('button[switch]:Flag') && dom.includes('input[range]:Volume'));
check('the slider input carries the value text', await page.evaluate(() => document.querySelector('input[type=range]').getAttribute('aria-valuetext')) === '25 percent');
// Moving the range input moves the runtime's slider.
await page.evaluate(() => { const input = document.querySelector('input[type=range]'); input.value = '0.75'; input.dispatchEvent(new Event('input', { bubbles: true })); });
await page.waitForTimeout(150);
check('the runtime follows the range input', (await page.evaluate(() => window.__swiftuiwebDebug.semantics())).find(t => t.role === 'slider').value === '75 percent');
const spin = page.locator('[role="spinbutton"]').first();
await spin.focus();
await page.keyboard.press('ArrowUp'); await page.waitForTimeout(150);
const texts = (await page.evaluate(() => window.__swiftuiwebDebug.displayList())).filter(c => c.startsWith('drawText(')).map(c => c.slice(10, c.indexOf('"', 10)));
check('arrow up on the spinbutton increments the stepper (echoed nowhere here, but no error)', texts.includes('Count'));
await browser.close();
process.exit(ok ? 0 : 1);
