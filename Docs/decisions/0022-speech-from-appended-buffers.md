# 0022 — Speech recognition from the app's appended buffers (draft)

Date: 2026-10-12
Status: **draft for a decision** — nothing here is built; `pf-speech` stays blocked until one
option is chosen and authorised.

## The requirement

Scrumdinger's `SpeechService` (unmodified) opens `AVAudioEngine.inputNode`, taps it, and
appends every `AVAudioPCMBuffer` to an `SFSpeechAudioBufferRecognitionRequest`; the
recogniser's results are whatever those bytes say. A faithful implementation transcribes
**those buffers** — not a microphone stream the browser opens on its own — and sends audio to
no service nobody approved. The page's plain `SpeechRecognition` fails both tests (its own
microphone; in Chrome, Google's service), which is why the browser host installs no recogniser
and `SFSpeechRecognizer.isAvailable` is false today.

## Options

### A. The buffers as a `MediaStreamTrack` into the browser's on-device recogniser

Data flow, all inside the page:

```
AVAudioEngine tap → request.append(buffer)           (the app, unchanged)
   → _SpeechHost.append(samples, rate)                 (Speech module → host hook)
   → AudioWorkletNode (a ring buffer the worklet plays out at the context's rate)
   → MediaStreamAudioDestinationNode.stream.getAudioTracks()[0]
   → recognition.processLocally = true; recognition.start(track)
   → onresult (interim + final) → SFSpeechRecognitionResult
```

Evidence (fetched 2026-10-12). **What this is evidence of**: each API on its own, from its
vendor's documentation. **What it is not**: proof that `start(track)` and `processLocally`
work *together* on the target browser with a worklet-generated track — no such source was
found, and nothing here has been run. That combined proof is the first deliverable of option
A if chosen (the availability probe and the synthetic-PCM plan below are written so it can be
established without installing anything or sending audio anywhere).

- `SpeechRecognition.start(audioTrack)` takes a live audio `MediaStreamTrack` and recognises
  that track instead of the microphone; an `InvalidStateError` if the track is not audio or
  not live ([MDN: start()](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition/start)).
  Chrome shipped it in **Chrome 135** (stable 2025-04-01; [Intent to Ship](https://groups.google.com/a/chromium.org/g/blink-dev/c/4ibjEVQ-i0s/m/2OsaIhf3BAAJ),
  [Chrome 135 release notes](https://developer.chrome.com/release-notes/135)).
- `processLocally = true`, `SpeechRecognition.available({langs, processLocally})` and
  `SpeechRecognition.install(...)` shipped in **Chrome 139** (2025-08): "neither audio nor
  transcribed speech are sent to a third-party service for processing"; a per-language pack
  (reported ≈60 MB) is downloaded once ([Chrome 139 release notes](https://developer.chrome.com/release-notes/139),
  [MDN: processLocally](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition/processLocally),
  [explainer](https://github.com/WebAudio/web-speech-api/blob/main/explainers/on-device-speech-recognition.md)).
  Chrome lists 17 on-device languages (en-US, ja-JP, zh-CN, …).
- MDN marks both as "limited availability", not Baseline: Chromium-based browsers only.
  Safari and Firefox have neither `start(track)` nor local processing → `isAvailable` false
  there, as now.
- A known edge: Brave's on-device model wanted 16 kHz input and rejected 44.1/48 kHz tracks
  with `service-not-allowed` until it resampled ([brave-browser#59570](https://github.com/brave/brave-browser/issues/59570));
  the worklet should therefore run in an `AudioContext({sampleRate: 16000})` and resample the
  app's buffers (Scrumdinger's tap comes at the input node's rate, 48 kHz from the browser
  microphone) — a linear resampler in the worklet, 48→16 kHz.

Semantics mapped to Apple's:

| Apple | Here |
|---|---|
| `append(buffer)` | the samples go into the worklet's ring buffer; the track plays them at real time (a buffer appended faster than real time queues; the queue depth is reported as latency) |
| `shouldReportPartialResults` | `interimResults`; each `onresult` builds the transcript so far (finals + interims) → `isFinal == false` |
| `endAudio()` | the worklet drains the queue, then the track is stopped → `recognition` ends → the last finals → one `isFinal == true` result (Apple: the final result after the audio ends) |
| `task.cancel()` | `recognition.abort()`, track stopped, no further results, `isCancelled` |
| `task.finish()` | `recognition.stop()`: finishes with what it has |
| `taskHint`, `addsPunctuation`, `contextualStrings` | accepted; Chrome's `phrases` (contextual biasing) where present |
| `isAvailable` | `available({langs: [locale], processLocally: true}) == "available"`; `"downloadable"` → `install()` after `requestAuthorization` (the one prompt the user sees); otherwise false |
| `requestAuthorization` | `.authorized` once the pack is installed, `.restricted` where local recognition is unavailable |

Constraints, **all unmeasured** (reported figures and estimates, not results from this
project): the pack download (reported ≈60 MB, once per language, user-visible); recognition
at real-time pace, so a 5-minute Scrumdinger meeting transcribes as it happens (latency: the
queue depth plus the recogniser's own — unmeasured); worklet code loaded from a `blob:` module
URL (the bundle has no separate file). Effort estimate: ~2 days (worklet, host hook, tests) —
an estimate. Package size: JavaScript only, expected negligible — unmeasured.

Whether the on-device recogniser accepts a worklet-generated track at all (as opposed to a
microphone or remote track), and at which sample rate, is the open question the probe below
answers; the Brave report suggests 16 kHz is the safe rate.

What it does not do: run anywhere but Chromium; recognise a URL request (`SFSpeechURLRecognitionRequest`)
without first decoding the file into buffers (possible via `decodeAudioData`, a second step).

### B. An in-page model consuming the buffers directly

What the **source** of whisper.cpp's `whisper.wasm` example says (fetched 2026-10-12 from
`ggml-org/whisper.cpp` master; nothing executed here):

- Input is float PCM: `full_default(index, audio, lang, nthreads, translate)` copies the
  JavaScript typed array straight into a `std::vector<float>` (`memoryView.set(audio)`) and
  calls `whisper_full(ctx, params, pcmf32.data(), pcmf32.size())` on a worker thread
  (`examples/whisper.wasm/emscripten.cpp`). The page feeds it `Float32Array` mono samples at
  `kSampleRate = 16000`, rendered through an `OfflineAudioContext`, up to `kMaxAudio_s = 30*60`
  (`index-tmpl.html`). So the app's appended buffers, resampled to 16 kHz mono, are exactly
  its input — the data flow is faithful by construction.
- Memory and threads from its `CMakeLists.txt`: `-s USE_PTHREADS=1`, `PTHREAD_POOL_SIZE_STRICT=0`,
  `INITIAL_MEMORY=512MB`, `MAXIMUM_MEMORY=2000MB`, `ALLOW_MEMORY_GROWTH=1`, `FORCE_FILESYSTEM=1`
  (`--bind`; no `-msimd128` flag in that file — the README states the SIMD requirement). So
  the **runtime budget is 512 MB of wasm memory at start, growable to 2 GB**; the 31 MB
  quantized model is a download size, not the memory the page takes. `n_threads =
  min(nthreads, min(16, pow2(hardware_concurrency)))`; threads need `SharedArrayBuffer`,
  which needs the page served **cross-origin isolated**: its `examples/server.py` sets
  `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`
  ("required headers for SharedArrayBuffer"). Those headers are a deployer's server setting
  and they constrain what else the page may embed (every cross-origin subresource must opt in).
- Models and sizes as the example lists them: tiny.en 75 MB, base.en 142 MB, small.en 466 MB;
  quantized tiny.en Q5_1 **31 MB**, base.en Q5_1 57 MB, small.en Q5_1 182 MB; the README
  says beyond `small` "the memory requirements and performance are unsatisfactory"; the model
  is written into the wasm file system (`FS_createDataFile`), so it lives in memory; Firefox
  "cannot load files exceeding 256 MB". No RAM figure is given.
- Hosting: the models are fetched from Hugging Face URLs in the example; a deployment would
  host its chosen model itself (an incoming download to the user, once; cached by the page).

Prerequisites for B, precisely: a cross-origin-isolated origin (COOP/COEP), a browser with
wasm SIMD and threads, a hosted model (31 MB quantized tiny.en at the smallest), the
whisper.wasm build (its own licence, MIT) in the bundle, and a 16 kHz mono resample of the
app's buffers. Not claimed: that it runs on any particular browser or phone, or any latency
or CPU figure — none was measured; the README's own limit is 120 s of microphone audio and
"unsatisfactory" beyond `small`. Effort estimate (an estimate): about a week plus the hosting
decision.

### C. A recogniser the deployer runs

The buffers over the deployer's own connection to a server the deployer controls (e.g. a
whisper server). Faithful bytes, but a transmission the deployer must approve and operate; not
a package default. Out unless Corey wants it.

## A non-installing availability probe (can run now, no decision needed)

A page script, run by hand or in Playwright on the target browser, that **installs nothing,
starts no recognition and opens no microphone**:

```js
const R = window.SpeechRecognition || window.webkitSpeechRecognition;
const report = {
  hasRecognition: !!R,
  hasProcessLocally: !!R && 'processLocally' in R.prototype,
  hasAvailable: !!R && typeof R.available === 'function',
  // whether start(track) is accepted is NOT derivable without calling it (start.length is
  // metadata, not the overload set): it stays "unproven" until a decision allows a call
  availability: R && R.available ? await R.available({ langs: ['en-US'], processLocally: true }) : 'n/a',
  worklet: !!(window.AudioContext && AudioWorkletNode && MediaStreamAudioDestinationNode),
};
```

First result (2026-10-12, `Playwright/speech-availability.mjs http://127.0.0.1:8772/index.html?platform=ios`,
the served app origin, a secure context): the project's Playwright Chromium is **129**
(HeadlessChrome/129.0.6668.29): `SpeechRecognition` present, `processLocally`/`available`/`install`
absent, the `start(track)` overload unproven (never called), the worklet pieces present. So option A cannot even be probed in this repository's CI until Playwright (and its
bundled Chromium) is upgraded past 139 — a tooling change to decide alongside the option, not
a given.

Second result (2026-10-12, the installed **Google Chrome 155.0.8059.40** through Playwright
with `CHROME=` — a fresh throwaway profile Playwright makes, not the person's; the served app
origin `http://127.0.0.1:8772`, a secure context; headless): `SpeechRecognition` present,
`processLocally` present, `available()` and `install()` present, the worklet pieces present,
and **`available({langs: ['en-US'], processLocally: true})` → `"downloadable"`**: the on-device
en-US pack is not on this machine's fresh profile. Nothing was installed (`install()` not
called) and no recognition was started, so the synthetic-WAV step did **not** run; the
`start(track)` overload remains unproven. To go further, someone installs the pack by hand
in that browser (a user-visible download from the browser vendor) — a prerequisite to
approve, not a step this probe takes. A note on the measurement itself: the status is per
profile; the person's own Chrome profile may differ, and was not touched.

`available()` only reports (`"available"`, `"downloadable"`, `"downloading"`, `"unavailable"`);
`install()` is never called. The report answers, per browser and version, whether option A's
three pieces exist before anyone commits to it; it goes in `Playwright/speech-availability.mjs`
and prints, it does not assert.

## Tests that prove the transcript depends on the buffers (for A or B)

Synthetic input, no microphone, no fake-device flags:

1. **Fixture WAVs**: two short utterances recorded once and committed (`Fixtures/Speech/one.wav`
   "one two three", `two.wav` "red green blue"), decoded in the test page into Float32 frames.
2. The test drives the *Swift* surface from the page: a tiny test app (or the Gallery with a
   `?speech-test` page) builds an `SFSpeechAudioBufferRecognitionRequest`, appends the decoded
   frames as `AVAudioPCMBuffer`s at the fixture's rate, calls `endAudio()`, and shows the final
   `formattedString`.
3. Assertions: fixture one's transcript contains "one two three" and not "red"; fixture two's
   the reverse; **silence** (zeros) yields an empty final; appending nothing and calling
   `endAudio()` yields an empty final; `cancel()` after the first interim yields no final; the
   transcript appears only after the frames are appended, never before (a timestamp check).
   Together these show the words come from the appended bytes and from nothing else.
4. The synthetic PCM is generated, not recorded from a microphone, so the test never touches
   `getUserMedia` and no fake-device flag is involved: the frames come from decoding the
   committed WAV (or from `speechSynthesis` rendered offline where a browser allows it) and
   are pushed through `request.append` exactly as the app pushes its tap's buffers.
5. CI: these need the language pack (A) or model (B) on the runner — a cached download step,
   or the test marked as requiring it and run on the machine that has it, reported as skipped
   (not passed) elsewhere. Until then the probe above is the only speech step in CI.

## The one owner choice, stated plainly

Both A and B are **local computation by design**: the only network traffic is an *incoming*
download (A: the browser's language pack, from the browser vendor, once per language; B: a
model file, from a host the deployer picks, once). Neither sends audio anywhere, needs a
service API key, or buys inference. Only C sends audio out, and C is not proposed.

So the choice is not "external service yes/no" — that is settled (no). It is:

| | A — browser on-device engine fed the exact PCM track | B — in-page model fed the exact buffers |
|---|---|---|
| Browsers | Chromium ≥ 139 only (feature-detected; `isAvailable` false elsewhere) | in principle any browser whose wasm has SIMD and threads (cross-origin isolation for `SharedArrayBuffer`); **unverified here** — which engine (whisper.cpp or Vosk), which model and whether it runs acceptably on an iPhone's Safari are prerequisites of the B experiment, not facts |
| Incoming download | the vendor's language pack (reported ≈60 MB, unmeasured), user-prompted | a model the deployer hosts (reported 50–150 MB, unmeasured) |
| Test infrastructure | an installed Chrome ≥ 139 through Playwright's `executablePath` with a throwaway profile (proven with Chrome 155 on this machine: all three APIs present) — the repository's Playwright Chromium 129 lacks them, so a CI run needs either that upgrade or an installed Chrome; plus the en-US pack on the machine (reported `"downloadable"`, not present) | the model cached on the runner; a cross-origin-isolated test server |
| Combined feasibility | the `start(track)`+`processLocally` pairing with a worklet-generated track is **unproven** (per-API evidence only) | whisper.cpp and Vosk publish wasm builds whose input is Float32 frames; **not run here** — their requirements (SIMD, threads, cross-origin isolation headers on the deployer's server, model hosting) are unverified for this project |
| CPU / latency | the browser's engine (unmeasured) | windowed, phone CPU cost (unmeasured) |
| Effort | ~2 days (estimate) | ~1 week + hosting decision (estimate) |

Corey's decision: A (Chromium-first, smaller, hinges on an unproven pairing and a test-browser
upgrade) or B (potentially broader, heavier, with engine/model/hosting requirements still to
verify). Nothing in this document picks one.

## The smallest isolated feasibility step (before either route is "accepted")

A synthetic-PCM experiment that touches no app, no microphone, no service, and installs
nothing *in the repository*:

- **For A** — prerequisites: (1) a Chromium ≥ 139: **already satisfied locally** by the
  installed Google Chrome 155 through `CHROME=… node speech-availability.mjs` (a throwaway
  profile; no repository upgrade needed for the experiment — CI is another matter); (2) the
  en-US on-device pack present in that profile: **not satisfied** — `available()` reported
  `"downloadable"`; `install()` is a user-visible ~60 MB download from the browser vendor,
  run by hand on the test machine, not by CI and not by this probe — this is the one
  remaining prerequisite, and granting it is *not* choosing A as the product's backend, only
  allowing the experiment; (3) one committed WAV with a known utterance. The step: a standalone page (no SwiftUIWeb
  code) decodes the WAV, plays its frames through an AudioWorklet into a
  `MediaStreamAudioDestinationNode` track at 16 kHz, calls `recognition.processLocally = true;
  recognition.start(track)`, and prints the transcript, the time to first interim and to the
  final, and any error. Pass = the known words come back; fail = `InvalidStateError`,
  `service-not-allowed`, silence, or a transcript that does not depend on the file. This is
  the combined-API proof the evidence above lacks.
- **For B** — prerequisites: a wasm build of whisper.cpp or Vosk and one model on the test
  machine (a download, approved separately); the same WAV. The step: the same page feeds the
  decoded frames to the model and prints the transcript and timing.
- Either way the result is a number set (first-interim latency, final latency, CPU) replacing
  the "unmeasured" labels above, and a yes/no on whether the route can consume the exact
  buffers. Only then does the Swift-surface test plan below apply.

## Recommendation

A, feature-detected, Chromium-only, with `isAvailable` false everywhere else and the app's own
alert as today — on the grounds that it is the smaller build, its semantics map onto Apple's
one for one, and the download is the browser vendor's rather than a file the deployer must
host. Both A and B keep every byte of audio on the device; that is not what separates them.
What does: A hinges on an unproven pairing and a test-browser upgrade; B is heavier and needs
a hosted model. B is the fallback if the A experiment fails or if browsers beyond Chromium
matter more than the download and CPU cost. C is not recommended. This is a recommendation,
not a choice; the choice is Corey's.

## 2048, for the record

Unchanged by this decision: SwiftUI-2048's wasm barrier (`@objc`, `#selector`) is a compiler
and runtime matter (decision 0021's two routes), open, with no acceptance by other means.
