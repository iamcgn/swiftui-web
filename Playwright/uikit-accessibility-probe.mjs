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
const report = (name, cond) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}`); if (!cond) ok = false; };
// Polls each check's condition for up to 3 s: a slow runner can lag a frame or two behind the input.
const until = async (cond, ms = 3000) => { const end = Date.now() + ms; let v; do { v = await cond(); if (v) return v; await page.waitForTimeout(50); } while (Date.now() < end); return v; };
const check = async (name, cond) => report(name, await until(cond));
const semantics = () => page.evaluate(() => window.__swiftuiwebDebug.semantics());
let tree = await semantics();
const labels = tree.map(t => t.label);
await check('the title is a heading', async () => tree.some(t => t.role === 'heading' && t.label === 'Inbox'));
await check('accessibilityElements orders the buttons C, A, B', async () => labels.indexOf('C') < labels.indexOf('A') && labels.indexOf('A') < labels.indexOf('B'));
await check('hidden and modal elements are absent', async () => !labels.includes('Secret') && !labels.includes('Modal'));
await check('switch, slider, link and image roles', async () => tree.some(t => t.role === 'switch' && t.label === 'Notifications') && tree.some(t => t.role === 'slider' && t.label === 'Volume') && tree.some(t => t.role === 'link' && t.label === 'Terms') && tree.some(t => t.role === 'image' && t.label === 'Badge'));
const dom = async () => page.evaluate(() => Array.from(document.querySelectorAll('[aria-label]')).map(e => ({ tag: e.tagName.toLowerCase(), role: e.getAttribute('role'), label: e.getAttribute('aria-label'), disabled: e.getAttribute('aria-disabled'), selected: e.getAttribute('aria-selected'), live: e.getAttribute('aria-live') })));
let elements = await dom();
await check('the disabled button is aria-disabled, the selected one aria-selected', async () => elements.some(e => e.label === 'Disabled' && e.tag === 'button' && e.disabled === 'true') && elements.some(e => e.label === 'Selected' && e.selected === 'true'));
await check('the status label is a live region', async () => elements.some(e => e.label === 'Ready' && e.live === 'polite'));
await check('the custom actions are buttons', async () => elements.some(e => e.label === 'Archive' && e.tag === 'button') && elements.some(e => e.label === 'Flag' && e.tag === 'button'));
await page.locator('button[aria-label="Archive"]').first().dispatchEvent('click');
await page.waitForTimeout(100);
await check('the custom action runs', async () => (await semantics()).some(t => t.label === 'Archived: 1'));
// Posting an announcement fills the live region the host keeps.
await page.locator('[aria-label="Announce"]').first().dispatchEvent('click');
await page.waitForTimeout(150);
await check('the announcement reaches the live region', async () => await page.evaluate(() => Array.from(document.querySelectorAll('[role="status"][aria-live]')).some(e => e.textContent === 'Saved')));
await check('the status label changed', async () => (await semantics()).some(t => t.label === 'Announced'));
// The browser's own accessibility tree.
const snapshot = JSON.stringify(await page.accessibility.snapshot({ interestingOnly: false }));
await check('the browser accessible tree has the heading', async () => snapshot.includes('"role":"heading","name":"Inbox"'));
await check('the browser accessible tree has the disabled button', async () => /"role":"button","name":"Disabled","disabled":true/.test(snapshot));
await check('the browser accessible tree has the switch and the slider', async () => snapshot.includes('"name":"Notifications"') && snapshot.includes('"role":"slider","name":"Volume"'));
await check('the browser accessible tree has the custom action button', async () => snapshot.includes('"role":"button","name":"Flag"'));
await browser.close();
process.exit(ok ? 0 : 1);
