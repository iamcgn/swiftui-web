// Prints the WebGL2 renderer Chromium gets with the launch settings in WEBGL_CHANNEL and
// WEBGL_CHROME_ARGS, and whether Canvas2D is GPU-backed (chrome://gpu's feature status).
import { chromium } from 'playwright';
const browser = await chromium.launch({ channel: process.env.WEBGL_CHANNEL || undefined, args: (process.env.WEBGL_CHROME_ARGS || '').split(' ').filter(Boolean) });
const page = await browser.newPage();
const gl = await page.evaluate(() => { const c = document.createElement('canvas').getContext('webgl2'); if (!c) return 'no WebGL2';
  const d = c.getExtension('WEBGL_debug_renderer_info'); return (d ? c.getParameter(d.UNMASKED_RENDERER_WEBGL) : c.getParameter(c.RENDERER)); });
let canvas = 'unknown';
try { await page.goto('chrome://gpu', { timeout: 15000 }); await page.waitForTimeout(1500);
  const t = await page.evaluate(() => { const walk = n => (n.shadowRoot ? walk(n.shadowRoot) : '') + [...n.childNodes].map(c => c.nodeType === 3 ? c.textContent : walk(c)).join(' '); return walk(document.body); });
  const m = t.match(/Canvas:\s*([A-Za-z ,]+?)(?:\s{2}|Canvas out-of-process|Direct Rendering)/); canvas = m ? m[1].trim() : 'not found'; } catch (e) { canvas = 'chrome://gpu unreadable'; }
console.log(`${process.env.WEBGL_CHANNEL || 'default'} [${process.env.WEBGL_CHROME_ARGS || ''}]: WebGL2 ${gl}; Canvas2D ${canvas}`);
await browser.close();
