// Frameworks probe (sw-frameworks): the VideoPlayer and WebView fixtures put a `<video>` and
// an `<iframe>` over the canvas at their views' frames; the map draws OpenStreetMap tiles
// (skipped when the network is unavailable).
//   node frameworks-probe.mjs http://127.0.0.1:8767/index.html
import { chromium } from 'playwright';
const url = process.argv[2] || 'http://127.0.0.1:8767/index.html';
const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1000, height: 800 }, deviceScaleFactor: 2 });
page.on('pageerror', e => console.error('page error', e));
let failures = 0;
const check = (name, ok) => { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (!ok) failures++; };
const open = async (fixture) => {
  await page.goto(`${url}?fixture=${encodeURIComponent(fixture)}`);
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0);
  await page.waitForTimeout(200);
};
const probe = async (id) => page.evaluate((id) => (window.__galleryFrames || window.__swiftuiwebDebug.frames())[id], id);
const rect = async (selector) => page.evaluate((selector) => {
  const el = document.querySelector(selector);
  if (!el) return null;
  const r = el.getBoundingClientRect(), c = document.querySelector('canvas').getBoundingClientRect();
  return { x: r.left - c.left, y: r.top - c.top, width: r.width, height: r.height, src: el.getAttribute('src') || el.src, paused: el.paused, controls: el.controls };
}, selector);

await open('frameworks/video');
const player = await probe('player');
const video = await rect('video');
check('a <video> element exists over the canvas', !!video);
check('the video sits at the player\'s frame', !!video && !!player && Math.abs(video.x - player.x) < 1 && Math.abs(video.y - player.y) < 1 && Math.abs(video.width - player.width) < 1 && Math.abs(video.height - player.height) < 1);
check('the video has the player\'s source and controls', !!video && /clip\.mp4$/.test(video.src) && video.controls === true && video.paused === true);

await open('frameworks/web');
const web = await probe('web');
const frame = await rect('iframe');
check('an <iframe> element exists over the canvas', !!frame);
check('the frame sits at the web view\'s frame', !!frame && !!web && Math.abs(frame.x - web.x) < 1 && Math.abs(frame.y - web.y) < 1 && Math.abs(frame.width - web.width) < 1);
check('the frame loads the page\'s URL', !!frame && frame.src === 'about:blank');

await open('frameworks/map');
const map = await probe('map');
check('the map fills its frame', !!map && map.width === 288 && map.height === 184);
const marker = await page.evaluate(() => window.__swiftuiwebDebug.semantics().some(n => n.label === 'Ferry Building'));
check('the marker\'s title is in the semantics', marker);
const tiles = await page.waitForFunction(() => window.__swiftuiwebDebug.displayList().some(c => c.startsWith('drawImage')), null, { timeout: 10000 }).then(() => true).catch(() => false);
console.log(tiles ? 'INFO tiles drawn from tile.openstreetmap.org' : 'INFO no tiles drawn (offline?)');

await browser.close();
console.log(failures === 0 ? 'frameworks probe: all passed' : `frameworks probe: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
