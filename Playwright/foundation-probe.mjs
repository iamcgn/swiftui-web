// WebFoundation through the browser (pf-web-foundation-gaps): the named zone `Intl` reports,
// daylight-saving offsets on a summer and a winter date, the locale from the browser's language,
// a formatted date, and Europe/Berlin answered on request. Run with the Counter (or any) bundle
// served: node foundation-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';

const url = process.argv[2] ?? 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const context = await browser.newContext({ timezoneId: 'America/New_York', locale: 'de-DE' });
const page = await context.newPage();
await page.goto(url);
await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);

const summer = await page.evaluate(() => window.__swiftuiwebDebug.foundation(1_782_000_000));   // 2026-06-21
const winter = await page.evaluate(() => window.__swiftuiwebDebug.foundation(1_767_225_600));   // 2026-01-01
let failures = 0;
const check = (name, ok, detail) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${name}${detail ? ` (${detail})` : ''}`); if (!ok) failures++; };
check('zone is the browser\'s tz name', summer.timeZone === 'America/New_York', summer.timeZone);
check('summer offset -4 h', summer.secondsFromGMT === -14400 && summer.isDaylightSavingTime, `${summer.secondsFromGMT}`);
check('winter offset -5 h', winter.secondsFromGMT === -18000 && !winter.isDaylightSavingTime, `${winter.secondsFromGMT}`);
check('abbreviations from Intl', summer.abbreviation === 'EDT' && winter.abbreviation === 'EST', `${summer.abbreviation} ${winter.abbreviation}`);
check('long name from Intl', winter.zoneName.includes('Eastern'), winter.zoneName);
check('locale from the browser', summer.locale === 'de_DE', summer.locale);
check('known zones listed', summer.knownZones > 300, `${summer.knownZones}`);
check('Berlin answered on request', summer.berlinOffset === 7200 && winter.berlinOffset === 3600, `${summer.berlinOffset} ${winter.berlinOffset}`);
check('formatted date in the zone', summer.formatted === 'Saturday, June 20, 2026 at 8:00:00\u202FPM EDT', summer.formatted);   // 2026-06-21 00:00Z in New York

await browser.close();
if (failures) { console.error(`${failures} check(s) failed`); process.exit(1); }
console.log('foundation probe: all checks passed');
