// Reports what the browser offers for decision 0022 (speech from the app's appended buffers)
// WITHOUT installing a language pack, starting recognition or opening a microphone: the
// SpeechRecognition constructor, `processLocally`, `available()`, whether `start` takes a
// track, the on-device availability for en-US, and the Web Audio pieces a worklet-fed track
// needs. It prints; it asserts nothing (no option is chosen).
//   node speech-availability.mjs [chromium|webkit|firefox]
import { chromium, webkit, firefox } from 'playwright';
const engine = { chromium, webkit, firefox }[process.argv[2] || 'chromium'];
const browser = await engine.launch();
const page = await browser.newPage();
await page.goto('about:blank');
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
    startArity: R ? R.prototype.start.length : 0,
    onDeviceAvailability: availability,
    worklet: !!(window.AudioContext && window.AudioWorkletNode && window.MediaStreamAudioDestinationNode),
  };
});
console.log(JSON.stringify(report, null, 2));
await browser.close();
