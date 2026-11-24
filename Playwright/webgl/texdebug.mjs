// Why the Globe's text texture draws in Chromium and not in WebKit: counts toDataURL calls
// (UIImage.pngData), their time and size, image loads of data URLs and their outcome, and
// texImage2D calls, over 4 s of the Globe scene in each mode.
//   WEBGL_BROWSER=webkit node texdebug.mjs <url>
import { chromium, webkit, firefox } from 'playwright';
const url = process.argv[2];
const which = process.env.WEBGL_BROWSER || 'chromium';
const browser = await ({ chromium, webkit, firefox })[which].launch();
const ctx = await browser.newContext({ viewport: { width: 1000, height: 760 }, deviceScaleFactor: 2 });
for (const mode of ['gl', 'cpu']) {
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', m => logs.push(m.type() + ': ' + m.text().slice(0, 200)));
  page.on('pageerror', e => logs.push('pageerror: ' + String(e).slice(0, 200)));
  await page.addInitScript(() => {
    const T = window.__tex = { toDataURL: 0, ms: 0, len: 0, imgSet: 0, imgLoad: 0, imgError: 0, texImage: 0, texErr: 0, sizes: [] };
    const td = HTMLCanvasElement.prototype.toDataURL;
    HTMLCanvasElement.prototype.toDataURL = function (...a) { const t = performance.now(); const r = td.apply(this, a); T.ms += performance.now() - t; T.toDataURL++; T.len = r.length; T.sizes.push(this.width + 'x' + this.height); if (T.sizes.length > 5) T.sizes.shift(); return r; };
    const d = Object.getOwnPropertyDescriptor(HTMLImageElement.prototype, 'src');
    Object.defineProperty(HTMLImageElement.prototype, 'src', { configurable: true, get() { return d.get.call(this); }, set(v) {
      if (typeof v === 'string' && v.startsWith('data:image/png') && v.length > 100000) { T.imgSet++; this.addEventListener('load', () => T.imgLoad++); this.addEventListener('error', () => T.imgError++); }
      d.set.call(this, v); } });
    const ti = WebGL2RenderingContext.prototype.texImage2D;
    WebGL2RenderingContext.prototype.texImage2D = function (...a) { T.texImage++; try { return ti.apply(this, a); } catch (e) { T.texErr++; T.texErrMsg = String(e).slice(0, 200); throw e; } };
  });
  await page.goto(url + (mode === 'cpu' ? '?mesh=cpu' : ''), { waitUntil: 'commit' });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  await page.waitForTimeout(1000);
  const box = await page.locator('[role="radiogroup"]').first().boundingBox();
  await page.mouse.click(box.x + box.width * 2.5 / 3, box.y + box.height / 2);
  await page.waitForTimeout(500);
  const before = await page.evaluate(() => JSON.stringify(window.__tex));
  const f0 = await page.evaluate(() => window.__swiftuiwebDebug.frameCount());
  await page.waitForTimeout(4000);
  const after = await page.evaluate(() => JSON.stringify(Object.assign({}, window.__tex, { mesh: window.__swiftuiwebMesh && window.__swiftuiwebMesh.stats })));
  const f1 = await page.evaluate(() => window.__swiftuiwebDebug.frameCount());
  console.log(`${which} globe ${mode}: frames ${f1 - f0}\n  after click ${before}\n  after 4 s   ${after}\n  logs ${JSON.stringify(logs.slice(0, 8))}`);
  await page.close();
}
await browser.close();
