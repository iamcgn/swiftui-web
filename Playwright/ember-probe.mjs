// Ember (Apps/upstream/ember-hackernews, unmodified; decision 0021) in headless Chromium, the
// flow a user takes against the live Hacker News API: the first-launch onboarding (a
// fullScreenCover, seven steps to "Start Reading"), the Top feed from
// hacker-news.firebaseio.com (its rows with rank, title, host, points and author), the feed
// chips (New replaces the rows), a story's discussion (its comments from the API, through the
// app's HTMLRenderer), the story saved from the bar and listed under Saved (the BookmarkStore's
// JSON file through FileManager → localStorage), a search on hn.algolia.com from the Search
// tab's searchable field, the Settings screen (its cache size through the byte-count format),
// and a reload that skips the onboarding (UserDefaults) and keeps the bookmark.
//   node ember-probe.mjs http://127.0.0.1:8779/index.html?platform=ios [--out ../.build/apps/ember]
// Evidence goes to --out whatever happens: report.json (the tested commit, the app's pinned
// revision, every flow's outcome, the problems, `full_app_pass`), the screenshots, a trace.
// The story favicons come from icons.duckduckgo.com, which sends no CORS header: the browser
// refuses them (the console says so for each) and the app shows its globe fallback — the app's
// own path for a failed favicon, counted in `favicons_refused`, not a problem of the run.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'ember');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'Ember', upstream: 'https://github.com/DatanoiseTV/ember-hackernews',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  working_tree_changes: dirty, app_pinned_revision: git('ls-files --stage Apps/upstream/ember-hackernews').split(/\s+/)[1] || 'unknown',
  browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], favicons_refused: 0, screenshots: [], trace: null,
  notes: ['Every flow talks to the live Hacker News API (hacker-news.firebaseio.com, hn.algolia.com): the titles and counts differ per run; the probe asserts shapes, not values.'],
};
let currentFlow = null;
const flow = (name, outcome, detail) => { report.flows[name] = { outcome, ...(detail ? { detail } : {}) }; };
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { report.problems.push('screenshot ' + name + ': ' + e.message); } };
const browser = await chromium.launch();
report.browser = browser.version();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
await context.tracing.start({ screenshots: true, snapshots: false });
const page = await context.newPage();
const problems = report.problems;
const isFavicon = (text) => /icons\.duckduckgo\.com/.test(text) || /could not load image https:\/\/icons\.duckduckgo\.com/.test(text);
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
page.on('console', m => {
  const text = m.text();
  if (m.type() !== 'error') return;
  if (isFavicon(text)) { report.favicons_refused++; return; }
  if (/net::ERR_FAILED|Failed to load resource/.test(text) && !/firebaseio|algolia/.test(text)) { report.favicons_refused++; return; }
  problems.push('console: ' + text.slice(0, 300));
});
// The painted texts, each with its font family and position.
const drawn = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)" (\S+) [\d.]+ w\d+ at ([-\d.]+),([-\d.]+)/);
  return m ? { text: m[1], font: m[2], x: +m[3], y: +m[4] } : { text: c.match(/"([^"]*)"/)?.[1] ?? c, font: '?', x: 0, y: 0 };
}));
const texts = async () => (await drawn()).map(d => d.text);
// A layout of the discussion's comment thread takes seconds (sw-perf: nested stacks), so
// each poll waits out a frame in flight.
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const expect = (condition, message) => { if (!condition) { problems.push(message); if (currentFlow) report.flows[currentFlow] = { outcome: 'failed', detail: message }; } };
const FLOWS = ['launch', 'onboarding', 'feed', 'feed-chips', 'story-detail', 'save-story', 'saved-list', 'search', 'settings', 'persists-after-reload'];
for (const f of FLOWS) flow(f, 'not-run');
const begin = (name) => { currentFlow = name; flow(name, 'passed'); };
const tapText = async (text, dx = 10, dy = -6) => {
  const hit = (await drawn()).find(d => d.text === text);
  if (!hit) { problems.push(`no painted text "${text}"`); return false; }
  await page.touchscreen.tap(hit.x + dx, hit.y + dy);
  return true;
};
const tap = async (label, which = 'first') => {
  const box = await page.locator(`[aria-label="${label}"]`)[which]().boundingBox();
  if (!box) { problems.push(`no element labelled "${label}"`); return false; }
  await page.touchscreen.tap(box.x + box.width / 2, box.y + box.height / 2);
  return true;
};
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(300);
};
// A story row: its rank, then a title, a host, points and an author (the texts between two ranks).
const rows = (t) => { const ranks = []; for (let i = 0; i < t.length; i++) if (/^\d+$/.test(t[i]) && +t[i] >= 1 && +t[i] <= 30 && (ranks.length === 0 || +t[i] === ranks[ranks.length - 1].rank + 1)) ranks.push({ rank: +t[i], index: i }); return ranks; };
const finish = async () => {
  report.finished = new Date().toISOString();
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch (e) { problems.push('trace: ' + e.message); }
  report.full_app_pass = Object.values(report.flows).every(f => f.outcome === 'passed') && problems.length === 0;
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ full_app_pass: report.full_app_pass, flows: report.flows, problems: report.problems, favicons_refused: report.favicons_refused }, null, 2));
  await browser.close();
  process.exit(report.full_app_pass ? 0 : 1);
};
process.on('uncaughtException', async (e) => { problems.push('uncaught: ' + e.message); if (currentFlow) flow(currentFlow, 'failed', e.message); await finish(); });
process.on('unhandledRejection', async (e) => { problems.push('unhandled: ' + (e && e.message || e)); if (currentFlow) flow(currentFlow, 'failed', String(e && e.message || e)); await finish(); });

begin('launch');
await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
await loaded();
let shown = await settle(t => t.includes('Welcome to Ember'));
expect(shown.includes('Welcome to Ember') && shown.includes('Continue'), 'the first launch did not present the onboarding cover: ' + JSON.stringify(shown.slice(0, 20)));
await shot('1-onboarding');

begin('onboarding');
let steps = 0;
for (let i = 0; i < 10; i++) {
  const t = await texts();
  const button = t.includes('Start Reading') ? 'Start Reading' : t.includes('Continue') ? 'Continue' : null;
  if (!button) break;
  await tapText(button);
  steps++;
  await page.waitForTimeout(500);
  if (button === 'Start Reading') break;
}
shown = await settle(t => !t.includes('Welcome to Ember') && !t.includes('Start Reading') && t.includes('Top'));
expect(steps === 7, `the onboarding took ${steps} taps, not 7`);
expect(!shown.includes('Continue') && shown.includes('Top') && shown.includes('New'), 'the feed did not appear after "Start Reading": ' + JSON.stringify(shown.slice(0, 20)));

begin('feed');
shown = await settle(t => rows(t).length >= 5, 100);
let feedRows = rows(shown);
expect(feedRows.length >= 5, 'fewer than five story rows after the Top feed loaded: ' + JSON.stringify(shown.slice(0, 30)));
const firstTitle = feedRows.length > 1 ? shown.slice(feedRows[0].index + 1, feedRows[1].index).find(s => s.length > 8) : null;
expect(!!firstTitle, 'the first row has no title text');
const detail = await drawn();
const titleFont = detail.find(d => d.text === firstTitle)?.font;
expect(titleFont === 'Inter', `the story title is drawn in ${titleFont}, not the app's Inter (the bundled font through Font.custom)`);
expect(shown.some(s => /^\d+[hmd]$/.test(s)), 'no relative age ("3h") in the rows');
expect(shown.includes('Stories') && shown.includes('Search') && shown.includes('Saved') && shown.includes('Settings'), 'the tab bar does not list the four tabs');
await shot('2-feed');

begin('feed-chips');
await tapText('New', 0, 0);
shown = await settle(t => { const r = rows(t); return r.length >= 3 && t.slice(r[0].index + 1, r[1]?.index ?? t.length).find(s => s.length > 8) !== firstTitle; }, 100);
feedRows = rows(shown);
const newTitle = feedRows.length > 1 ? shown.slice(feedRows[0].index + 1, feedRows[1].index).find(s => s.length > 8) : null;
expect(feedRows.length >= 3 && newTitle && newTitle !== firstTitle, 'the New chip did not replace the rows: ' + JSON.stringify(shown.slice(0, 24)));
await shot('3-new-feed');
await tapText('Top', 0, 0);
shown = await settle(t => { const r = rows(t); return r.length >= 3 && t.slice(r[0].index + 1, r[1]?.index ?? t.length).find(s => s.length > 8) === firstTitle; }, 100);
feedRows = rows(shown);

begin('story-detail');
const openTitle = shown.slice(feedRows[0].index + 1, feedRows[1].index).find(s => s.length > 8);
await tapText(openTitle, 40, 4);
shown = await settle(t => !t.includes('Top') && t.length > 12, 120);
await page.waitForTimeout(1500);
shown = await texts();
expect(shown.some(s => s.startsWith(openTitle.slice(0, 12))), 'the discussion did not show the story title: ' + JSON.stringify(shown.slice(0, 20)));
expect(await page.locator('[aria-label="Save story"]').count() > 0, 'the discussion bar has no Save button (an icon button, by its accessibility label)');
expect(shown.includes('Comments') || shown.some(s => /^\d+$/.test(s)), 'the discussion did not show its comments header: ' + JSON.stringify(shown.slice(0, 20)));
await shot('4-discussion');

begin('save-story');
await tap('Save story');
let removeCount = 0;
for (let i = 0; i < 20 && removeCount === 0; i++) { await page.waitForTimeout(250); removeCount = await page.locator('[aria-label="Remove"]').count(); }
expect(removeCount > 0, 'the save button did not turn into Remove (its accessibility label after the toggle)');
await shot('5-saved');
await tap('Back');
shown = await settle(t => t.includes('Top') && rows(t).length >= 3, 60);

begin('saved-list');
await tapText('Saved', 0, -10);
shown = await settle(t => t.includes('Saved') && t.some(s => s.startsWith(openTitle.slice(0, 12))), 60);
expect(shown.some(s => s.startsWith(openTitle.slice(0, 12))), 'the Saved tab does not list the saved story: ' + JSON.stringify(shown.slice(0, 20)));
await shot('6-saved-list');

begin('search');
await tapText('Search', 0, -10);
shown = await settle(t => t.includes('Search stories and discussions') || t.includes('Search'), 60);
const field = await page.locator('input[type="search"], input[type="text"], [role="searchbox"]').first().boundingBox().catch(() => null);
if (field) await page.touchscreen.tap(field.x + field.width / 2, field.y + field.height / 2);
else await tapText('Search stories and discussions', 20, 0);
await page.waitForTimeout(300);
await page.keyboard.type('swift');
await page.keyboard.press('Enter');
shown = await settle(t => t.includes('swift') && rows(t).length === 0 && t.filter(s => s.length > 12).length >= 4, 120);
expect(shown.includes('swift'), 'the query was not typed into the search field');
expect(shown.filter(s => s.length > 12).length >= 4, 'no search results arrived from hn.algolia.com: ' + JSON.stringify(shown.slice(0, 24)));
await shot('7-search');

begin('settings');
await tapText('Settings', 0, -10);
shown = await settle(t => t.includes('Appearance') && t.includes('Reading'), 60);
expect(shown.includes('Appearance') && shown.includes('Reading') && shown.includes('Default Feed'), 'the Settings screen did not show its sections: ' + JSON.stringify(shown.slice(0, 30)));
await shot('8-settings');
// The Data section is below the fold: scroll the list to it.
for (let i = 0; i < 6 && !(await texts()).includes('Offline Cache'); i++) { await page.mouse.move(195, 500); await page.mouse.wheel(0, 400); await page.waitForTimeout(300); }
shown = await settle(t => t.includes('Offline Cache'), 20);
expect(shown.includes('Offline Cache'), 'the Data section did not scroll into view: ' + JSON.stringify(shown.slice(0, 30)));
expect(shown.some(s => /^(Zero KB|[\d.,]+ (bytes|KB|MB))$/.test(s)), 'the cache size is not a byte count: ' + JSON.stringify(shown.filter(s => /KB|MB|bytes/.test(s))));
await shot('8b-settings-data');

begin('persists-after-reload');
await page.reload({ waitUntil: 'commit' });
await loaded();
shown = await settle(t => t.includes('Top') && rows(t).length >= 3, 100);
expect(!shown.includes('Welcome to Ember'), 'the onboarding came back after a reload (UserDefaults not kept)');
await tapText('Saved', 0, -10);
shown = await settle(t => t.some(s => s.startsWith(openTitle.slice(0, 12))), 60);
expect(shown.some(s => s.startsWith(openTitle.slice(0, 12))), 'the bookmark did not survive a reload: ' + JSON.stringify(shown.slice(0, 20)));
await shot('9-after-reload');
await finish();
