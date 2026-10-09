// uikit/accessibility/basic in headless Chromium (uk-accessibility): the overlay exposes the
// UIKit elements with ARIA roles, labels, states and custom-action buttons in the order the
// views ask for; a custom action runs by its button; a posted announcement lands in the live
// region; a modal panel hides its siblings; the browser's own accessible tree (what a screen
// reader is given) carries the same.
//   node uikit-accessibility-probe.mjs <gallery url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 2 });
await page.goto(`${url}?fixture=${encodeURIComponent('uikit/accessibility/basic')}`);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 30000 });
await page.waitForTimeout(100);
let ok = true;
const check = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
const semantics = () => page.evaluate(() => window.__swiftuiwebDebug.semantics());
let tree = await semantics();
const labels = tree.map(t => t.label);
check('the title is a heading', tree.some(t => t.role === 'heading' && t.label === 'Inbox'));
check('accessibilityElements orders the buttons C, A, B', labels.indexOf('C') < labels.indexOf('A') && labels.indexOf('A') < labels.indexOf('B'));
check('hidden and modal elements are absent', !labels.includes('Secret') && !labels.includes('Modal'));
check('switch, slider, link and image roles', tree.some(t => t.role === 'switch' && t.label === 'Notifications') && tree.some(t => t.role === 'slider' && t.label === 'Volume') && tree.some(t => t.role === 'link' && t.label === 'Terms') && tree.some(t => t.role === 'image' && t.label === 'Badge'));
const dom = async () => page.evaluate(() => Array.from(document.querySelectorAll('[aria-label]')).map(e => ({ tag: e.tagName.toLowerCase(), role: e.getAttribute('role'), label: e.getAttribute('aria-label'), disabled: e.getAttribute('aria-disabled'), selected: e.getAttribute('aria-selected'), live: e.getAttribute('aria-live') })));
let elements = await dom();
check('the disabled button is aria-disabled, the selected one aria-selected', elements.some(e => e.label === 'Disabled' && e.tag === 'button' && e.disabled === 'true') && elements.some(e => e.label === 'Selected' && e.selected === 'true'));
check('the status label is a live region', elements.some(e => e.label === 'Ready' && e.live === 'polite'));
check('the custom actions are buttons', elements.some(e => e.label === 'Archive' && e.tag === 'button') && elements.some(e => e.label === 'Flag' && e.tag === 'button'));
await page.locator('button[aria-label="Archive"]').first().dispatchEvent('click');
await page.waitForTimeout(100);
check('the custom action runs', (await semantics()).some(t => t.label === 'Archived: 1'));
// Posting an announcement fills the live region the host keeps.
await page.locator('[aria-label="Announce"]').first().dispatchEvent('click');
await page.waitForTimeout(150);
check('the announcement reaches the live region', await page.evaluate(() => Array.from(document.querySelectorAll('[role="status"][aria-live]')).some(e => e.textContent === 'Saved')));
check('the status label changed', (await semantics()).some(t => t.label === 'Announced'));
// The browser's own accessibility tree.
const snapshot = JSON.stringify(await page.accessibility.snapshot({ interestingOnly: false }));
check('the browser accessible tree has the heading', snapshot.includes('"role":"heading","name":"Inbox"'));
check('the browser accessible tree has the disabled button', /"role":"button","name":"Disabled","disabled":true/.test(snapshot));
check('the browser accessible tree has the switch and the slider', snapshot.includes('"name":"Notifications"') && snapshot.includes('"role":"slider","name":"Volume"'));
check('the browser accessible tree has the custom action button', snapshot.includes('"role":"button","name":"Flag"'));
await browser.close();
process.exit(ok ? 0 : 1);
