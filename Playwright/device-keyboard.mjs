// The phone's own on-screen keyboard against the keyboard host (uk-app-delegate-adaptor): the
// Launches page on a real iPhone through safaridriver (Remote Automation on the phone,
// `safaridriver -p 4444` on the Mac, the page served on the LAN). The field is tapped, the
// keyboard rises, the visual viewport shrinks, and the page's "keyboard: N" line (the Countries
// handler's reading of keyboardFrameEndUserInfoKey) plus the scene's frame are read back; then
// the field is blurred and both must clear. This is the actual-device evidence the Chromium
// probe's synthetic readings are not.
//   node device-keyboard.mjs http://<mac-lan-ip>:8790/index.html --udid <udid> [--out ../.build/apps/keyboard]
import { mkdirSync, writeFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
const args = process.argv.slice(2);
const option = (name, fallback) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : fallback; };
const url = args.find(a => a.startsWith('http'));
const driver = option('--driver', 'http://127.0.0.1:4444');
const udid = option('--udid', process.env.DEVICE_UDID);
const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = option('--out', join(root, '.build', 'apps', 'keyboard'));
mkdirSync(out, { recursive: true });
if (!url) { console.error('usage: node device-keyboard.mjs <url> --udid <udid>'); process.exit(2); }
const request = async (method, path, body) => {
  const response = await fetch(driver + path, { method, headers: { 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const json = await response.json();
  if (json.value && json.value.error) throw new Error(`${method} ${path}: ${json.value.error}: ${json.value.message}`);
  return json.value;
};
const report = { url, udid: udid || null, started: new Date().toISOString(), device: null, steps: [], problems: [], outcome: null };
const note = (step, detail) => { report.steps.push({ step, ...detail }); console.log(step + ': ' + JSON.stringify(detail)); };
const problem = (text) => { report.problems.push(text); console.log('PROBLEM ' + text); };
const sleep = ms => new Promise(r => setTimeout(r, ms));
let id = null;
try {
  const alwaysMatch = { browserName: 'Safari' };
  if (udid) { alwaysMatch.platformName = 'iOS'; alwaysMatch['safari:deviceUDID'] = udid; }
  // `--simulator`: Safari in the iOS Simulator (its own software keyboard; evidence of the
  // simulator's WebKit, said so in the report, not the phone's).
  if (args.includes('--simulator')) alwaysMatch['safari:useSimulator'] = true;
  report.target = args.includes('--simulator') ? 'ios-simulator' : 'device';
  const session = await request('POST', '/session', { capabilities: { alwaysMatch } });
  id = session.sessionId;
  const run = (script, ...scriptArgs) => request('POST', `/session/${id}/execute/sync`, { script, args: scriptArgs });
  await request('POST', `/session/${id}/url`, { url });
  for (let i = 0; i < 600; i++) {
    if (await run('return !!(window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0)')) break;
    await sleep(250);
  }
  await sleep(1000);
  const shot = async (name) => { try { const png = await request('GET', `/session/${id}/screenshot`); writeFileSync(join(out, name + '.png'), Buffer.from(png, 'base64')); report.screenshots = [...(report.screenshots || []), name + '.png']; } catch (e) { problem('screenshot ' + name + ': ' + e.message); } };
  const state = () => run(`
    const t = window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]);
    const vv = window.visualViewport;
    const a = document.activeElement;
    return { line: t.find(x => x.startsWith('keyboard: ')) || null, frame: window.__swiftuiwebDebug.keyboardFrame(),
             innerHeight, visual: vv ? [vv.height, vv.offsetTop, vv.scale] : null, active: a ? a.tagName : null };`);
  report.device = await run('return { ua: navigator.userAgent, viewport: [innerWidth, innerHeight], dpr: devicePixelRatio, visualViewport: !!window.visualViewport }');
  const before = await state();
  note('before', before);
  await shot('01-before');
  if (before.line !== 'keyboard: 0') problem(`before the tap the line is "${before.line}"`);
  // The field's input element (the canvas overlay for the TextField): tapped with a touch, as
  // a finger would, so Safari raises its keyboard (a scripted focus() does not).
  // WebDriver's element click: safaridriver performs it as the user's tap (a touch action
  // sequence left the field unfocused in the simulator, 2026-10-13).
  const element = await request('POST', `/session/${id}/element`, { using: 'css selector', value: 'input[type=text]' });
  const ref = element['element-6066-11e4-a52e-4f735466cecf'];
  if (!ref) throw new Error('no text input element on the page');
  await request('POST', `/session/${id}/element/${ref}/click`, {});
  let up = null;
  for (let i = 0; i < 40; i++) { await sleep(250); up = await state(); if (up.line && up.line !== 'keyboard: 0') break; }
  note('after the tap', up);
  await shot('02-after-tap');
  const shown = up.line && up.line !== 'keyboard: 0';
  const focused = up.active === 'INPUT' || up.active === 'TEXTAREA';
  // The tap must have focused the field for the keyboard to be in question at all; when the
  // automation's tap does not (the iOS Simulator through safaridriver, 2026-10-13: element
  // click and a touch sequence both left BODY active while a scripted focus() worked), the
  // run proves nothing either way and says so.
  if (!focused) report.inconclusive = `the automation's tap did not focus the field (active ${up.active}); the keyboard was never asked for`;
  if (!shown && focused) problem(`after the tap the line is "${up.line}" (active ${up.active}, visual ${JSON.stringify(up.visual)} of ${up.innerHeight})`);
  if (shown) {
    const height = Number(up.line.slice('keyboard: '.length));
    const expected = Math.round(up.innerHeight - (up.visual[0] + up.visual[1]));
    if (Math.abs(height - expected) > 2) problem(`line says ${height}, the viewports say ${expected}`);
    if (up.frame !== `${up.innerHeight - height},${height}`) problem(`scene frame ${up.frame}, expected "${up.innerHeight - height},${height}"`);
  }
  // Blur: the keyboard goes, the line and the frame clear.
  await run('document.activeElement && document.activeElement.blur()');
  let down = null;
  for (let i = 0; i < 40; i++) { await sleep(250); down = await state(); if (down.line === 'keyboard: 0') break; }
  note('after the blur', down);
  await shot('03-after-blur');
  if (focused && (down.line !== 'keyboard: 0' || down.frame !== null)) problem(`after the blur the line is "${down.line}", frame ${down.frame}`);
  report.outcome = report.inconclusive ? 'inconclusive' : report.problems.length ? 'failed' : 'passed';
} catch (e) {
  problem('session: ' + e.message);
  report.outcome = report.problems.some(p => p.startsWith('session: ')) && report.steps.length === 0 ? 'unavailable' : 'failed';
} finally {
  if (id) { try { await request('DELETE', `/session/${id}`); } catch {} }
}
report.finished = new Date().toISOString();
writeFileSync(join(out, 'report.json'), JSON.stringify(report, null, 2));
console.log(`device keyboard: ${report.outcome} (${join(out, 'report.json')})`);
process.exit(report.outcome === 'passed' ? 0 : report.outcome === 'inconclusive' ? 3 : 1);
