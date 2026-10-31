// Smoke test for Examples/CoreDataNotes in headless Chromium (decision 0024): a view that imports
// only SwiftUI lists Core Data notes through @FetchRequest, a predicate built in a file that
// imports only Foundation counts some of them, adds and a clear go through the context's save,
// and the notes are still there after a reload (the store in localStorage).
//   node coredata-notes.mjs http://127.0.0.1:8771/index.html [--shot notes.png]
import { chromium } from 'playwright';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const shot = opt('--shot', null);

const browser = await chromium.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 600, height: 500 } });
const page = await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });

const open = async () => {
  const started = Date.now();
  await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  return (Date.now() - started) / 1000;
};
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
// A slow runner may take a few frames to repaint: poll until every expected text is painted.
const settled = async (expected, budget = 6000) => {
  const deadline = Date.now() + budget;
  let seen = await texts();
  while (!expected.every(t => seen.includes(t)) && Date.now() < deadline) { await page.waitForTimeout(50); seen = await texts(); }
  return seen;
};
const expectTexts = async (step, expected, absent = []) => {
  const seen = await settled(expected);
  const missing = expected.filter(t => !seen.includes(t));
  const present = absent.filter(t => seen.includes(t));
  if (missing.length || present.length) problems.push(`${step}: missing ${JSON.stringify(missing)}, unexpected ${JSON.stringify(present)} in ${JSON.stringify(seen)}`);
  else console.log(`${step}: ${JSON.stringify(seen)}`);
};
const press = async (label) => {
  const button = page.locator(`button[aria-label="${label}"]`);
  const box = await button.boundingBox();
  if (!box) { problems.push(`no button labelled "${label}"`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
};

console.log(`first frame after ${(await open()).toFixed(1)} s`);
await expectTexts('empty store', ['Notes: 0', 'Ending in 2: 0']);
await press('Add');
await expectTexts('one note', ['Notes: 1', 'Note 1', 'Ending in 2: 0']);
await press('Add');
await expectTexts('two notes', ['Notes: 2', 'Note 1', 'Note 2', 'Ending in 2: 1']);
if (shot) await page.screenshot({ path: shot });

await open();
await expectTexts('after a reload', ['Notes: 2', 'Note 1', 'Note 2', 'Ending in 2: 1']);
await press('Clear');
await expectTexts('cleared', ['Notes: 0', 'Ending in 2: 0'], ['Note 1', 'Note 2']);
await open();
await expectTexts('cleared after a reload', ['Notes: 0', 'Ending in 2: 0'], ['Note 1', 'Note 2']);

await browser.close();
if (problems.length) {
  console.error('core data notes FAILED:\n  ' + problems.join('\n  '));
  process.exit(1);
}
console.log('core data notes OK');
