// The browser's audio as AVFAudio reads it (decision 0021, pf-avfoundation-audio): the hook
// SwiftUIWebCanvas installs (MediaHost.swift) and AVFAudio uses. A module of its own, so
// installing the hook links only this into an app that never plays or records (decision 0006).
import WebFoundation

// MARK: - The host

/// What a host provides: playback of a URL, the microphone permission and its sample stream.
public enum _AVAudioHost {
    /// A player for the URL, or nil when the host cannot play it.
    nonisolated(unsafe) public static var makePlayer: ((URL) -> (any _AVAudioPlayback)?)?
    /// Asks for the microphone; the answer arrives on the main actor.
    nonisolated(unsafe) public static var requestRecordPermission: ((@escaping @MainActor (Bool) -> Void) -> Void)?
    /// Opens the microphone: samples arrive as mono float frames with their sample rate
    /// (chunks of `bufferSize` frames or whatever the host delivers), until stopped.
    nonisolated(unsafe) public static var openMicrophone: ((_ bufferSize: Int, _ deliver: @escaping @MainActor ([Float], Double) -> Void, _ failed: @escaping @MainActor (String) -> Void) -> (any _AVAudioCapture)?)?
}

/// A playing sound in the host.
public protocol _AVAudioPlayback: AnyObject {
    func play()
    func pause()
    func stop()
    var currentTime: Double { get set }
    var duration: Double { get }
    var volume: Double { get set }
    var rate: Double { get set }
    var loops: Int { get set }
    var isPlaying: Bool { get }
    var onFinished: (@MainActor () -> Void)? { get set }
}

/// An open microphone in the host.
public protocol _AVAudioCapture: AnyObject {
    var sampleRate: Double { get }
    func stop()
}
