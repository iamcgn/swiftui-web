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

`whisper.cpp` (wasm build; tiny/base English models reported 75–150 MB) or Vosk (wasm;
models reported ≈50 MB) fed the appended Float32 frames; results after each window. Every
browser with wasm SIMD and threads; no pack API, but a model download from a host the
deployer chooses (a transmission of the model to the user, not of audio from them). Latency:
windowed (1–3 s chunks, unmeasured); CPU heavy on phones (unmeasured). Effort estimate: a
week, plus a model hosting decision. Faithful in data flow; costly in size and battery; the
deployer must host the model. Nothing here has been run either.

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
  startArity: R ? R.prototype.start.length : 0,                 // 1 when start(track) is accepted
  availability: R && R.available ? await R.available({ langs: ['en-US'], processLocally: true }) : 'n/a',
  worklet: !!(window.AudioContext && AudioWorkletNode && MediaStreamAudioDestinationNode),
};
```

First result (2026-10-12, `Playwright/speech-availability.mjs chromium`): the project's
Playwright Chromium is **129** (HeadlessChrome/129.0.6668.29): `SpeechRecognition` present,
`processLocally`/`available`/`install` absent, `start` takes no track, the worklet pieces
present. So option A cannot even be probed in this repository's CI until Playwright (and its
bundled Chromium) is upgraded past 139 — a tooling change to decide alongside the option, not
a given.

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

## Recommendation

A, feature-detected, Chromium-only, with `isAvailable` false everywhere else and the app's own
alert as today. It is the only option whose bytes never leave the page, whose cost is a
one-time pack the user is asked for, and whose semantics map onto Apple's one for one. B is
the fallback if Corey wants Safari/Firefox covered and accepts a model download and the CPU
cost. C is not recommended.

## 2048, for the record

Unchanged by this decision: SwiftUI-2048's wasm barrier (`@objc`, `#selector`) is a compiler
and runtime matter (decision 0021's two routes), open, with no acceptance by other means.
