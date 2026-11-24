// Finds Chromium launch options that give the page WebGL2 on this machine, for the WebGL probes.
// CI's hosted Mac VMs have no GPU of their own, and which mode gives WebGL there (old headless,
// new headless, a window, SwiftShader) differs between Chromium builds, so try each in turn and
// log what each gave. Returns { headless, args, renderer }, or throws with the table.
import { chromium } from 'playwright';

const SWIFTSHADER = ['--enable-unsafe-swiftshader', '--use-angle=swiftshader'];
const CANDIDATES = [
  { name: 'headless, SwiftShader', headless: true, args: SWIFTSHADER },
  { name: 'headless, ANGLE SwiftShader WebGL', headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader-webgl', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] },
  { name: 'new headless, SwiftShader', headless: false, args: ['--headless=new', ...SWIFTSHADER] },
  { name: 'new headless, GPU', headless: false, args: ['--headless=new', '--ignore-gpu-blocklist'] },
  { name: 'window, GPU', headless: false, args: ['--ignore-gpu-blocklist'] },
  { name: 'window, SwiftShader', headless: false, args: SWIFTSHADER },
];

async function tryOne(c) {
  let browser;
  try {
    browser = await chromium.launch({ headless: c.headless, args: c.args, timeout: 30000 });
    const page = await browser.newPage();
    await page.setContent('<canvas></canvas>');
    return await page.evaluate(() => {
      const gl = document.querySelector('canvas').getContext('webgl2');
      if (!gl) return { ok: false, why: 'no WebGL2 context' };
      const info = gl.getExtension('WEBGL_debug_renderer_info');
      return { ok: true, renderer: String(info ? gl.getParameter(info.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER)) };
    });
  } catch (e) {
    return { ok: false, why: String(e).split('\n')[0].slice(0, 200) };
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
}

export async function webglLaunch() {
  const rows = [];
  for (const c of CANDIDATES) {
    const r = await tryOne(c);
    rows.push(`  ${r.ok ? 'WebGL2' : 'none  '}  ${c.name}: ${r.ok ? r.renderer : r.why}`);
    if (r.ok) {
      console.log('WebGL launch options tried:\n' + rows.join('\n'));
      return { headless: c.headless, args: c.args, renderer: r.renderer, name: c.name };
    }
  }
  throw new Error('no launch mode gives WebGL2 here:\n' + rows.join('\n'));
}
