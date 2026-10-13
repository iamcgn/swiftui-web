// Reports what the browser offers for decision 0022 (speech from the app's appended buffers)
// WITHOUT installing a language pack, starting recognition or opening a microphone, on a
// representative app origin (the served app page, so permissions policy and secure-context
// rules apply as they will to the app): the SpeechRecognition constructor, `processLocally`,
// `available()`/`install()` as properties, the on-device availability for en-US, and the Web
// Audio pieces a worklet-fed track needs. Whether `start(track)` is accepted is NOT reported:
// `start.length` is metadata, and the only proof is a call, which this probe does not make —
// it stays "unproven" until a decision allows an actual recognition. It prints; it asserts nothing.
//   node speech-availability.mjs http://127.0.0.1:8773/index.html [chromium|webkit|firefox]
//   CHROME=/path/to/Chrome node speech-availability.mjs <url>   an installed Chrome in a throwaway
//   profile (never the person's own), for a newer Chromium than Playwright's
import { chromium, webkit, firefox } from 'playwright';
const url = process.argv[2] && process.argv[2].startsWith('http') ? process.argv[2] : 'about:blank';
const engine = { chromium, webkit, firefox }[process.argv[3] || (url === 'about:blank' ? process.argv[2] : null) || 'chromium'];
const launch = process.env.CHROME ? { executablePath: process.env.CHROME, args: ['--no-first-run', '--no-default-browser-check'] } : {};
const browser = await engine.launch(launch);   // Playwright makes a fresh, isolated profile per launch
const page = await browser.newPage();
await page.goto(url, { waitUntil: 'commit' });
const report = await page.evaluate(async () => {
  const R = window.SpeechRecognition || window.webkitSpeechRecognition;
  let availability = 'n/a';
  try { if (R && typeof R.available === 'function') availability = await R.available({ langs: ['en-US'], processLocally: true }); } catch (e) { availability = 'error: ' + e.message; }
  return {
    userAgent: navigator.userAgent,
    hasRecognition: !!R,
    hasProcessLocally: !!R && 'processLocally' in R.prototype,
    hasAvailable: !!R && typeof R.available === 'function',
    hasInstall: !!R && typeof R.install === 'function',
    startTrackOverload: 'unproven (needs a start(track) call; not made here)',
    onDeviceAvailability: availability,
    origin: location.origin, secureContext: window.isSecureContext,
    worklet: !!(window.AudioContext && window.AudioWorkletNode && window.MediaStreamAudioDestinationNode),
  };
});
console.log(JSON.stringify(report, null, 2));
await browser.close();
