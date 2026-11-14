// A movie's still images (AVFoundation's AVAssetImageGenerator) over a stand-in for the browser's
// `<video>`: what Kingfisher's AVAssetImageDataProvider calls. Each asked time goes to the host in
// order, with the movie's URL and the maximum size; each answer comes back with its time, the
// frame as an image and the time the frame is from; without a host or a frame the request fails
// with AVFoundation's decode error; cancelling answers what is pending as cancelled; and times
// travel in `NSValue`s.
#if !os(WASI)
import AVFoundation
import AVCaptureHost
import Foundation
import Testing
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Plays the browser's video: keeps each request and answers when told to, or at once.
@MainActor
private enum StandInVideo {
    struct Request { var url: String; var seconds: Double; var maxWidth: Int; var maxHeight: Int; var done: @MainActor (_AVFrame?) -> Void }
    nonisolated(unsafe) static var requests: [Request] = []
    nonisolated(unsafe) static var answersAtOnce = false

    static func install(answersAtOnce: Bool = false) {
        requests = []
        Self.answersAtOnce = answersAtOnce
        _AVFrameHost.frame = { url, seconds, maxWidth, maxHeight, done in
            if StandInVideo.answersAtOnce {
                Task { @MainActor in done(StandInVideo.frame(at: seconds)) }
            } else {
                StandInVideo.requests.append(Request(url: url, seconds: seconds, maxWidth: maxWidth, maxHeight: maxHeight, done: done))
            }
        }
    }

    /// A 4 by 2 frame shown a little after the asked time.
    nonisolated static func frame(at seconds: Double) -> _AVFrame {
        _AVFrame(width: 4, height: 2, rgba: [UInt8](repeating: 200, count: 32), seconds: seconds + 0.02)
    }

    static func answer(_ frame: _AVFrame?) {
        let request = requests.removeFirst()
        request.done(frame)
    }
}

/// What the completion handler was called with.
private final class Answers: @unchecked Sendable {
    var calls: [(requested: Double, width: Int?, actual: Double, result: AVAssetImageGenerator.Result, error: (any Error)?)] = []
}

@MainActor
@Suite(.serialized) struct ImageGeneratorTests {
    let movie = URL(string: "https://example.com/clip.mp4")!

    @Test func framesAreReadInOrder() async {
        StandInVideo.install()
        defer { _AVFrameHost.frame = nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: movie))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 0)
        let answers = Answers()
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: CMTime(seconds: 1, preferredTimescale: 600)),
                                                            NSValue(time: CMTime(seconds: 2.5, preferredTimescale: 600))]) {
            requested, image, actual, result, error in
            answers.calls.append((requested.seconds, image?.width, actual.seconds, result, error))
        }
        // One frame at a time: the second waits for the first.
        #expect(StandInVideo.requests.count == 1)
        #expect(StandInVideo.requests.first?.url == movie.absoluteString)
        #expect(StandInVideo.requests.first?.seconds == 1)
        #expect(StandInVideo.requests.first?.maxWidth == 320)
        #expect(StandInVideo.requests.first?.maxHeight == 0)
        StandInVideo.answer(StandInVideo.frame(at: 1))
        #expect(answers.calls.count == 1)
        #expect(StandInVideo.requests.first?.seconds == 2.5)
        StandInVideo.answer(nil)
        #expect(answers.calls.count == 2)
        #expect(StandInVideo.requests.isEmpty)

        #expect(answers.calls[0].requested == 1)
        #expect(answers.calls[0].result == .succeeded)
        #expect(answers.calls[0].width == 4)
        #expect(abs(answers.calls[0].actual - 1.02) < 0.000_1)
        #expect(answers.calls[0].error == nil)
        // A frame the browser could not read fails with AVFoundation's decode error.
        #expect(answers.calls[1].requested == 2.5)
        #expect(answers.calls[1].result == .failed)
        #expect(answers.calls[1].width == nil)
        #expect((answers.calls[1].error as? AVError)?.code == .decodeFailed)
    }

    @Test func imageAtTimeAwaitsTheFrame() async throws {
        StandInVideo.install(answersAtOnce: true)
        defer { _AVFrameHost.frame = nil }
        let generator = AVAssetImageGenerator(asset: AVAsset(url: movie))
        let (image, actual) = try await generator.image(at: CMTime(seconds: 3, preferredTimescale: 600))
        #expect(image.width == 4)
        #expect(image.height == 2)
        #expect(abs(actual.seconds - 3.02) < 0.000_1)
    }

    @Test func withoutAHostEveryRequestFails() async {
        _AVFrameHost.frame = nil
        let generator = AVAssetImageGenerator(asset: AVAsset(url: movie))
        await #expect(throws: AVError.self) { _ = try await generator.image(at: .zero) }
        #expect(throws: AVError.self) { _ = try generator.copyCGImage(at: .zero, actualTime: nil) }
    }

    @Test func cancellingAnswersWhatIsPending() async {
        StandInVideo.install()
        defer { _AVFrameHost.frame = nil }
        let generator = AVAssetImageGenerator(asset: AVAsset(url: movie))
        let answers = Answers()
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero), NSValue(time: CMTime(seconds: 1, preferredTimescale: 600))]) {
            requested, image, actual, result, error in
            answers.calls.append((requested.seconds, image?.width, actual.seconds, result, error))
        }
        generator.cancelAllCGImageGeneration()
        // The browser's late answer to the first request is dropped.
        StandInVideo.answer(StandInVideo.frame(at: 0))
        for _ in 0..<10 where answers.calls.count < 2 { await Task.yield() }
        #expect(answers.calls.map(\.result) == [.cancelled, .cancelled])
        #expect(answers.calls.map(\.requested) == [0, 1])
        #expect(answers.calls.allSatisfy { $0.error == nil && $0.width == nil })
    }

    @Test func timesTravelInValues() {
        #expect(NSValue(time: CMTime(seconds: 4.25, preferredTimescale: 600)).timeValue.seconds == 4.25)
        #expect(CMTime.positiveInfinity.seconds == .infinity)
        #expect(AVAssetImageGenerator.Result.cancelled.rawValue == 2)
    }
}
#endif
