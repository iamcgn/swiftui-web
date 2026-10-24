// The Speech framework end to end (decision 0022, pf-speech): Examples/Launches' SpeechCheck
// drives SFSpeechRecognizer as an app does — authorisation, an SFSpeechAudioBufferRecognitionRequest
// fed AVAudioPCMBuffers decoded from a committed recording, endAudio — and the host transcribes
// them on the device through Chrome's on-device SpeechRecognition (`processLocally`), fed by a
// worklet track. No microphone, no fake-device flag, no service: the only network traffic is the
// locale's language pack, downloaded from Google once into the persistent profile below
// (`available()` → "downloadable" → `install()`; 219 MB on disk; minutes the first time).
//
// Six runs, each a page load: the two synthetic fixtures (macOS `say`, 16 kHz: "one two three
// four five", "red green blue yellow" — the recogniser writes the numerals as digits) must come
// back as their own words and not the other's; the 48 kHz copy of the first proves the host's
// resampling; silence (two seconds of zeros) and nothing (endAudio alone) leave an empty final;
// a cancel at the first partial result leaves no final. Every transcript must appear only after
// the frames were appended (the line carries both timestamps).
//
// The browser is the installed Google Chrome (Playwright's `channel: 'chrome'`; the bundled
// Chromium lacks on-device recognition) WITH ITS SANDBOX ON: Playwright passes --no-sandbox
// by default, and under it Chrome's recogniser runs and never answers (decision 0022, results).
//   node speech-probe.mjs http://127.0.0.1:8769/index.html [profileDir]
import { chromium } from 'playwright';
import path from 'node:path';
import fs from 'node:fs';
const url = process.argv[2];
const profile = process.argv[3] || path.join(process.cwd(), '.speech-profile');
fs.mkdirSync(profile, { recursive: true });
const context = await chromium.launchPersistentContext(profile, {
  channel: 'chrome', chromiumSandbox: true, headless: true, viewport: { width: 500, height: 400 },
  args: ['--autoplay-policy=no-user-gesture-required'],
});
const page = context.pages()[0] || await context.newPage();
const problems = [];
page.on('pageerror', e => problems.push('pageerror: ' + e.message));
// The network check's deliberate 404 (`/fixtures/missing.json`) and Chrome's own favicon request are matched by location; any other console error is a problem.
page.on('console', m => { if (m.type() === 'error' && !/\/fixtures\/missing\.json$|\/favicon\.ico$/.test((m.location() && m.location().url) || '')) problems.push('console: ' + m.text() + ' @ ' + ((m.location() && m.location().url) || '')); });
const texts = () => page.evaluate(() => window.__swiftuiwebDebug.displayList().filter(c => c.startsWith('drawText')).map(c => c.match(/"([^"]*)"/)[1]));
const speechLine = async () => { const t = await texts(); const start = t.findIndex(x => x.startsWith('speech: ')); if (start < 0) return ''; const parts = []; for (let i = start; i < t.length && t[i] !== 'Record again'; i++) parts.push(t[i]); return parts.join(' '); };
const field = (line, name) => { const m = line.match(new RegExp(name + '=(\\[[^\\]]*\\]|\\S+)')); return m ? m[1].replace(/^\[|\]$/g, '') : null; };
const sep = url.includes('?') ? '&' : '?';

// The pack: the first run installs it through the app's requestAuthorization; wait for it.
const run = async (query, settledWhen, timeoutMs) => {
  await page.goto(url + sep + query, { waitUntil: 'commit', timeout: 180000 });
  await page.waitForFunction(() => window.__swiftuiwebDebug && window.__swiftuiwebDebug.frameCount() > 0, null, { timeout: 180000 });
  const deadline = Date.now() + timeoutMs;
  let line = '';
  while (Date.now() < deadline) { line = await speechLine(); if (settledWhen(line)) return line; await page.waitForTimeout(250); }
  return line;
};
const hasFinal = (line) => / final=/.test(line) || / error=/.test(line) || / cancelled/.test(line) || /available=false/.test(line) || /auth=(denied|restricted)/.test(line);
const words = (s) => s.toLowerCase().replace(/[^a-z0-9 ]/g, '').split(/\s+/).filter(Boolean);
const saysOne = (t) => { const w = words(t); return (w.includes('1') || w.includes('one')) && (w.includes('2') || w.includes('two')) && (w.includes('3') || w.includes('three')); };
const saysTwo = (t) => { const w = words(t); return w.includes('red') && w.includes('green') && w.includes('blue'); };
const orderly = (line, name) => {
  const appended = +field(line, 'appended')?.replace('ms', ''), first = +field(line, 'first')?.replace('ms', ''), finalAt = +field(line, 'at')?.replace('ms', '');
  if (!(first > 0) || !(appended >= 0)) problems.push(`${name}: timestamps missing in "${line}"`);
  else if (first < 100) problems.push(`${name}: a result at ${first} ms, before any frames could have been heard`);
  if (finalAt && first && finalAt < first) problems.push(`${name}: final at ${finalAt} ms before the first result at ${first} ms`);
};

const first = await run('speech=speech-one.wav', hasFinal, 15 * 60 * 1000);   // the pack's download, the first time
console.log('one:', first);
if (!/auth=authorized available=true/.test(first)) problems.push(`one: not authorised/available: "${first}"`);
let transcript = field(first, 'final');
if (transcript === null || !saysOne(transcript) || /red|green|blue/.test(transcript.toLowerCase())) problems.push(`one: final "${transcript}", expected one two three (as words or digits), no colours`);
if (+field(first, 'partials') < 1) problems.push(`one: no partial results in "${first}"`);
orderly(first, 'one');

const second = await run('speech=speech-two.wav', hasFinal, 60000);
console.log('two:', second);
transcript = field(second, 'final');
if (transcript === null || !saysTwo(transcript) || saysOne(transcript)) problems.push(`two: final "${transcript}", expected red green blue, no numbers`);
orderly(second, 'two');

const resampled = await run('speech=speech-one-48k.wav', hasFinal, 60000);
console.log('one at 48 kHz:', resampled);
transcript = field(resampled, 'final');
if (!/frames=79797@48000/.test(resampled)) problems.push(`48k: frames "${field(resampled, 'frames')}", expected 79797@48000`);
if (transcript === null || !saysOne(transcript)) problems.push(`48k: final "${transcript}", expected one two three through the resampler`);

const silence = await run('speech=silence', hasFinal, 60000);
console.log('silence:', silence);
if (field(silence, 'final') !== '' || +field(silence, 'partials') !== 0) problems.push(`silence: expected an empty final and no partials: "${silence}"`);

const nothing = await run('speech=none', hasFinal, 60000);
console.log('none:', nothing);
if (field(nothing, 'final') !== '' || +field(nothing, 'partials') !== 0) problems.push(`none: expected an empty final and no partials: "${nothing}"`);

const cancelled = await run('speech=speech-one.wav&cancel=1', (l) => / cancelled/.test(l) || / final=/.test(l) || / error=/.test(l), 60000);
await page.waitForTimeout(3000);   // nothing may follow the cancel
const afterCancel = await speechLine();
console.log('cancel:', afterCancel);
if (!/ cancelled/.test(afterCancel) || / final=/.test(afterCancel) || +field(afterCancel, 'partials') !== 1) problems.push(`cancel: expected one partial, cancelled, no final: "${afterCancel}"`);

console.log(problems.length ? problems.join('\n') : 'speech OK: the appended buffers are what is transcribed — two fixtures told apart, 48 kHz resampled, silence and nothing empty, a cancel final-less, every result after its frames');
await context.close();
process.exit(problems.length ? 1 : 0);
