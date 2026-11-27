// Preloaded (node --import, through a shim on PATH) by CI's browser job on the self-hosted laptop-sweep Mac:
// Chromium there gets SwiftShader's software GL, as GitHub's macOS runners have no GPU it will
// use. Without it the Mac's GPU turns the WebGL painter on (a second, overlay canvas) and the
// probes and goldens, written against the Canvas2D painter that hosted runners get, don't match.
// It acts only for this folder's scripts, and only when SWIFTUI_WEB_SOFTWARE_GL is 1.
import path from 'node:path';

const script = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (process.env.SWIFTUI_WEB_SOFTWARE_GL === '1' && script.includes(`${path.sep}Playwright${path.sep}`)) {
  // Probes a runner starts with process.execPath (interactions.mjs) skip CI's node shim, so they
  // get this preload through NODE_OPTIONS, which children inherit.
  const own = `--import=${import.meta.url}`;
  if (!(process.env.NODE_OPTIONS ?? '').includes(own)) {
    process.env.NODE_OPTIONS = `${process.env.NODE_OPTIONS ?? ''} ${own}`.trim();
  }
  try {
    const { chromium } = await import('playwright');
    const flags = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'];
    // The WebGL probes pick their own launch through webgl-launch.mjs, which sets this: on a Mac
    // SwiftShader gives no WebGL2 at all, so forcing it there leaves them nothing to probe.
    const withFlags = (options = {}) => globalThis.__swiftuiwebOwnGL === true ? options
      : ({ ...options, args: [...(options.args ?? []), ...flags] });
    const launch = chromium.launch.bind(chromium);
    const launchPersistentContext = chromium.launchPersistentContext.bind(chromium);
    chromium.launch = (options) => launch(withFlags(options));
    chromium.launchPersistentContext = (dir, options) => launchPersistentContext(dir, withFlags(options));
  } catch {
    // No Playwright here (a script run before npm install): nothing to change.
  }
}
