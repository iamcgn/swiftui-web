// `AVAudioRecorder` on the web: it meters the microphone. `record()` opens the host's
// microphone (the browser's, through `_AVAudioHost`), and `updateMeters()` reads the level of
// the latest samples, which is what apps that draw a sound level use it for (Swift Charts
// Examples' sound bars). Nothing is written to the URL: there is no AVAudioFile yet.
import WebFoundation
#if os(WASI)
import WASILibc
#endif

/// The keys of a recorder's settings.
public let AVFormatIDKey = "AVFormatIDKey"
public let AVSampleRateKey = "AVSampleRateKey"
public let AVNumberOfChannelsKey = "AVNumberOfChannelsKey"
public let AVEncoderAudioQualityKey = "AVEncoderAudioQualityKey"
public let AVEncoderBitRateKey = "AVEncoderBitRateKey"
public let AVLinearPCMBitDepthKey = "AVLinearPCMBitDepthKey"

/// A Core Audio format identifier (a four-character code).
public typealias AudioFormatID = UInt32
public let kAudioFormatLinearPCM: AudioFormatID = 0x6C70_636D       // 'lpcm'
public let kAudioFormatAppleLossless: AudioFormatID = 0x616C_6163   // 'alac'
public let kAudioFormatMPEG4AAC: AudioFormatID = 0x6161_6320        // 'aac '

/// An encoder's quality.
public enum AVAudioQuality: Int, Sendable {
    case min = 0
    case low = 0x20
    case medium = 0x40
    case high = 0x60
    case max = 0x7F
}

/// What a recorder tells its delegate.
public protocol AVAudioRecorderDelegate: AnyObject {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool)
    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?)
}

extension AVAudioRecorderDelegate {
    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {}
}

/// An object that records audio from the microphone; here it meters the level and keeps no file.
public class AVAudioRecorder {
    public let url: URL
    public let settings: [String: Any]
    public let format: AVAudioFormat
    public weak var delegate: AVAudioRecorderDelegate?
    /// Whether `updateMeters()` reads the level (Apple's needs it on; here it always may).
    public var isMeteringEnabled = false
    public private(set) var isRecording = false

    private var capture: (any _AVAudioCapture)?
    private var frames = 0
    private var latestRMS: Float = 0
    private var latestPeak: Float = 0
    private var averageDecibels: Float = -160
    private var peakDecibels: Float = -160

    public init(url: URL, settings: [String: Any]) throws {
        self.url = url
        self.settings = settings
        let rate = (settings[AVSampleRateKey] as? Double) ?? Double((settings[AVSampleRateKey] as? Int) ?? 44100)
        let channels = UInt32((settings[AVNumberOfChannelsKey] as? Int) ?? 1)
        format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)
    }

    public init(url: URL, format: AVAudioFormat) throws {
        self.url = url
        self.format = format
        settings = [AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: Int(format.channelCount)]
    }

    /// The seconds recorded since `record()`.
    public var currentTime: TimeInterval { capture.map { Double(frames) / $0.sampleRate } ?? 0 }

    public func prepareToRecord() -> Bool { true }

    /// Opens the microphone; false when there is no host or it cannot open one.
    @discardableResult
    public func record() -> Bool {
        if isRecording { return true }
        guard let open = _AVAudioHost.openMicrophone else { return false }
        nonisolated(unsafe) let recorder = self
        capture = open(1024, { samples, _ in recorder.take(samples) }, { _ in recorder.stop() })
        isRecording = capture != nil
        return isRecording
    }

    @discardableResult
    public func record(forDuration duration: TimeInterval) -> Bool { record() }

    public func pause() {
        capture?.stop()
        capture = nil
        isRecording = false
    }

    public func stop() {
        let was = isRecording
        pause()
        frames = 0
        if was { delegate?.audioRecorderDidFinishRecording(self, successfully: true) }
    }

    /// There is no file to delete.
    @discardableResult
    public func deleteRecording() -> Bool { false }

    /// Reads the level of the latest samples into the meters.
    public func updateMeters() {
        averageDecibels = Self.decibels(latestRMS)
        peakDecibels = Self.decibels(latestPeak)
    }

    /// The level in decibels full scale, -160 (silence) to 0, as of the last `updateMeters()`.
    public func averagePower(forChannel channelNumber: Int) -> Float { averageDecibels }
    public func peakPower(forChannel channelNumber: Int) -> Float { peakDecibels }

    private func take(_ samples: [Float]) {
        frames += samples.count
        guard !samples.isEmpty else { return }
        var sum: Float = 0, peak: Float = 0
        for s in samples {
            sum += s * s
            peak = Swift.max(peak, abs(s))
        }
        latestRMS = (sum / Float(samples.count)).squareRoot()
        latestPeak = peak
    }

    private static func decibels(_ amplitude: Float) -> Float {
        guard amplitude > 0 else { return -160 }
        return Swift.max(20 * Float(log10(Double(amplitude))), -160)
    }
}
