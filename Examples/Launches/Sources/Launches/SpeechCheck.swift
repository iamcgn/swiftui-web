// The Speech framework driven as an app drives it (decision 0022, pf-speech), from a committed
// recording instead of a microphone: `?speech=<fixture>` decodes `fixtures/<fixture>` (16-bit
// PCM WAV), asks authorisation (the host installs the locale's pack), appends the frames to an
// `SFSpeechAudioBufferRecognitionRequest` in 1024-frame `AVAudioPCMBuffer`s at the file's rate
// — the way an audio tap delivers them — and ends the audio; the line shows what came back and
// when. `?speech=silence` appends two seconds of zeros, `?speech=none` nothing; `&cancel=1`
// cancels the task at its first partial result. The probe (Playwright/speech-probe.mjs) reads
// the line: the words must be the file's, must appear only after the frames did, and silence,
// nothing and a cancel must leave no words.
import AVFoundation
import Foundation
import Speech
import SwiftUI

@MainActor
final class SpeechCheck: ObservableObject {
    @Published var summary = ""

    static var fixture: String? { PageAddresses.query("speech") }
    static var cancels: Bool { PageAddresses.query("cancel") == "1" }

    func run() {
        guard let fixture = Self.fixture else { return }
        summary = "speech: starting"
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))
        guard let recognizer else { summary = "speech: no recognizer"; return }
        let started = Date()
        let stamp = { Int(Date().timeIntervalSince(started) * 1000) }
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor in
                let available = recognizer.isAvailable
                guard status == .authorized, available else {
                    self.summary = "speech: auth=\(status) available=\(available)"
                    return
                }
                let frames: ([Float], Double)
                switch fixture {
                case "none": frames = ([], 16_000)
                case "silence": frames = (Array(repeating: 0, count: 32_000), 16_000)
                default:
                    guard let decoded = await Self.decode(fixture) else { self.summary = "speech: fixture \(fixture) unreadable"; return }
                    frames = decoded
                }
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                request.taskHint = .dictation
                var partials = 0
                var firstResultAt: Int?
                var appendedAt: Int?
                var final: String?
                var finalAt: Int?
                var failure: String?
                var task: SFSpeechRecognitionTask?
                let show = {
                    var parts = ["speech: auth=authorized available=true frames=\(frames.0.count)@\(Int(frames.1))"]
                    if let appendedAt { parts.append("appended=\(appendedAt)ms") }
                    parts.append("partials=\(partials)")
                    if let firstResultAt { parts.append("first=\(firstResultAt)ms") }
                    // Brackets, not quotes: the probe reads the line out of the display list's quoted text.
                    if let final, let finalAt { parts.append("final=[\(final)] at=\(finalAt)ms") }
                    if let task, task.isCancelled { parts.append("cancelled") }
                    if let failure { parts.append("error=\(failure)") }
                    self.summary = parts.joined(separator: " ")
                }
                task = recognizer.recognitionTask(with: request) { result, error in
                    if let error { failure = "\(error)"; show(); return }
                    guard let result else { return }
                    if firstResultAt == nil { firstResultAt = stamp() }
                    if result.isFinal {
                        final = result.bestTranscription.formattedString
                        finalAt = stamp()
                    } else {
                        partials += 1
                        if Self.cancels, partials == 1 { task?.cancel() }
                    }
                    show()
                }
                show()
                // A tap's cadence: 1024 frames per buffer, at the file's rate.
                var index = 0
                let format = AVAudioFormat(standardFormatWithSampleRate: frames.1, channels: 1)
                while index < frames.0.count {
                    let end = min(index + 1024, frames.0.count)
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(end - index)), let channel = buffer.floatChannelData?[0] else { break }
                    for (offset, sample) in frames.0[index..<end].enumerated() { channel[offset] = sample }
                    buffer.frameLength = AVAudioFrameCount(end - index)
                    request.append(buffer)
                    index = end
                }
                appendedAt = stamp()
                request.endAudio()
                show()
            }
        }
    }

    /// `fixtures/<name>`: a 16-bit PCM WAV's first channel as floats, with its sample rate.
    private static func decode(_ name: String) async -> ([Float], Double)? {
        guard let url = URL(string: PageAddresses.origin + "/fixtures/" + name),
              let (data, _) = try? await URLSession.shared.data(from: url), data.count > 44 else { return nil }
        let bytes = [UInt8](data)
        guard String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF", String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        var offset = 12
        var channels = 1, rate = 16_000.0, bits = 16
        var samples: [Float] = []
        let u16 = { (at: Int) in Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        let u32 = { (at: Int) in u16(at) | u16(at + 2) << 16 }
        while offset + 8 <= bytes.count {
            let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
            let size = u32(offset + 4)
            let body = offset + 8
            if id == "fmt " {
                channels = max(1, u16(body + 2))
                rate = Double(u32(body + 4))
                bits = u16(body + 14)
            } else if id == "data" {
                guard bits == 16 else { return nil }
                let end = min(body + size, bytes.count)
                let frameBytes = 2 * channels
                samples.reserveCapacity((end - body) / frameBytes)
                var at = body
                while at + 1 < end {
                    samples.append(Float(Int16(truncatingIfNeeded: u16(at))) / 32768)
                    at += frameBytes
                }
            }
            offset = body + size + (size & 1)
        }
        return samples.isEmpty ? nil : (samples, rate)
    }
}
