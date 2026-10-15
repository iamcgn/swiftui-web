// SwiftUI-2048 (Apps/upstream/SwiftUI-2048, unmodified; decision 0021) in headless Chromium,
// built with the Objective-C runtime SDK (decision 0023): the app's `@UIApplicationMain`
// delegate launches, the board shows its two starting tiles, swipes move them, and ⌘N — the
// delegate's `UIKeyCommand(input: "N", modifierFlags: .command, action: #selector(newGame(_:)))`
// from `buildMenu(with:)`, sent down the responder chain as a selector — starts a new game.
//   node 2048-probe.mjs http://127.0.0.1:8775/index.html?platform=ios [--out ../.build/apps/2048]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', '2048');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'SwiftUI-2048', upstream: 'https://github.com/unixzii/SwiftUI-2048',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/SwiftUI-2048').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.3.3-RELEASE_wasm-objc', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null,
};
const flow = (name, outcome, detail) => { report.flows[name] = { outcome, ...(detail ? { detail } : {}) }; };
const browser = await chromium.launch();
report.browser = browser.version();
const context = await browser.newContext({ viewport: { width: 375, height: 667 }, hasTouch: true, isMobile: true });
await context.tracing.start({ screenshots: true, snapshots: false });
const page = await context.newPage();
const problems = report.problems;
page.on('pageerror', e => problems.push('pageerror: ' + e.message + ' ' + (e.stack || '').split('\n').slice(1, 6).join(' <- ')));
page.on('console', m => { if (m.type() === 'error') problems.push('console: ' + m.text() + ' @ ' + (m.location().url || '?')); });
const shot = async (name) => { const file = join(out, name + '.png'); try { await page.screenshot({ path: file }); report.screenshots.push(name + '.png'); } catch (e) { problems.push('screenshot ' + name + ': ' + e.message); } };
// The drawn texts, with the position of each (drawText("…", x, y, …) in the display list).
const drawn = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => {
  const m = c.match(/^drawText\("([^"]*)"(?:,\s*([-\d.]+),\s*([-\d.]+))?/); return { text: m ? m[1] : c, x: m && m[2] ? +m[2] : null, y: m && m[3] ? +m[3] : null };
}));
const tiles = (d) => d.filter(t => /^\d+$/.test(t.text) && t.text !== '2048');
const settle = async (ready, tries = 60) => { let d = await drawn(); for (let i = 0; i < tries && !ready(d); i++) { await page.waitForTimeout(100); d = await drawn(); } return d; };
const key = (t) => t.map(x => `${x.text}@${Math.round(x.x)},${Math.round(x.y)}`).sort().join(' ');
try {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  let d = await settle(d => d.some(t => t.text === '2048') && tiles(d).length >= 2);
  const start = tiles(d);
  await shot('01-launch');
  if (d.some(t => t.text === '2048') && start.length >= 2) flow('launch', 'passed', `title and ${start.length} starting tile(s): ${start.map(t => t.text).join(', ')}`);
  else { flow('launch', 'failed', `texts: ${d.map(t => t.text).join(' | ')}`); throw new Error('launch'); }

  // Swipes across the board (the tiles' bounding box) in four directions: each move adds a tile.
  const box = () => { const t = tiles(start.length ? start : []); return t; };
  const xs = start.map(t => t.x), ys = start.map(t => t.y);
  const cx = 187, cy = (Math.min(...ys) + Math.max(...ys)) / 2 || 400;
  const swipe = async (dx, dy) => { await page.mouse.move(cx, cy); await page.mouse.down(); for (let i = 1; i <= 8; i++) { await page.mouse.move(cx + dx * i / 8, cy + dy * i / 8); } await page.mouse.up(); await page.waitForTimeout(400); };
  const before = key(start);
  await swipe(-120, 0); await swipe(0, 120); await swipe(120, 0); await swipe(0, -120);
  d = await settle(d => key(tiles(d)) !== before, 20);
  const moved = tiles(d);
  await shot('02-after-swipes');
  if (key(moved) !== before) flow('swipes move the tiles', 'passed', `${moved.length} tile(s) after four swipes`);
  else flow('swipes move the tiles', 'failed', 'the board did not change after four swipes');

  // ⌘N: the delegate's key command through the main menu (buildMenu) and the responder chain.
  const beforeNew = key(tiles(d));
  await page.keyboard.press('Meta+n');
  d = await settle(d => key(tiles(d)) !== beforeNew && tiles(d).length === 2, 30);
  const fresh = tiles(d);
  await shot('03-after-command-n');
  if (key(fresh) !== beforeNew && fresh.length === 2) flow('⌘N starts a new game', 'passed', `${fresh.length} tile(s): ${fresh.map(t => t.text).join(', ')}`);
  else flow('⌘N starts a new game', 'failed', `${fresh.length} tile(s) after ⌘N; changed: ${key(fresh) !== beforeNew}`);
  report.full_app_pass = Object.values(report.flows).every(f => f.outcome === 'passed') && problems.length === 0;
} catch (e) {
  problems.push('probe: ' + e.message);
} finally {
  const trace = join(out, 'trace.zip');
  try { await context.tracing.stop({ path: trace }); report.trace = 'trace.zip'; } catch {}
  await browser.close();
  report.finished = new Date().toISOString();
  writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ full_app_pass: report.full_app_pass, flows: report.flows, problems: report.problems }, null, 2));
}
process.exit(report.full_app_pass ? 0 : 1);
