// Opens a page in headless Chromium, collects console lines matching a pattern, clicks once,
// saves a screenshot. Used for spikes now and for Tier B fidelity checks later.
//   node run-page.mjs <url> [--dpr 2] [--pattern '\[spike05\]'] [--wait-for measureText] [--shot out.png] [--timeout 60000]
import { chromium } from 'playwright';
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--'));
const opt = (name, def) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : def; };
const dpr = Number(opt('--dpr', 2));
const pattern = new RegExp(opt('--pattern', '.'));
const waitFor = opt('--wait-for', null);
const shot = opt('--shot', null);
const timeout = Number(opt('--timeout', 60000));

const browser = await chromium.launch();
const context = await browser.newContext({ deviceScaleFactor: dpr, viewport: { width: 1280, height: 900 } });
const page = await context.newPage();
const lines = [];
page.on('console', m => { const t = m.text(); if (pattern.test(t) || m.type() === 'error') lines.push(`${m.type()}: ${t}`); });
page.on('pageerror', e => lines.push('pageerror: ' + e.message));
await page.goto(url);
const deadline = Date.now() + timeout;
while (Date.now() < deadline && !(waitFor ? lines.some(l => l.includes(waitFor)) : false)) {
  if (!waitFor) { await page.waitForTimeout(1500); break; }
  await page.waitForTimeout(250);
}
if (shot) await page.screenshot({ path: shot });
console.log(lines.join('\n') || `(no console output matching ${pattern} within ${timeout} ms)`);
await browser.close();
process.exit(lines.some(l => l.startsWith('pageerror') || l.startsWith('error')) ? 1 : 0);
