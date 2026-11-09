// PomPadDo (Apps/upstream/pompaddo, unmodified; its iOS branches per decision 0025) in headless
// Chromium on a phone-sized page, built with the Objective-C runtime SDK (decision 0023): the
// tab bar (Tasks, Focus, Settings and the Add to Inbox tab), a task added from the Add to Inbox
// tab's sheet, the task in the Inbox list, the focus timer started from the Focus tab (its time
// counts down), and the task still in the Inbox after a reload (SwiftData through the host's
// store). All data is what the probe types.
//   node pompaddo-probe.mjs http://127.0.0.1:8783/index.html?platform=ios [--out ../.build/apps/pompaddo]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'pompaddo');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'PomPadDo', upstream: 'https://github.com/amikhaylin/pompaddo',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/pompaddo').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.3.3-RELEASE_wasm-objc', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null, steps: [],
};
const TASK = 'Water the plants';
const FLOWS = ['launch', 'add-to-inbox', 'inbox-lists-task', 'focus-timer', 'persists-after-reload'];
for (const f of FLOWS) report.flows[f] = { outcome: 'not-run' };
let current = null;
const begin = (name) => { current = name; report.flows[name] = { outcome: 'passed' }; };
const problems = report.problems;
const expect = (ok, message) => { if (!ok) { problems.push(message); if (current) report.flows[current] = { outcome: 'failed', detail: message }; } return ok; };
const note = (detail) => { if (current && report.flows[current].outcome === 'passed') report.flows[current].detail = detail; };

const browser = await chromium.launch();
report.browser = browser.version();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, hasTouch: true, isMobile: true });
await context.tracing.start({ screenshots: true, snapshots: false });
const page = await context.newPage();
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
// Chrome asks for a favicon the server has not got; any other console error is a problem.
page.on('console', m => { if (m.type() === 'error' && !/\/favicon\.ico$/.test((m.location() && m.location().url) || '')) problems.push('console: ' + m.text().slice(0, 300)); });
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { problems.push('screenshot ' + name + ': ' + e.message); } };
const list = () => page.evaluate(() => window.__swiftuiwebDebug.displayList());
const drawn = async () => (await list()).filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)".*? at ([-\d.]+),([-\d.]+)/);
  return m ? { text: m[1], x: +m[2], y: +m[3] } : { text: c.match(/"([^"]*)"/)?.[1] ?? c, x: 0, y: 0 };
});
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
// The overlay's controls (their labels and test ids: an app's accessibilityIdentifier).
const controls = () => page.evaluate(() => [...document.querySelectorAll('[aria-label], [data-testid]')].map(e => {
  const r = e.getBoundingClientRect();
  return { label: e.getAttribute('aria-label') || '', id: e.getAttribute('data-testid') || '', role: e.getAttribute('role') || e.tagName.toLowerCase(), x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
}).filter(b => b.width > 0 && b.height > 0 && b.label !== 'SwiftUI content'));
// What each step saw, for the report (and the log when a flow fails).
const record = async (step) => {
  const d = await drawn();
  report.steps.push({ step, texts: d.filter(t => t.y > 0 && t.y < 844).map(t => `${t.text}@${Math.round(t.x)},${Math.round(t.y)}`), controls: (await controls()).map(c => `${c.role}:${c.label}${c.id ? '#' + c.id : ''}@${c.x},${c.y}`) });
};
const tapAt = async (x, y) => { await page.touchscreen.tap(x, y); await page.waitForTimeout(250); };
const tapControl = async (match) => {
  const c = (await controls()).find(match);
  if (!c) return false;
  await tapAt(c.x + c.width / 2, c.y + c.height / 2);
  return true;
};
const tapText = async (text, dy = -6) => {
  const t = (await drawn()).find(d => d.text === text && d.y > 0 && d.y < 844);
  if (!t) return false;
  await tapAt(t.x + 8, t.y + dy);
  return true;
};
const byId = (id) => (c) => c.id === id;
const byLabel = (label) => (c) => c.label === label;
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(500);
};
// The Tasks tab's Inbox list: from the sidebar (Back first when a list is open).
const openInbox = async () => {
  let t = await texts();
  if (!t.includes('Inbox')) { await tapControl(byLabel('Back')); t = await settle(t => t.includes('Inbox'), 20); }
  if (!(await tapControl(byId('InboxNavButton')))) await tapText('Inbox');
  return settle(t => t.includes(TASK), 40);
};

try {
  begin('launch');
  await page.goto(url, { waitUntil: 'load', timeout: 180000 });
  await loaded();
  let t = await settle(t => ['Tasks', 'Focus', 'Settings'].every(s => t.includes(s)));
  await record('launch');
  await shot('01-launch');
  if (expect(['Tasks', 'Focus', 'Settings'].every(s => t.includes(s)), 'the tab bar did not show Tasks, Focus and Settings: ' + JSON.stringify(t))) note('tab bar: Tasks, Focus, Settings, Add to Inbox');

  begin('add-to-inbox');
  if (!(await tapControl(byLabel('Add to Inbox')))) await tapText('Add to Inbox');
  t = await settle(t => t.some(s => s.startsWith('Add task to')));
  await record('add sheet');
  await shot('02-add-sheet');
  if (expect(t.some(s => s.startsWith('Add task to')), 'the Add to Inbox tab did not open the new task sheet: ' + JSON.stringify(t))) {
    if (!(await tapControl(byId('TaskName')))) await tapControl(byLabel('Task name'));
    await page.waitForTimeout(200);
    await page.keyboard.type(TASK);
    t = await settle(t => t.includes(TASK));
    expect(t.includes(TASK), 'the task name was not typed: ' + JSON.stringify(t));
    await shot('03-typed');
    if (!(await tapControl(byId('SaveTask')))) await tapControl(byLabel('OK'));
    t = await settle(t => !t.some(s => s.startsWith('Add task to')));
    await record('after OK');
    if (expect(!t.some(s => s.startsWith('Add task to')), 'OK did not close the sheet: ' + JSON.stringify(t))) note(`"${TASK}" saved from the sheet`);
  }

  begin('inbox-lists-task');
  t = await openInbox();
  await record('inbox');
  await shot('04-inbox');
  if (expect(t.includes(TASK), `the Inbox did not list "${TASK}": ` + JSON.stringify(t))) note(`the Inbox lists "${TASK}"`);

  begin('focus-timer');
  if (!(await tapControl(byLabel('Focus')))) await tapText('Focus');
  const clock = s => /^\d{1,2}:\d{2}$/.test(s);
  t = await settle(t => t.includes('Focus Timer') || t.filter(clock).length > 0);
  await record('focus');
  const before = t.find(clock);
  if (expect(before, 'the Focus tab showed no time: ' + JSON.stringify(t))) {
    if (!(await tapControl(byId('StartTimerButton')))) await tapControl(byLabel('Start'));
    t = await settle(t => t.some(s => clock(s) && s !== before), 20);
    await page.waitForTimeout(1500);
    t = await texts();
    await record('timer running');
    await shot('05-timer');
    const after = t.find(s => clock(s) && s !== before);
    if (expect(after, `the time did not move from ${before} after Start: ` + JSON.stringify(t))) note(`${before} → ${after}`);
  }

  begin('persists-after-reload');
  await page.reload({ waitUntil: 'load' });
  await loaded();
  await settle(t => t.includes('Tasks'));
  t = await openInbox();
  await record('inbox after reload');
  await shot('06-reloaded');
  if (expect(t.includes(TASK), `after a reload the Inbox did not list "${TASK}": ` + JSON.stringify(t))) note('the task came back from the host store');
} catch (e) {
  problems.push('probe: ' + e.message);
  if (current) report.flows[current] = { outcome: 'failed', detail: e.message };
} finally {
  try { await record('end'); } catch {}
  try { await context.tracing.stop({ path: join(out, 'trace.zip') }); report.trace = 'trace.zip'; } catch {}
  await browser.close();
  report.full_app_pass = FLOWS.every(f => report.flows[f].outcome === 'passed') && problems.length === 0;
  report.finished = new Date().toISOString();
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
}
process.exit(report.full_app_pass ? 0 : 1);
