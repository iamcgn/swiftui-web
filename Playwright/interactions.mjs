// The interaction suite: every gallery probe that drives the runtime the way a user does (taps,
// drags, typing, keys, menus, sheets, scrolling, hover, accessibility) run against one served
// gallery, each in its own process with its own browser. Each probe asserts and exits non-zero
// on a failure; this runner keeps going, writes report.json (one entry per probe: outcome,
// seconds, its PASS/FAIL lines) and exits non-zero if any probe failed or timed out.
//   node interactions.mjs <gallery url> [--out ../.build/interactions] [--only focus,menu]
import { spawn } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const url = args.find(a => !a.startsWith('--')) || 'http://127.0.0.1:8767/index.html';
const opt = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };
const out = resolve(here, opt('--out') || '../.build/interactions');
const only = opt('--only')?.split(',');

// [probe, what a user does in it]
const suite = [
  ['focus-probe', 'click a field, Tab to the next, a button moves focus, blur clears it'],
  ['textfield-probe', 'type into a text field, the binding follows, blur'],
  ['keyboard-probe', 'arrow keys pick list rows, key presses, shortcuts, Escape closes a sheet'],
  ['menu-probe', 'open a pull-down, run a row, a submenu, a split button, a context menu'],
  ['presentation-probe', 'a sheet, a popover, an alert, a pop-up picker'],
  ['toolbar-probe', "a toolbar's layout and its button's action"],
  ['gesture-probe', 'drag, long press, double tap, pinch'],
  ['hover-probe', 'hover, continuous hover, the pointer style, a help tooltip'],
  ['scroll-probe', 'wheel a scroll view, the indicator, back to the top'],
  ['wheel-probe', 'wheel a UIKit scroll view and chain the rest to SwiftUI'],
  ['text-selection-probe', 'drag to select text, copy it, a press clears it'],
  ['dragdrop-probe', 'drag and drop inside the app and across its boundary'],
  ['uikit-dragdrop-probe', "UIKit's drag and drop interactions"],
  ['colorpicker-probe', "the colour well opens the browser's picker and follows it"],
  ['accessibility-probe', 'ARIA roles and labels, a slider, a stepper by arrow keys'],
  ['uikit-accessibility-probe', "UIKit's accessibility elements, custom actions, announcements"],
  ['uikit-sheets-probe', 'share, document and photo pickers'],
  ['representable-hover-probe', "a UIKit view's hover recogniser and pointer interaction"],
  ['asyncimage-probe', 'AsyncImage loads a real image, a missing one fails'],
  ['animation-probe', 'an animated frame grows over time and settles'],
  ['timeline-probe', 'a periodic timeline ticks'],
  ['foundation-probe', "Foundation's time zones, locale and dates from the browser"],
].filter(([name]) => !only || only.includes(name.replace(/-probe$/, '')) || only.includes(name));

const run = (name) => new Promise(done => {
  const started = Date.now();
  const extra = name === 'scroll-probe' ? ['--out', join(out, 'scroll')] : [];
  // The Foundation probe reads the debug bridge once something has painted: any fixture will do.
  const target = name === 'foundation-probe' ? `${url}?fixture=${encodeURIComponent('textfield/steps')}` : url;
  const child = spawn(process.execPath, [join(here, `${name}.mjs`), target, ...extra], { cwd: here });
  let log = '';
  child.stdout.on('data', d => { log += d; });
  child.stderr.on('data', d => { log += d; });
  const timer = setTimeout(() => { log += '\n(timed out after 120 s)'; child.kill('SIGKILL'); }, 120000);
  child.on('close', code => {
    clearTimeout(timer);
    done({ outcome: code === 0 ? 'passed' : 'failed', exit: code, seconds: Math.round((Date.now() - started) / 100) / 10, log });
  });
});

mkdirSync(out, { recursive: true });
const report = { url, browser: 'chromium', probes: {} };
for (const [name, what] of suite) {
  const r = await run(name);
  report.probes[name] = { what, ...r, checks: r.log.split('\n').filter(l => /^(PASS|FAIL)\b/.test(l)) };
  console.log(`${r.outcome === 'passed' ? 'ok  ' : 'FAIL'} ${name} (${r.seconds} s) — ${what}`);
  if (r.outcome !== 'passed') console.log(r.log.split('\n').map(l => '    ' + l).join('\n'));
}
const failed = Object.entries(report.probes).filter(([, r]) => r.outcome !== 'passed').map(([n]) => n);
const checks = Object.values(report.probes).reduce((n, r) => n + r.checks.length, 0);
report.all_passed = failed.length === 0;
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
console.log(`${suite.length - failed.length}/${suite.length} probes passed, ${checks} checks${failed.length ? '; failed: ' + failed.join(', ') : ''}`);
process.exit(failed.length ? 1 : 0);
