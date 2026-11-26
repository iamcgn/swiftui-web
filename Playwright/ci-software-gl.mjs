// Preloaded (NODE_OPTIONS=--import) by CI's browser job on the self-hosted laptop-sweep Mac:
// Chromium there gets SwiftShader's software GL, as GitHub's macOS runners have no GPU it will
// use. Without it the Mac's GPU turns the WebGL painter on (a second, overlay canvas) and the
// probes and goldens, written against the Canvas2D painter that hosted runners get, don't match.
// It acts only for this folder's scripts, and only when SWIFTUI_WEB_SOFTWARE_GL is 1.
import path from 'node:path';

const script = process.argv[1] ? path.resolve(process.argv[1]) : '';
if (process.env.SWIFTUI_WEB_SOFTWARE_GL === '1' && script.includes(`${path.sep}Playwright${path.sep}`)) {
  try {
    const { chromium } = await import('playwright');
    const flags = ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'];
    const withFlags = (options = {}) => ({ ...options, args: [...(options.args ?? []), ...flags] });
    const launch = chromium.launch.bind(chromium);
    const launchPersistentContext = chromium.launchPersistentContext.bind(chromium);
    chromium.launch = (options) => launch(withFlags(options));
    chromium.launchPersistentContext = (dir, options) => launchPersistentContext(dir, withFlags(options));
  } catch {
    // No Playwright here (a script run before npm install): nothing to change.
  }
}
