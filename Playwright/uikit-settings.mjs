// Smoke test for Examples/UIKitSettings (UIKitWeb, decision 0014): a tab bar over a navigation
// controller and an inset grouped table with controls. The first frame shows the large title and
// the rows; tapping the Appearance row pushes a screen with a segmented control; the back platter
// pops; the About tab switches screens; a screenshot is saved.
//   node uikit-settings.mjs http://127.0.0.1:8765/index.html [--browser chromium|webkit|firefox] [--shot out.png]
import { chromium, webkit, firefox } from 'playwright';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const shot = opt('--shot', null);

const engine = { chromium, webkit, firefox }[opt('--browser', 'chromium')];
const browser = await engine.launch();
const context = await browser.newContext({ deviceScaleFactor: 2, viewport: { width: 390, height: 700 } });
const page = await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message + (process.env.SHOW_STACK ? '\n' + (e.stack || '') : '')));
page.on('console', m => { if (m.type() === 'error' || (process.env.SHOW_STACK && m.type() === 'warning')) problems.push('console: ' + m.text()); });
const started = Date.now();
await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
console.log(`first frame after ${((Date.now() - started) / 1000).toFixed(1)} s`);
const texts = async () => (await page.evaluate(() => window.__swiftuiwebDebug.displayList()))
  .filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
// Taps go through the accessibility overlay's element for the label (its box is the element's frame).
const tap = async (label) => {
  const box = await page.locator(`[aria-label="${label}"]`).first().boundingBox();
  if (!box) { problems.push(`no overlay element labelled "${label}"`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  // A push or pop slides for 0.35 s.
  await page.waitForTimeout(600);
};

const initial = await texts();
for (const expected of ['Settings', 'General', 'Notifications', 'Appearance', 'Brightness', 'Text Size', 'About']) {
  if (!initial.includes(expected)) problems.push(`initial frame lacks "${expected}": ` + JSON.stringify(initial));
}
// The Appearance row pushes its screen: the title changes and the segmented control appears.
await tap('Appearance');
const pushed = await texts();
if (!pushed.includes('Automatic') || !pushed.includes('Light')) problems.push('after the push expected the segmented control: ' + JSON.stringify(pushed));
if (pushed.includes('Notifications')) problems.push('after the push the settings rows are still drawn');
// The back platter pops.
await tap('Back');
const popped = await texts();
if (!popped.includes('Notifications')) problems.push('after the pop expected the settings rows: ' + JSON.stringify(popped));
// The Reset bar button presents an alert; Cancel dismisses it.
await tap('Reset');
const alerted = await texts();
if (!alerted.includes('Reset settings?') || !alerted.includes('Cancel')) problems.push('after Reset expected the alert: ' + JSON.stringify(alerted));
await tap('Cancel');
const cancelled = await texts();
if (cancelled.includes('Reset settings?')) problems.push('after Cancel the alert is still drawn');
// The About tab switches the screen.
await tap('About');
const about = await texts();
if (!about.some(t => t.startsWith('UIKitWeb runs'))) problems.push('after the tab expected the about text: ' + JSON.stringify(about));
if (shot) await page.screenshot({ path: shot });
await browser.close();
if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
console.log('uikit settings OK: push, pop, alert and tab switch');
