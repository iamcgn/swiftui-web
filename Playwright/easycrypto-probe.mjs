// EasyCrypto (Apps/upstream/EasyCrypto, unmodified; decision 0021) in headless Chromium on a
// phone-sized page: the market list from CoinGecko's REST API (served by the probe from fixtures,
// so CI never meets the API's rate limit; the app's requests are recorded), a coin's detail
// pushed, the coin saved to the wish list through Core Data, the Whishlists tab listing it, the
// wish list back after a reload (the Core Data store through the host), a search typed into the
// search bar and its dropdown, and a searched coin's detail with its description.
//   node easycrypto-probe.mjs http://127.0.0.1:8785/index.html?platform=ios [--out ../.build/apps/easycrypto]
import { chromium } from 'playwright';
import { mkdirSync, writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const url = process.argv[2];
const outIndex = process.argv.indexOf('--out');
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = outIndex > 0 ? process.argv[outIndex + 1] : join(root, '.build', 'apps', 'easycrypto');
mkdirSync(out, { recursive: true });
const git = (args) => { try { return execSync(`git ${args}`, { cwd: root, encoding: 'utf8' }).trim(); } catch { return 'unknown'; } };
const dirty = git('status --porcelain --untracked-files=normal').split('\n').filter(Boolean);
const report = {
  app: 'EasyCrypto', upstream: 'https://github.com/mehrankmlf/EasyCrypto',
  tested_commit: git('rev-parse HEAD'), working_tree: dirty.length ? `dirty: ${dirty.length} path(s) differ from the commit` : 'clean',
  app_pinned_revision: git('ls-files --stage Apps/upstream/EasyCrypto').split(/\s+/)[1] || 'unknown',
  sdk: 'swift-6.3.3-RELEASE_wasm-objc', browser: null, url, started: new Date().toISOString(),
  full_app_pass: false, flows: {}, problems: [], screenshots: [], trace: null, requests: [], steps: [],
};
const FLOWS = ['launch', 'market-list', 'coin-detail', 'save-to-wishlist', 'wishlist-tab', 'persists-after-reload', 'search', 'search-detail'];
for (const f of FLOWS) report.flows[f] = { outcome: 'not-run' };

// The fixtures: made-up market data in CoinGecko's shapes (the app's Decodable entities).
const IMG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==', 'base64');
const icon = (n) => `https://assets.coingecko.com/coins/images/${n}/large/coin.png`;
const market = (rank, id, symbol, name, price, change) => ({
  id, symbol, name, image: icon(rank), current_price: price, market_cap: Math.round(price * 1e7 / rank), market_cap_rank: rank,
  total_volume: price * 1e5, high_24h: price * 1.02, low_24h: price * 0.97, price_change_24h: price * change / 100,
  price_change_percentage_24h: change, market_cap_change_24h: price * 1e5 * change, market_cap_change_percentage_24h: change,
  circulating_supply: 19000000, total_supply: 21000000, max_supply: 21000000,
});
const MARKETS = [
  market(1, 'bitcoin', 'btc', 'Bitcoin', 64250.5, 2.41),
  market(2, 'ethereum', 'eth', 'Ethereum', 3120.25, -1.37),
  market(3, 'tether', 'usdt', 'Tether', 1.0, 0.01),
  market(4, 'solana', 'sol', 'Solana', 142.8, 5.62),
];
const SEARCH = { coins: [
  { id: 'zcoin', name: 'Firo', api_symbol: 'zcoin', symbol: 'FIRO', market_cap_rank: 596, large: icon(479) },
  { id: 'firmachain', name: 'FirmaChain', api_symbol: 'firmachain', symbol: 'FCT', market_cap_rank: 1210, large: icon(480) },
] };
const DESCRIPTION = 'Firo is a privacy coin made up for this probe.';
const COIN = { id: 'zcoin', symbol: 'firo', name: 'Firo', description: { en: DESCRIPTION }, links: { homepage: ['https://firo.org/'] },
  image: { large: icon(479) }, market_cap_rank: 596, coingecko_rank: 433 };
const api = (u) => {
  const p = new URL(u);
  if (p.pathname.endsWith('/coins/markets')) return (p.searchParams.get('page') || '1') === '1' ? MARKETS : [];
  if (p.pathname.endsWith('/search')) return /^fir/i.test(p.searchParams.get('query') || '') ? SEARCH : { coins: [] };
  if (p.pathname.endsWith('/coins/zcoin')) return COIN;
  return null;
};
const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' };

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
}).filter(d => d.y > 0 && d.y < 844);
const texts = async () => (await drawn()).map(d => d.text);
const settle = async (ready, tries = 60) => { let t = await texts(); for (let i = 0; i < tries && !ready(t); i++) { await page.waitForTimeout(250); t = await texts(); } return t; };
const count = (t, s) => t.filter(x => x === s).length;
// The overlay's controls (their labels and test ids).
const controls = () => page.evaluate(() => [...document.querySelectorAll('[aria-label], [data-testid]')].map(e => {
  const r = e.getBoundingClientRect();
  return { label: e.getAttribute('aria-label') || '', id: e.getAttribute('data-testid') || '', role: e.getAttribute('role') || e.tagName.toLowerCase(), x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
}).filter(b => b.width > 0 && b.height > 0 && b.label !== 'SwiftUI content'));
const record = async (step) => {
  report.steps.push({ step, texts: (await drawn()).map(t => `${t.text}@${Math.round(t.x)},${Math.round(t.y)}`), controls: (await controls()).map(c => `${c.role}:${c.label}${c.id ? '#' + c.id : ''}@${c.x},${c.y},${c.width}x${c.height}`) });
};
const tapAt = async (x, y) => { await page.touchscreen.tap(x, y); await page.waitForTimeout(250); };
const tapControl = async (match) => {
  const c = (await controls()).find(match);
  if (!c) return false;
  await tapAt(c.x + c.width / 2, c.y + c.height / 2);
  return true;
};
const tapText = async (text, dy = -6, dx = 8) => {
  const t = (await drawn()).find(d => d.text === text);
  if (!t) return false;
  await tapAt(t.x + dx, t.y + dy);
  return true;
};
const byLabel = (label) => (c) => c.label === label;
const loaded = async () => {
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(500);
};
const has = (t, s) => t.some(x => x === s);
const back = async () => { if (!(await tapControl(c => /^back$/i.test(c.label) || c.label === 'EasyCrypto' && c.role === 'button'))) await tapAt(24, 70); await page.waitForTimeout(600); };

await context.route('https://api.coingecko.com/**', route => {
  const u = route.request().url();
  if (route.request().method() === 'OPTIONS') return route.fulfill({ status: 204, headers: cors });
  const body = api(u);
  report.requests.push((body ? '' : 'unanswered ') + u.replace('https://api.coingecko.com', ''));
  return body ? route.fulfill({ status: 200, contentType: 'application/json', headers: cors, body: JSON.stringify(body) })
              : route.fulfill({ status: 404, contentType: 'application/json', headers: cors, body: '{"error":"not in the fixtures"}' });
});
await context.route('https://assets.coingecko.com/**', route => route.fulfill({ status: 200, contentType: 'image/png', headers: cors, body: IMG }));

try {
  begin('launch');
  await page.goto(url, { waitUntil: 'load', timeout: 180000 });
  await loaded();
  let t = await settle(t => has(t, 'EasyCrypto') && has(t, 'Coins'));
  await record('launch');
  await shot('01-launch');
  if (expect(has(t, 'EasyCrypto') && has(t, 'Coins') && has(t, 'Whishlists'), 'the main screen did not show its title and the Coins and Whishlists tabs: ' + JSON.stringify(t))) note('title EasyCrypto, Coins and Whishlists tabs, the search bar');

  begin('market-list');
  t = await settle(t => has(t, 'Bitcoin') && has(t, 'Ethereum'), 80);
  await record('markets');
  await shot('02-markets');
  if (expect(['Bitcoin', 'Ethereum', 'Tether'].every(n => has(t, n)), 'the market list did not show the fixture coins: ' + JSON.stringify(t) + ' requests ' + JSON.stringify(report.requests))) note('Bitcoin, Ethereum, Tether from /coins/markets');

  begin('coin-detail');
  await tapText('Ethereum');
  t = await settle(t => has(t, 'Global Rank'), 40);
  await record('detail');
  await shot('03-detail');
  if (expect(has(t, 'Global Rank') && has(t, 'Ethereum') && has(t, 'Market Cap'), 'tapping Ethereum did not push its detail: ' + JSON.stringify(t))) note('Ethereum detail: Global Rank, Market Cap');

  begin('save-to-wishlist');
  // The save button is the 20-point image at the right end of the Global Rank row.
  const rank = (await drawn()).find(d => d.text === 'Global Rank');
  const before = await list();
  if (expect(rank, 'no Global Rank row')) {
    const btn = (await controls()).find(c => c.role === 'button' && Math.abs(c.y + c.height / 2 - (rank.y - 6)) < 25 && c.x > 250);
    if (btn) await tapAt(btn.x + btn.width / 2, btn.y + btn.height / 2); else await tapAt(390 - 16 - 10, rank.y - 6);
    await page.waitForTimeout(800);
    const after = await list();
    await record('saved');
    await shot('04-saved');
    expect(JSON.stringify(before.filter(c => c.startsWith('drawImage'))) !== JSON.stringify(after.filter(c => c.startsWith('drawImage'))), 'the save button\'s image did not change after the tap');
    note('the save image switched');
  }

  begin('wishlist-tab');
  await back();
  t = await settle(t => has(t, 'Whishlists'), 20);
  await tapText('Whishlists');
  t = await settle(t => has(t, 'Ethereum') && !has(t, 'Bitcoin'), 40);
  await record('wishlist');
  await shot('05-wishlist');
  if (expect(has(t, 'Ethereum') && !has(t, 'Bitcoin'), 'the Whishlists tab did not list only Ethereum: ' + JSON.stringify(t))) note('Whishlists lists Ethereum alone');

  begin('persists-after-reload');
  await page.reload({ waitUntil: 'load' });
  await loaded();
  t = await settle(t => has(t, 'Whishlists') && has(t, 'Bitcoin'), 80);
  await tapText('Whishlists');
  t = await settle(t => has(t, 'Ethereum') && !has(t, 'Bitcoin'), 40);
  await record('reloaded');
  await shot('06-reloaded');
  if (expect(has(t, 'Ethereum') && !has(t, 'Bitcoin'), 'after a reload the wish list did not hold Ethereum: ' + JSON.stringify(t))) note('Ethereum back in Whishlists from the Core Data store');
  await tapText('Coins');
  await page.waitForTimeout(500);

  begin('search');
  if (!(await tapControl(c => ['input', 'textbox'].includes(c.role)))) await tapText('Search coins');
  await page.waitForTimeout(300);
  await page.keyboard.type('fir', { delay: 80 });
  t = await settle(t => has(t, 'Firo'), 60);
  await record('search');
  await shot('07-search');
  if (expect(has(t, 'Firo') && has(t, 'FirmaChain'), 'typing "fir" did not show Firo and FirmaChain in the dropdown: ' + JSON.stringify(t) + ' requests ' + JSON.stringify(report.requests))) note('"fir" → /search → Firo, FirmaChain');

  begin('search-detail');
  await tapText('Firo');
  t = await settle(t => t.some(x => x.includes('privacy coin')), 60);
  await record('coin');
  await shot('08-coin');
  if (expect(t.some(x => x.includes('privacy coin')) && has(t, 'Description'), 'tapping Firo did not show its description: ' + JSON.stringify(t))) note('Firo: Description from /coins/zcoin');
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
