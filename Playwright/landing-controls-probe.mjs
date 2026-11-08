// Landing page Controls demo (issue 54): the Notifications toggle stays interactive while it
// is off, so Space turns it off, on, off and on again without a reload, and the Name field it
// governs disables and re-enables with it. Drives the accessibility overlay with the keyboard.
//   node landing-controls-probe.mjs <landing url>
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8769/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
const errors = []; page.on('pageerror', e => errors.push(String(e)));
await page.goto(url, { timeout: 120000 });
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 120000 });
let ok = true;
const check = (name, cond, detail) => { console.log(`${cond ? 'PASS' : 'FAIL'} ${name}${!cond && detail ? ` (${detail})` : ''}`); if (!cond) ok = false; };
const toggle = '[aria-label="Notifications"][role="switch"], [aria-label="Notifications"][role="checkbox"]';
// The demo sits below the fold: wheel down until its toggle is in the overlay.
for (let i = 0; i < 40 && !(await page.locator(toggle).count()); i++) {
  await page.mouse.move(640, 450); await page.mouse.wheel(0, 400); await page.waitForTimeout(100);
}
check('the Controls demo shows a Notifications toggle', (await page.locator(toggle).count()) > 0);
const state = () => page.evaluate(sel => {
  const t = document.querySelector(sel);
  const names = [...document.querySelectorAll('[aria-label="Name"]')];
  const name = names.find(e => e.tagName === 'INPUT' || e.tagName === 'TEXTAREA') || names[0];
  return {
    on: t ? t.getAttribute('aria-checked') : null,
    toggleDisabled: t ? (t.getAttribute('aria-disabled') === 'true' || t.disabled === true) : null,
    nameDisabled: name ? (name.disabled === true || name.getAttribute('aria-disabled') === 'true') : null,
  };
}, toggle);
// Polls the overlay for the expected state, up to 3 s (a slow runner lags a frame or two).
const until = async (want, ms = 3000) => {
  const end = Date.now() + ms; let s;
  do { s = await state(); if (s.on === want.on && s.nameDisabled === want.nameDisabled) return s; await page.waitForTimeout(50); } while (Date.now() < end);
  return s;
};
if ((await page.locator(toggle).count()) > 0) {
  let s = await until({ on: 'true', nameDisabled: false });
  check('starts on, with Name enabled', s.on === 'true' && s.nameDisabled === false, JSON.stringify(s));
  for (const [round, want] of [[1, 'false'], [2, 'true'], [3, 'false'], [4, 'true']]) {
    await page.locator(toggle).first().focus();
    await page.keyboard.press('Space');
    s = await until({ on: want, nameDisabled: want === 'false' });
    const label = want === 'true' ? 'on, Name enabled' : 'off, Name disabled';
    check(`Space ${round} turns Notifications ${label}`, s.on === want && s.nameDisabled === (want === 'false'), JSON.stringify(s));
    check(`the toggle stays interactive after Space ${round}`, s.toggleDisabled === false, JSON.stringify(s));
  }
}
check('no page errors', errors.length === 0, errors.join('; '));
await browser.close();
process.exit(ok ? 0 : 1);
