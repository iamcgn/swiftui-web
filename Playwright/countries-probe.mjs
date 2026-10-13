// Countries (Apps/upstream/clean-architecture-swiftui, unmodified; decision 0021) in headless
// Chromium, the flow a user takes: the app launches to its countries list, which loads from its
// web repository (https://restcountries.com/v2, the app's own constant) into its SwiftData
// container (pf-swiftdata) and shows the list — or, as that endpoint stands (pf-urlsession:
// a 301 to a deprecation notice with no CORS header), the app's own ErrorView with Retry, which
// is what the app does on a device when its service is gone. Nothing is stubbed or injected:
// no fixture data, no proxy, no rewritten endpoint. The probe records which of the two the app
// reached and what the error view said; the list, search and detail flows run only when the
// list is there, and `full_app_pass` stays false until every flow has passed.
//   node countries-probe.mjs http://127.0.0.1:8774/index.html?platform=ios [--out ../.build/apps/countries]
// Evidence goes to --out whatever happens: report.json (the tested commit, the app's pinned
// revision, every flow's outcome — passed / failed / blocked / not-run — the problems), the
// screenshots, a Playwright trace.
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'countries');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const report = {
  app: 'Countries (clean-architecture-swiftui)', upstream: 'https://github.com/nalexn/clean-architecture-swiftui',
  tested_commit: git('rev-parse HEAD'), app_pinned_revision: git('ls-files --stage Apps/upstream/clean-architecture-swiftui').split(/\s+/)[1] || 'unknown',
  browser: null, url, started: new Date().toISOString(),
  full_app_pass: false,
  endpoint: { url: 'https://restcountries.com/v2/all', outcome: null },
  flows: {}, problems: [], screenshots: [], trace: null,
  notes: ['The app loads its list from restcountries.com/v2, which answers with a 301 to a deprecation notice and no CORS header (verified 2026-10-12, pf-urlsession): from the page the fetch fails and the app shows its own ErrorView. That is the app\'s real path for a gone service, recorded here, not a pass; no fixture, proxy or endpoint rewrite is used. The list, search and detail flows are blocked on the external service.'],
};
let currentFlow = null;
const flow = (name, outcome, detail) => { report.flows[name] = { outcome, ...(detail ? { detail } : {}) }; };
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { report.problems.push('screenshot ' + name + ': ' + e.message); } };
const browser = await chromium.launch();
report.browser = browser.version();
const context = await browser.newContext({ viewport: { width: 375, height: 667 }, hasTouch: true, isMobile: true });
await context.tracing.start({ screenshots: true, snapshots: false });
const page = await context.newPage();
const problems = report.problems;
const requests = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
// The failed fetch of the deprecated endpoint is the one console error the app provokes; any other counts.
page.on('console', m => { if (m.type() === 'error' && !/restcountries\.com/.test(m.text() + ' ' + (m.location().url || ''))) problems.push('console: ' + m.text()); });
page.on('requestfailed', r => requests.push({ url: r.url(), failure: r.failure()?.errorText }));
page.on('response', r => { if (/restcountries\.com/.test(r.url())) requests.push({ url: r.url(), status: r.status() }); });
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
const settle = async (ready, tries = 50) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(100); t = await texts(); } return t; };
const expect = (condition, message) => { if (!condition) { problems.push(message); if (currentFlow) report.flows[currentFlow] = { outcome: 'failed', detail: message }; } };
const FLOWS = ['launch', 'model-container', 'countries-request', 'error-view-retry', 'countries-list', 'search', 'country-detail'];
for (const f of FLOWS) flow(f, 'not-run');
const begin = (name) => { currentFlow = name; flow(name, 'passed'); };
const tapText = async (text) => {
  const at = await page.evaluate((text) => { const op = window.__swiftuiwebDebug.displayList().find(c => c.startsWith(`drawText("${text}"`)); const m = op && op.match(/at ([\d.]+),([\d.]+)/); return m ? { x: +m[1], y: +m[2] } : null; }, text);
  if (!at) { problems.push(`no text "${text}" to tap`); return; }
  await page.mouse.click(at.x + 20, at.y - 8);
};
try {
  begin('launch');
  await page.goto(url, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  let t = await settle(t => t.includes('Countries'));
  expect(t.includes('Countries'), 'launch: the navigation title "Countries" is not painted: ' + JSON.stringify(t));
  await shot('01-launch');

  // The app's persistent ModelContainer opened (pf-swiftdata, over localStorage): the app
  // paints "There is an issue with local database" under its list when `appModelContainer()`
  // threw and it fell back to its in-memory stub — that footer must be absent.
  begin('model-container');
  const stubFooter = t.find(x => x.includes('issue with local database'));
  expect(!stubFooter, 'model-container: the app fell back to its stub container: "' + stubFooter + '"');

  // The request to the app's endpoint: the list, or the app's error view. Either is a terminal
  // state the app reaches on its own; which one is the external service's doing.
  begin('countries-request');
  t = await settle(t => t.includes('An Error Occured') || t.includes('Retry') || t.some(x => /^[A-Z][a-z]+$/.test(x) && x !== 'Countries' && x !== 'Retry'), 300);
  const errored = t.includes('An Error Occured');
  const errorText = errored ? t.slice(t.indexOf('An Error Occured') + 1, t.indexOf('Retry')).join(' ') : null;
  report.endpoint.outcome = errored ? 'failed: ' + errorText : 'answered: the list is painted';
  report.endpoint.requests = requests;
  await shot('02-after-request');
  if (errored) {
    expect(t.includes('Retry'), 'countries-request: the error view has no Retry: ' + JSON.stringify(t));
    flow('countries-request', 'blocked', 'the app\'s ErrorView: "' + errorText + '" — restcountries.com/v2 is deprecated and refuses the page (no CORS header); an external service, not the app or the framework');
    // Retry runs the same request again and lands on the same view: the app's own loop, intact.
    begin('error-view-retry');
    await tapText('Retry');
    t = await settle(t => !t.includes('An Error Occured'), 10);
    t = await settle(t => t.includes('An Error Occured'), 300);
    expect(t.includes('An Error Occured') && t.includes('Retry'), 'error-view-retry: after Retry the view is ' + JSON.stringify(t));
    await shot('03-after-retry');
    for (const f of ['countries-list', 'search', 'country-detail']) flow(f, 'blocked', 'needs the list the external service no longer serves');
  } else {
    // The service answered: the list is the app's; the flows below are what a pass needs and
    // are not written until the list can be seen (they would be guessed from a painted state).
    for (const f of ['error-view-retry']) flow(f, 'not-run', 'the service answered; no error view');
    for (const f of ['countries-list', 'search', 'country-detail']) flow(f, 'not-run', 'the list appeared; its flows are not scripted yet');
  }
} catch (e) {
  problems.push('probe: ' + e.message);
  if (currentFlow && report.flows[currentFlow]?.outcome === 'passed') report.flows[currentFlow] = { outcome: 'failed', detail: e.message };
  await shot('99-at-failure');
}
report.trace = 'trace.zip';
try { await context.tracing.stop({ path: join(out, 'trace.zip') }); } catch (e) { problems.push('trace: ' + e.message); report.trace = null; }
report.finished = new Date().toISOString();
report.full_app_pass = false;   // blocked or unscripted flows remain; see the notes
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
await browser.close();
console.log(Object.entries(report.flows).map(([k, v]) => `${k}: ${v.outcome}`).join(' | '));
console.log('endpoint: ' + report.endpoint.outcome);
console.log(problems.length ? problems.join('\n') : 'countries: the app reached its own terminal state; full_app_pass=false (see ' + join(out, 'report.json') + ')');
process.exit(problems.length ? 1 : 0);
