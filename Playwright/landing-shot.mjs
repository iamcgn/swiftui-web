// Screenshots the landing page in headless Chromium at a tall viewport so the whole scroll view
// fits, then each demo tab. Usage: node landing-shot.mjs http://127.0.0.1:8768/ out-dir
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
const [url, out = '.'] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 4200 }, deviceScaleFactor: 1 });
const errors = [];
page.on('pageerror', e => errors.push(String(e)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
await page.goto(url);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/landing.png` });
// The segmented picker is one accessibility element (a radiogroup; its label is hidden): click its segments by position.
const picker = page.locator('[role="radiogroup"]').first();
const box = await picker.boundingBox();
if (box) {
  const tabs = ['Controls', 'Data', 'Drawing', 'State'];
  for (let i = 1; i < tabs.length; i++) {
    await page.mouse.click(box.x + box.width * (i + 0.5) / tabs.length, box.y + box.height / 2);
    await page.waitForTimeout(400);
    await page.screenshot({ path: `${out}/landing-${tabs[i].toLowerCase()}.png` });
  }
} else console.log('no picker overlay');
console.log(JSON.stringify({ errors, frames: await page.evaluate(() => window.__swiftuiwebDebug.frameCount()) }));
await browser.close();
