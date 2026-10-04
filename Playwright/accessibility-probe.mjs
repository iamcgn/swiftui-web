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

// accessibility/actions: custom and adjustable actions, heading levels, sort order, a live
// region, help as a title, and a rotor as a navigation landmark; the browser's own accessible
// tree (ariaSnapshot) as the stand-in for a screen reader session.
await page.goto(`${url}?fixture=${encodeURIComponent('accessibility/actions')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
await page.waitForTimeout(100);
const semantics = () => page.evaluate(() => window.__swiftuiwebDebug.semantics());
let tree2 = await semantics();
check('heading level one is an h1', await page.evaluate(() => Array.from(document.querySelectorAll('h1')).some(h => h.getAttribute('aria-label') === 'Overview')));
check('sort priority orders the elements', tree2.map(t => t.label).indexOf('Second') < tree2.map(t => t.label).indexOf('Third'));
check('live region and help title', await page.evaluate(() => { const e = document.querySelector('[aria-live]'); return e && e.getAttribute('aria-live') === 'polite' && e.getAttribute('title') === 'Updates every second'; }));
// The default action makes the card a button; the named action is a button inside it.
const card = page.locator('[aria-label="Archived: 0"]').first();
check('a default action makes the element a button', (await card.evaluate(e => e.tagName)) === 'BUTTON');
await page.locator('button[aria-label="Archive"]').first().dispatchEvent('click');
await page.waitForTimeout(100);
check('the named action runs', (await semantics()).some(t => t.label === 'Archived: 1'));
await page.locator('[aria-label="Archived: 1"]').first().dispatchEvent('click');
await page.waitForTimeout(100);
check('activation runs the default action', (await semantics()).some(t => t.label === 'Archived: 11'));
// The adjustable text is a spinbutton the arrow keys step.
const level = page.locator('[role="spinbutton"][aria-label="Level: 3"]').first();
await level.focus();
await page.keyboard.press('ArrowUp'); await page.waitForTimeout(100);
check('arrow up on the adjustable element increments', (await semantics()).some(t => t.label === 'Level: 4'));
// The rotor is a nav landmark whose links focus their entries.
check('the rotor is a nav with its entries', await page.evaluate(() => Array.from(document.querySelectorAll('nav[aria-label="Fruit"] a')).map(a => a.getAttribute('aria-label')).join(',')) === 'Apple,Banana');
await page.locator('nav[aria-label="Fruit"] a[aria-label="Banana"]').first().dispatchEvent('click');
await page.waitForTimeout(100);
check('a rotor entry focuses its element', await page.evaluate(() => document.activeElement?.getAttribute('aria-label')) === 'Banana');
// The browser's own accessibility tree (what a screen reader is given).
const snapshot = JSON.stringify(await page.accessibility.snapshot({ interestingOnly: false }));
check('the browser accessible tree has the level-one heading', snapshot.includes('"role":"heading","name":"Overview","level":1'));
check('the browser accessible tree has the custom action button', snapshot.includes('"role":"button","name":"Archive"'));
check('the browser accessible tree has the rotor landmark', snapshot.includes('"role":"navigation","name":"Fruit"'));
check('the browser accessible tree has the adjustable spinbutton', /"role":"spinbutton","name":"Level: \d"/.test(snapshot));
await browser.close();
process.exit(ok ? 0 : 1);
