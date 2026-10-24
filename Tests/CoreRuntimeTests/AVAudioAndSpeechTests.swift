// The AVFoundation audio and Speech stand-ins (decision 0021: pf-avfoundation-audio, pf-speech)
// against a fake host — what Scrumdinger's AudioService and SpeechService call, in the order
// they call it. Without a host: players play nothing, the engine fails to start, no permission
// and no recognition; the browser host installs both (MediaHost.swift, SpeechHost.swift — the
// recogniser hears the buffers the app appends, decision 0022).
import Testing
import AVFoundation
import Speech
import WebFoundation

#if !os(WASI)
@Suite(.serialized) @MainActor struct AVAudioAndSpeechTests {
    final class FakePlayback: _AVAudioPlayback {
        var played = 0, paused = 0
        var currentTime: Double = 0
        var duration: Double { 1.5 }
        var volume: Double = 1
        var rate: Double = 1
        var loops = 0
        var isPlaying = false
        var onFinished: (@MainActor () -> Void)?
        func play() { played += 1; isPlaying = true }
        func pause() { paused += 1; isPlaying = false }
        func stop() { isPlaying = false; currentTime = 0 }
    }

    final class FakeCapture: _AVAudioCapture {
        let sampleRate: Double = 16_000
        var stopped = false
        func stop() { stopped = true }
    }

    private func withoutHost() {
        _AVAudioHost.makePlayer = nil
        _AVAudioHost.requestRecordPermission = nil
        _AVAudioHost.openMicrophone = nil
        _AVAudioHost.recordPermission = .undetermined
        _SpeechHost._reset()
    }

    @Test func playerPlaysThroughTheHostAndIsInertWithoutOne() throws {
        withoutHost()
        let url = URL(string: "assets/ding.wav")!
        let silent = try AVAudioPlayer(contentsOf: url)
        #expect(!silent.prepareToPlay() && !silent.play() && !silent.isPlaying && silent.duration == 0)
        var made: [FakePlayback] = []
        _AVAudioHost.makePlayer = { _ in let p = FakePlayback(); made.append(p); return p }
        let player = try AVAudioPlayer(contentsOf: url)
        player.numberOfLoops = 2
        player.volume = 0.5
        #expect(player.prepareToPlay() && made.count == 1)
        // As AudioService replays a cached player: the time back to 0, play again.
        player.currentTime = 0
        #expect(player.play() && player.isPlaying && made[0].played == 1 && made[0].loops == 2 && made[0].volume == 0.5)
        #expect(player.duration == 1.5)
        player.pause()
        #expect(!player.isPlaying && made[0].paused == 1)
        withoutHost()
    }

    @Test func sessionRecordsItsConfigurationAndAsksTheHostForTheMicrophone() throws {
        withoutHost()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #expect(session.category == .playAndRecord && session.mode == .measurement && session.categoryOptions == .duckOthers && session.isActive)
        var refused = false
        AVAudioApplication.requestRecordPermission { refused = !$0 }
        #expect(refused && session.recordPermission == .denied)
        _AVAudioHost.recordPermission = .undetermined
        _AVAudioHost.requestRecordPermission = { answer in answer(true) }
        var granted = false
        AVAudioApplication.requestRecordPermission { granted = $0 }
        #expect(granted && session.recordPermission == .granted && AVAudioApplication.shared.recordPermission == .granted)
        try session.setActive(false, options: .notifyOthersOnDeactivation)
        #expect(!session.isActive)
        withoutHost()
    }

    @Test func engineDeliversTheMicrophoneToTheTapAsPCMBuffers() throws {
        withoutHost()
        let engine = AVAudioEngine()
        engine.prepare()
        #expect(throws: (any Error).self) { try engine.start() }
        var received: [(frames: Int, rate: Double, sample: Float, position: Int64)] = []
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: engine.inputNode.outputFormat(forBus: 0)) { buffer, time in
            received.append((Int(buffer.frameLength), buffer.format.sampleRate, buffer.floatChannelData![0][1], time.sampleTime))
        }
        var deliver: (@MainActor ([Float], Double) -> Void)?
        let capture = FakeCapture()
        _AVAudioHost.openMicrophone = { size, send, _ in
            #expect(size == 1024)
            deliver = send
            return capture
        }
        try engine.start()
        #expect(engine.isRunning)
        deliver?([0, 0.25, 0.5], 16_000)
        deliver?([1, 1, 1, 1], 16_000)
        #expect(received.count == 2 && received[0].frames == 3 && received[0].rate == 16_000 && received[0].sample == 0.25 && received[1].position == 3)
        // SpeechService appends every buffer to its request: counted, not transcribed.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.append(AVAudioPCMBuffer(samples: [0, 0], sampleRate: 16_000))
        #expect(request.appendedFrames == 2)
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        #expect(!engine.isRunning && capture.stopped)
        withoutHost()
    }

    @Test func speechIsUnavailableWithoutAHostAndTheAppSeesIt() async {
        withoutHost()
        // SpeechService: the recognizer exists, is not available, and authorisation is refused.
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        #expect(recognizer != nil && recognizer?.isAvailable == false)
        var status: SFSpeechRecognizerAuthorizationStatus?
        SFSpeechRecognizer.requestAuthorization { status = $0 }
        #expect(status == .restricted && SFSpeechRecognizer.authorizationStatus() == .restricted)
        var failure: Error?
        let task = recognizer!.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, error in failure = error }
        #expect(failure != nil && task.state == .completed)
    }

    /// A host's session: what it was given, and the results it can emit.
    final class FakeSession: _SpeechSession {
        var appended: [([Float], Double)] = []
        var audioEnded = false, stopped = false, cancelled = false
        func append(_ samples: [Float], sampleRate: Double) { appended.append((samples, sampleRate)) }
        func endAudio() { audioEnded = true }
        func stop() { stopped = true }
        func cancel() { cancelled = true }
    }

    private func hostedSession(available: _SpeechAvailability = .available, installs: Bool? = nil) -> (FakeSession, () -> (@MainActor (String, Bool) -> Void)?, () -> (@MainActor (String) -> Void)?) {
        let session = FakeSession()
        nonisolated(unsafe) var emit: (@MainActor (String, Bool) -> Void)?
        nonisolated(unsafe) var failed: (@MainActor (String) -> Void)?
        // Authorisation asks for the current locale's pack (whatever the machine's is: en-001 on
        // CI's Linux), a recognizer's availability for its own locale.
        _SpeechHost.availability = { _, install, completion in
            if let installs { #expect(install == installs) }
            completion(available)
        }
        _SpeechHost.start = { locale, partial, result, fail in
            #expect(locale == "en-US" && partial)
            emit = result
            failed = fail
            return session
        }
        return (session, { emit }, { failed })
    }

    @Test func authorizationInstallsThePackAndAvailabilityIsTheHostsAnswer() {
        withoutHost()
        _ = hostedSession(available: .available, installs: true)
        let recognizer = SFSpeechRecognizer()!   // the current locale, as Scrumdinger's service makes it
        var status: SFSpeechRecognizerAuthorizationStatus?
        SFSpeechRecognizer.requestAuthorization { status = $0 }
        #expect(status == .authorized && recognizer.isAvailable && recognizer.supportsOnDeviceRecognition)
        // Another locale's recognizer asks the host for its own pack (without installing) and is
        // unavailable until the answer lands — here at once.
        _SpeechHost.availability = { locale, install, completion in
            #expect(locale == "ja-JP" && !install)
            completion(.available)
        }
        let other = SFSpeechRecognizer(locale: Locale(identifier: "ja_JP"))!
        #expect(!other.isAvailable && other.isAvailable)
        // A locale the device has no pack for: restricted, and not available.
        _SpeechHost._reset()
        _ = hostedSession(available: .unavailable)
        SFSpeechRecognizer.requestAuthorization { status = $0 }
        #expect(status == .restricted && !recognizer.isAvailable)
        withoutHost()
    }

    @Test func theAppendedBuffersReachTheSessionAndResultsAreCumulativeThenFinal() {
        withoutHost()
        let (session, emit, _) = hostedSession()
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
        var seen: [(String, Bool)] = []
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Buffers appended before the task takes the request wait for it (Apple allows the order).
        request.append(AVAudioPCMBuffer(samples: [0.1, 0.2], sampleRate: 48_000))
        #expect(session.appended.isEmpty && request.appendedFrames == 2)
        let task = recognizer.recognitionTask(with: request) { result, _ in
            if let result { seen.append((result.bestTranscription.formattedString, result.isFinal)) }
        }
        #expect(session.appended.count == 1 && session.appended[0].0 == [0.1, 0.2] && session.appended[0].1 == 48_000)
        request.append(AVAudioPCMBuffer(samples: [0.3], sampleRate: 48_000))
        #expect(session.appended.count == 2 && request.appendedFrames == 3)
        emit()?("hello", false)
        emit()?("hello world", false)
        #expect(seen.map(\.0) == ["hello", "hello world"] && seen.allSatisfy { !$0.1 } && task.state == .running)
        // The app ends its audio: the session drains, and the host's final result completes the task.
        request.endAudio()
        #expect(session.audioEnded && request.audioEnded)
        request.append(AVAudioPCMBuffer(samples: [0.4], sampleRate: 48_000))   // after the end: not forwarded
        #expect(session.appended.count == 2)
        emit()?("hello world", true)
        #expect(seen.last?.0 == "hello world" && seen.last?.1 == true && task.state == .completed)
        #expect(SFTranscription("hello world").segments.map(\.substring) == ["hello", "world"])
        emit()?("late", true)   // nothing after the final
        #expect(seen.count == 3)
        withoutHost()
    }

    @Test func aTaskCancelsFinishesAndFailsThroughTheSession() {
        withoutHost()
        let (session, _, failed) = hostedSession()
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
        let cancelled = recognizer.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, _ in }
        cancelled.cancel()
        #expect(cancelled.isCancelled && session.cancelled && cancelled.state == .completed)
        let finished = recognizer.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, _ in }
        finished.finish()
        #expect(finished.isFinishing && session.stopped && finished.state == .finishing)
        var failure: Error?
        let failing = recognizer.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, error in failure = error }
        failed()?("Speech: network")
        #expect(failure?.localizedDescription == "Speech: network" && failing.state == .completed)
        // A file request: the host recognises buffers only.
        var fileFailure: Error?
        recognizer.recognitionTask(with: SFSpeechURLRecognitionRequest(url: URL(string: "file:///a.wav")!)) { _, error in fileFailure = error }
        #expect(fileFailure != nil)
        withoutHost()
    }
}
#endif
