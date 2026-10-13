// The AVFoundation audio and Speech stand-ins (decision 0021: pf-avfoundation-audio, pf-speech)
// against a fake host — what Scrumdinger's AudioService and SpeechService call, in the order
// they call it. Without a host: players play nothing, the engine fails to start, no permission
// and no recognition; the browser host installs the audio part (MediaHost.swift), never speech.
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
        _SpeechHost.isAvailable = nil
        _SpeechHost.start = nil
        _SpeechHost.authorization = .notDetermined
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

    final class FakeSession: _SpeechSession {
        var stopped = false, cancelled = false
        func stop() { stopped = true }
        func cancel() { cancelled = true }
    }

    @Test func aHostedRecognizerDeliversPartialThenFinalResultsAndCancels() {
        withoutHost()
        var emit: (@MainActor (String, Bool) -> Void)?
        let session = FakeSession()
        _SpeechHost.isAvailable = { true }
        _SpeechHost.start = { locale, partial, result, _, _ in
            #expect(locale == "en-US" && partial)
            emit = result
            return session
        }
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
        #expect(recognizer.isAvailable)
        var seen: [(String, Bool)] = []
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let task = recognizer.recognitionTask(with: request) { result, _ in
            if let result { seen.append((result.bestTranscription.formattedString, result.isFinal)) }
        }
        emit?("hello", false)
        emit?("hello world", true)
        #expect(seen.map(\.0) == ["hello", "hello world"] && seen.map(\.1) == [false, true] && task.state == .completed)
        #expect(seen.last.map { _ in SFTranscription("hello world").segments.map(\.substring) } == ["hello", "world"])
        let second = recognizer.recognitionTask(with: SFSpeechAudioBufferRecognitionRequest()) { _, _ in }
        second.cancel()
        #expect(second.isCancelled && session.cancelled)
        withoutHost()
    }
}
#endif
