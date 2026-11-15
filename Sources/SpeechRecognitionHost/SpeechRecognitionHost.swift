// The browser's on-device speech recognition as Speech reads it (decisions 0021 and 0022,
// pf-speech): the hook SwiftUIWebCanvas installs (SpeechHost.swift) and Speech uses. A module of
// its own, depending on nothing, so installing the hook links only this into an app that never
// makes a recogniser (decision 0006).

// MARK: - The host

/// What a host provides: whether on-device recognition exists for a locale (installing its
/// language pack when asked to), and a session recognising the buffers it is given.
public enum _SpeechHost {
    /// Asks whether `locale` (a BCP 47 tag) can be recognised on the device; with `install`,
    /// the host may download the locale's pack first (the one user-visible step, from the
    /// browser's vendor). The answer arrives when known.
    nonisolated(unsafe) public static var availability: ((_ locale: String, _ install: Bool, _ completion: @escaping @MainActor (_SpeechAvailability) -> Void) -> Void)?
    /// Starts a session recognising `locale` with interim results when `partial`; `result`
    /// gets the transcript so far and whether it is the final one, `failed` an error; the
    /// returned session takes the audio.
    nonisolated(unsafe) public static var start: ((_ locale: String, _ partial: Bool, _ result: @escaping @MainActor (String, Bool) -> Void,
                                                  _ failed: @escaping @MainActor (String) -> Void) -> (any _SpeechSession)?)?
}

public enum _SpeechAvailability: Sendable, Equatable {
    /// The locale is recognised on the device now.
    case available
    /// A language pack would have to be downloaded first.
    case downloadable
    /// The browser has no on-device recognition for the locale (or none at all).
    case unavailable
}

/// One recognition: the audio goes in as float frames at their sample rate; `endAudio` lets
/// what was appended finish and then ends with the final result; `stop` finishes with what
/// has been recognised so far; `cancel` ends with no further results.
public protocol _SpeechSession: AnyObject {
    func append(_ samples: [Float], sampleRate: Double)
    func endAudio()
    func stop()
    func cancel()
}
