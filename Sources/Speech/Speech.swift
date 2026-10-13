// Apple's Speech framework for the web (decision 0021, pf-speech): `SFSpeechRecognizer` over the
// browser's `SpeechRecognition` (the host installs `_SpeechHost`), delivering partial and final
// `SFSpeechRecognitionResult`s to a task's handler. The browser recognises from the microphone
// itself: the buffers an app appends to an `SFSpeechAudioBufferRecognitionRequest` from its own
// audio tap are accepted and are not what is transcribed (the stated deviation of `pf-speech`).
// Written against Scrumdinger's SpeechService.
@_exported import WebFoundation   // as Apple's Speech re-exports Foundation
import AVFoundation

// MARK: - The host

/// What a host provides: whether recognition exists, and a session delivering transcripts.
public enum _SpeechHost {
    /// Whether the browser offers speech recognition at all.
    nonisolated(unsafe) public static var isAvailable: (() -> Bool)?
    /// Starts recognising in `locale` (a BCP 47 tag), with interim results when `partial`;
    /// `result` gets the transcript so far and whether it is final, `failed` an error, `ended`
    /// the session's end; the returned session stops it.
    nonisolated(unsafe) public static var start: ((_ locale: String, _ partial: Bool, _ result: @escaping @MainActor (String, Bool) -> Void,
                                                  _ failed: @escaping @MainActor (String) -> Void, _ ended: @escaping @MainActor () -> Void) -> (any _SpeechSession)?)?
    /// The authorisation the host remembers (the browser asks for the microphone on start).
    nonisolated(unsafe) public static var authorization: SFSpeechRecognizerAuthorizationStatus = .notDetermined
}

public protocol _SpeechSession: AnyObject {
    func stop()
    func cancel()
}

// MARK: - Authorization and hints

public enum SFSpeechRecognizerAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case restricted = 2
    case authorized = 3
}

public enum SFSpeechRecognitionTaskHint: Int, Sendable {
    case unspecified = 0
    case dictation = 1
    case search = 2
    case confirmation = 3
}

public enum SFSpeechRecognitionTaskState: Int, Sendable {
    case starting = 0
    case running = 1
    case finishing = 2
    case canceling = 3
    case completed = 4
}

public struct SFSpeechError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public var errorDescription: String? { description }
    public init(_ description: String) { self.description = description }
}

// MARK: - Recognizer

/// An object you use to check for the availability of the speech recognition service, and to
/// initiate the speech recognition process.
public class SFSpeechRecognizer {
    public let locale: Locale
    public weak var delegate: (any SFSpeechRecognizerDelegate)?
    public var defaultTaskHint: SFSpeechRecognitionTaskHint = .unspecified
    public var supportsOnDeviceRecognition: Bool { false }
    public var queue: DispatchQueue = .main

    /// The recognizer for the current locale.
    public convenience init?() { self.init(locale: Locale.current) }

    /// A recognizer for the locale (Apple's is nil only for an unsupported locale; whether the
    /// browser recognises at all is `isAvailable`, asked when the host is in place — an app's
    /// scene can make its recognizer before the host installs).
    public init?(locale: Locale) {
        self.locale = locale
    }

    /// Whether the recognizer is available to process speech right now.
    public var isAvailable: Bool { _SpeechHost.isAvailable?() ?? false }

    /// The locales the host can recognise: the browser takes any BCP 47 tag.
    public static func supportedLocales() -> Set<Locale> { [Locale.current] }

    public static func authorizationStatus() -> SFSpeechRecognizerAuthorizationStatus { _SpeechHost.authorization }

    /// Asks the user to allow speech recognition. The browser asks for the microphone when
    /// recognition starts, so the answer is whether recognition exists at all.
    public static func requestAuthorization(_ handler: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        let status: SFSpeechRecognizerAuthorizationStatus = (_SpeechHost.isAvailable?() ?? false) ? .authorized : .restricted
        _SpeechHost.authorization = status
        handler(status)
    }

    /// Executes the speech recognition request and delivers the results to the handler.
    @discardableResult
    public func recognitionTask(with request: SFSpeechRecognitionRequest, resultHandler: @escaping (SFSpeechRecognitionResult?, Error?) -> Void) -> SFSpeechRecognitionTask {
        let task = SFSpeechRecognitionTask(request: request)
        nonisolated(unsafe) let resultHandler = resultHandler
        task.start(locale: locale.identifier.replacingOccurrences(of: "_", with: "-"), partial: request.shouldReportPartialResults,
                   onResult: { resultHandler($0, nil) }, onError: { resultHandler(nil, $0) })
        return task
    }

    @discardableResult
    public func recognitionTask(with request: SFSpeechRecognitionRequest, delegate: any SFSpeechRecognitionTaskDelegate) -> SFSpeechRecognitionTask {
        let task = SFSpeechRecognitionTask(request: request)
        task.delegate = delegate
        nonisolated(unsafe) let delegate = delegate
        nonisolated(unsafe) let held = task
        task.start(locale: locale.identifier.replacingOccurrences(of: "_", with: "-"), partial: request.shouldReportPartialResults, onResult: { result in
            if result.isFinal {
                delegate.speechRecognitionTask(held, didFinishRecognition: result)
                delegate.speechRecognitionTask(held, didFinishSuccessfully: true)
            } else {
                delegate.speechRecognitionTask(held, didHypothesizeTranscription: result.bestTranscription)
            }
        }, onError: { _ in delegate.speechRecognitionTask(held, didFinishSuccessfully: false) })
        return task
    }
}

public protocol SFSpeechRecognizerDelegate: AnyObject {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool)
}

public protocol SFSpeechRecognitionTaskDelegate: AnyObject {
    func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult)
    func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask)
    func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool)
}

extension SFSpeechRecognitionTaskDelegate {
    public func speechRecognitionDidDetectSpeech(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didHypothesizeTranscription transcription: SFTranscription) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishRecognition recognitionResult: SFSpeechRecognitionResult) {}
    public func speechRecognitionTaskFinishedReadingAudio(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTaskWasCancelled(_ task: SFSpeechRecognitionTask) {}
    public func speechRecognitionTask(_ task: SFSpeechRecognitionTask, didFinishSuccessfully successfully: Bool) {}
}

// MARK: - Requests

/// An abstract class that represents a request to recognize speech from an audio source.
public class SFSpeechRecognitionRequest {
    public var taskHint: SFSpeechRecognitionTaskHint = .unspecified
    public var shouldReportPartialResults = true
    public var contextualStrings: [String] = []
    public var interactionIdentifier: String?
    public var requiresOnDeviceRecognition = false
    public var addsPunctuation = false
    public var customizedLanguageModel: Any?
    package init() {}
}

/// A request to recognize speech from captured audio content, such as audio from the device's
/// microphone. The appended buffers are counted and otherwise not used: the browser's
/// recogniser listens to the microphone itself.
public final class SFSpeechAudioBufferRecognitionRequest: SFSpeechRecognitionRequest {
    public private(set) var appendedFrames: Int = 0
    public private(set) var audioEnded = false
    public var nativeAudioFormat: AVAudioFormat { AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1) }
    public override init() { super.init() }

    /// Appends audio from a PCM buffer (accepted; the browser transcribes the microphone directly).
    public func append(_ audioPCMBuffer: AVAudioPCMBuffer) { appendedFrames += Int(audioPCMBuffer.frameLength) }

    /// Marks the end of audio input: the recogniser finishes with what it has.
    public func endAudio() {
        audioEnded = true
        onEndAudio?()
    }

    var onEndAudio: (() -> Void)?
}

/// A request to recognize speech in a recorded audio file. The browser's recogniser has no
/// file input: the task fails.
public final class SFSpeechURLRecognitionRequest: SFSpeechRecognitionRequest {
    public let url: URL
    public init(url: URL) {
        self.url = url
        super.init()
    }
}

// MARK: - Results

/// A textual representation of the specified speech in its entirety, as recognized by the
/// speech recognizer.
public final class SFTranscription {
    public let formattedString: String
    public let segments: [SFTranscriptionSegment]
    package init(_ string: String) {
        formattedString = string
        var offset = 0
        segments = string.split(separator: " ", omittingEmptySubsequences: true).map { word in
            let segment = SFTranscriptionSegment(substring: String(word), substringRange: NSRange(location: offset, length: word.count))
            offset += word.count + 1
            return segment
        }
    }
    public var speakingRate: Double { 0 }
    public var averagePauseDuration: TimeInterval { 0 }
}

/// A discrete part of an entire transcription.
public final class SFTranscriptionSegment {
    public let substring: String
    public let substringRange: NSRange
    public let timestamp: TimeInterval = 0
    public let duration: TimeInterval = 0
    public let confidence: Float = 1
    public let alternativeSubstrings: [String] = []
    init(substring: String, substringRange: NSRange) {
        self.substring = substring
        self.substringRange = substringRange
    }
}

/// An object that contains the partial or final results of a speech recognition request.
public final class SFSpeechRecognitionResult {
    public let bestTranscription: SFTranscription
    public let transcriptions: [SFTranscription]
    public let isFinal: Bool
    public var speechRecognitionMetadata: Any? { nil }
    package init(_ string: String, isFinal: Bool) {
        bestTranscription = SFTranscription(string)
        transcriptions = [bestTranscription]
        self.isFinal = isFinal
    }
}

// MARK: - Task

/// A task object for monitoring the speech recognition progress.
public final class SFSpeechRecognitionTask {
    public private(set) var state: SFSpeechRecognitionTaskState = .starting
    public private(set) var isCancelled = false
    public private(set) var isFinishing = false
    public private(set) var error: Error?
    public weak var delegate: (any SFSpeechRecognitionTaskDelegate)?
    private let request: SFSpeechRecognitionRequest
    private var session: (any _SpeechSession)?

    package init(request: SFSpeechRecognitionRequest) { self.request = request }

    func start(locale: String, partial: Bool, onResult: @escaping (SFSpeechRecognitionResult) -> Void, onError: @escaping (Error) -> Void) {
        nonisolated(unsafe) let onResult = onResult
        nonisolated(unsafe) let onError = onError
        nonisolated(unsafe) let task = self
        if request is SFSpeechURLRecognitionRequest {
            fail(SFSpeechError("Speech: the browser recognises the microphone, not a file"), onError)
            return
        }
        guard let start = _SpeechHost.start else {
            fail(SFSpeechError("Speech: no speech host"), onError)
            return
        }
        (request as? SFSpeechAudioBufferRecognitionRequest)?.onEndAudio = { [weak self] in self?.finish() }
        session = start(locale, partial, { transcript, isFinal in
            guard !task.isCancelled, task.state != .completed else { return }
            task.state = isFinal ? .completed : .running
            onResult(SFSpeechRecognitionResult(transcript, isFinal: isFinal))
        }, { message in
            task.fail(SFSpeechError(message), onError)
        }, {
            // The browser's session ended without a final result (silence, or stopped): a
            // final result from nothing says so, as Apple's does when audio ends.
            guard !task.isCancelled, task.state != .completed else { return }
            task.state = .completed
            onResult(SFSpeechRecognitionResult("", isFinal: true))
        })
        if session == nil { fail(SFSpeechError("Speech: recognition could not start"), onError) }
        else if state == .starting { state = .running }
    }

    private func fail(_ error: Error, _ onError: (Error) -> Void) {
        guard !isCancelled, state != .completed else { return }
        self.error = error
        state = .completed
        onError(error)
    }

    /// Cancels the current speech recognition task: no more results.
    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        state = .canceling
        session?.cancel()
        session = nil
        delegate?.speechRecognitionTaskWasCancelled(self)
        state = .completed
    }

    /// Stops accepting new audio and finishes processing on the audio input that has already
    /// been accepted.
    public func finish() {
        guard !isCancelled, !isFinishing else { return }
        isFinishing = true
        state = .finishing
        session?.stop()
    }
}
