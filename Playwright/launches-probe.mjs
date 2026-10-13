// Examples/Launches in headless Chromium (decision 0021): an app whose model imports Foundation
// and Combine. Three loads in one context: the launch count (UserDefaults) and the launches on
// file (FileManager + JSONEncoder) persist through localStorage, the Combine chain sets the
// status, the dispatched delay settles it, libm and Bundle answer.
//   node launches-probe.mjs http://127.0.0.1:8765/index.html
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 400, height: 300 } });
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text()); });
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
for (let load = 1; load <= 3; load++) {
  await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(400);
  const shown = await texts();
  const summary = shown.find(t => t.startsWith('launch ')) || '';
  const status = shown.find(t => t.startsWith('event: ')) || '';
  const expected = `launch ${load}.0, ${load} on file, log2(8) = 3.0, /`;
  if (summary !== expected) problems.push(`load ${load}: summary "${summary}", expected "${expected}"`);
  if (status !== `event: settled ${load}`) problems.push(`load ${load}: status "${status}", expected "event: settled ${load}"`);
  // UIKit, Foundation and SwiftUI imported together: one Selector ("copy:"), UIScreen's bounds, the bundle's languages (none recorded: the development one).
  const mixed = shown.find(t => t.startsWith('mixed: ')) || '';
  if (!/^mixed: copy: \d+ en$/.test(mixed)) problems.push(`load ${load}: mixed imports "${mixed}", expected "mixed: copy: <width> en"`);
}
const stored = await page.evaluate(() => Object.keys(localStorage).filter(k => k.startsWith('swiftuiweb.')).sort());
if (!stored.includes('swiftuiweb.defaults.standard') || !stored.includes('swiftuiweb.files/Documents/launches.json')) problems.push('localStorage keys: ' + stored.join(', '));
console.log(problems.length ? problems.join('\n') : 'launches OK: three loads counted, on file and settled');
await browser.close();
process.exit(problems.length ? 1 : 0);
