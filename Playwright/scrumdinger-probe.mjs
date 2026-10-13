// Scrumdinger (Apps/upstream/Scrumdinger, unmodified; decision 0021) in headless Chromium, the
// flow a user takes: the add sheet from the bar's "+" (a NavigationStack in a sheet with its
// own Dismiss and Add), a title typed into the form, an attendee added with the icon-only "Add
// Attendee" button, the scrum on the list after Add and still there after a reload (its
// FileService through localStorage), the detail screen opened from the card, a meeting started
// (the real SpeechService, which the app's `.task` runs: it asks for speech authorisation,
// which the browser host reports as unavailable — pf-speech, no recogniser is installed — so
// the app shows its own alert, dismissed with OK, and does not start its timer: the meeting
// is blocked on speech, which this probe records rather than passes).
//   node scrumdinger-probe.mjs http://127.0.0.1:8773/index.html?platform=ios
import { chromium } from 'playwright';
const url = process.argv[2];
const browser = await chromium.launch({ args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 375, height: 667 }, hasTouch: true, isMobile: true });
const problems = [];
const logs = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
page.on('console', m => { logs.push(m.text()); if (m.type() === 'error') problems.push('console: ' + m.text()); });
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
const settle = async (ready, tries = 50) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(100); t = await texts(); } return t; };
const tap = async (label, which = 'first') => {
  const box = await page.locator(`[aria-label="${label}"]`)[which]().boundingBox();
  if (!box) { problems.push(`no element labelled "${label}"`); return; }
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
};
const expect = (condition, message) => { if (!condition) problems.push(message); };
// Taps a painted text (a row with a tap gesture has no control element).
const tapText = async (text, dx = 20, dy = -8) => {
  const at = await page.evaluate((text) => { const op = window.__swiftuiwebDebug.displayList().find(c => c.startsWith(`drawText("${text}"`)); const m = op && op.match(/at ([\d.]+),([\d.]+)/); return m ? { x: +m[1], y: +m[2] } : null; }, text);
  if (!at) { problems.push(`no painted text "${text}"`); return; }
  await page.mouse.click(at.x + dx, at.y + dy);
};
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(300);
};

await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
await loaded();
expect((await texts()).includes('Daily Scrums'), 'the list screen did not show "Daily Scrums"');
expect(logs.some(l => l.includes('SpeechRecognizer created')), 'the real SpeechService did not find a recogniser (RuntimeEnvironment should be the physical device on wasm)');

// The add sheet: a NavigationStack inside a sheet with Dismiss and Add in its bar.
await tap('Add');
let shown = await settle(t => t.includes('Dismiss') && t.includes('Meeting Info'));
expect(shown.includes('Dismiss') && shown.includes('Add') && shown.includes('Title'), 'the add sheet did not show its bar and form: ' + JSON.stringify(shown));

await tap('Title');
await page.waitForTimeout(200);
await page.keyboard.type('Design review');
shown = await settle(t => t.includes('Design review'));
expect(shown.includes('Design review'), 'the title was not typed: ' + JSON.stringify(shown));

await tap('New Attendee');
await page.waitForTimeout(200);
await page.keyboard.type('Ada');
await settle(t => t.includes('Ada'));
await tap('Add Attendee');
shown = await settle(t => t.includes('Ada') && t.includes('New Attendee'));
expect(shown.includes('Ada') && shown.includes('New Attendee'), 'the attendee row did not appear with the field cleared: ' + JSON.stringify(shown));

await tap('Add', 'last');
shown = await settle(t => !t.includes('Dismiss') && t.includes('Design review'));
expect(shown.includes('Design review') && shown.includes('1') && shown.includes('5'), 'the card did not show the scrum with 1 attendee and 5 minutes: ' + JSON.stringify(shown));

// On file: a reload shows it again.
await page.reload({ waitUntil: 'commit' });
await loaded();
shown = await settle(t => t.includes('Design review'));
expect(shown.includes('Design review'), 'the scrum did not survive a reload: ' + JSON.stringify(shown));
const stored = await page.evaluate(() => Object.keys(localStorage));
expect(stored.includes('swiftuiweb.files/Documents/dailyScrumsKey'), 'the scrums file is not in localStorage: ' + JSON.stringify(stored));

// The detail screen from the card, then the meeting.
await tapText('Design review', 40);
shown = await settle(t => t.includes('Start Meeting'));
expect(shown.includes('Start Meeting') && shown.includes('Ada'), 'the detail screen did not open: ' + JSON.stringify(shown));

await tapText('Start Meeting');
shown = await settle(t => t.includes('Seconds Elapsed') && t.includes('Not authorized to recognize speech'));
expect(shown.includes('Seconds Elapsed') && shown.includes('Seconds Remaining'), 'the meeting screen did not open: ' + JSON.stringify(shown));
// The app's own alert for the speech it cannot get (the recogniser is unavailable in the
// browser; the host does not substitute one), dismissed with its OK.
expect(shown.includes('Not authorized to recognize speech'), 'the app did not present its speech alert: ' + JSON.stringify(shown));
await tap('OK');
shown = await settle(t => !t.includes('Not authorized to recognize speech'));
expect(!shown.includes('Not authorized to recognize speech'), 'the alert did not dismiss: ' + JSON.stringify(shown));
// The meeting itself is BLOCKED here: the app starts its timer only after
// `speechService.requestPermissions()` succeeds (MeetingScreen.startSpeechRecording), and speech
// is unavailable in the browser (pf-speech: no recogniser consumes the app's buffers yet), so
// the seconds stay at 0 — the app's own behaviour without speech, and the honest result, not a
// pass. The check below pins that down so a recogniser landing shows up as a change.
const elapsedAt = (t) => { const i = t.indexOf('Seconds Elapsed'); return i >= 0 ? t[i + 1] : null; };
await page.waitForTimeout(2500);
shown = await texts();
expect(elapsedAt(shown) === '0', 'the meeting timer ran without speech authorisation (did a recogniser get installed?): ' + JSON.stringify(shown));
expect(logs.some(l => l.includes('Not authorized to recognize speech') || l.includes('❌ Not authorized')), 'the SpeechService did not report the authorisation it was refused');

console.log(problems.length ? problems.join('\n') : 'scrumdinger: sheet, attendee, on file after reload, detail and the meeting screen OK; the meeting is blocked on speech (pf-speech), as the app behaves without it');
await browser.close();
process.exit(problems.length ? 1 : 0);
