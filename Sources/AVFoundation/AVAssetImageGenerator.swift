// Still images from a movie: `AVAssetImageGenerator` over the browser's own video decoder. The
// host (`_AVFrameHost`, which SwiftUIWebCanvas installs) loads the asset's URL in a hidden
// `<video>`, seeks to each asked time and draws that frame, scaled down to the generator's
// `maximumSize`; Kingfisher's `AVAssetImageDataProvider` makes video thumbnails this way. Frames
// are read one at a time in the order asked, and each answer comes on the main actor. A
// synchronous `copyCGImage(at:actualTime:)` cannot wait for the browser, so it throws, as Apple's
// does for an asset it cannot decode; `image(at:)` and the asynchronous calls are the way here.
// Without a host (or for a movie the browser cannot play) each request fails with
// `AVError.decodeFailed`.
#if os(WASI)
import WebFoundation
// Apple's AVFoundation re-exports ImageIO. Here it re-exports the image sources (WebImageIO, which
// every app links anyway) but not the destinations: those bring Foundation's NSMutableData module,
// about 800 KB that every app using AVFoundation would carry (the Gallery's size gate). A file
// that writes images with only AVKit imported (Kingfisher's video thumbnail JPEG) needs
// `import ImageIO`.
@_exported import WebImageIO
#else
import Foundation
#endif
#if canImport(CoreGraphics) && !os(WASI)
import CoreGraphics
#endif
import UIKitWebCore
import AVCaptureHost

/// What `generateCGImagesAsynchronously(forTimes:completionHandler:)` calls for each asked time:
/// the time asked, the image, the time the image is from, how it went, and the error.
public typealias AVAssetImageGeneratorCompletionHandler = @Sendable (CMTime, CGImage?, CMTime, AVAssetImageGenerator.Result, (any Error)?) -> Void

/// Makes still images of an asset's frames.
open class AVAssetImageGenerator: NSObject, @unchecked Sendable {
    /// How a request ended.
    public enum Result: Int, Sendable {
        case succeeded = 0
        case failed = 1
        case cancelled = 2
    }

    /// The aperture a frame is cropped to (the host draws the whole picture).
    public struct ApertureMode: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let cleanAperture = ApertureMode(rawValue: "CleanAperture")
        public static let productionAperture = ApertureMode(rawValue: "ProductionAperture")
        public static let encodedPixels = ApertureMode(rawValue: "EncodedPixels")
    }

    /// How a frame is chosen when no frame is exactly at the asked time.
    public struct DynamicRangePolicy: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let forceSDR = DynamicRangePolicy(rawValue: "DynamicRangePolicyForceSDR")
        public static let matchSource = DynamicRangePolicy(rawValue: "DynamicRangePolicyMatchSource")
    }

    /// The asset the images are of.
    public let asset: AVAsset
    /// Whether the track's orientation is applied (the browser draws a frame upright either way).
    open var appliesPreferredTrackTransform = false
    /// The largest size an image may be; a zero side leaves that side free, and `.zero` keeps the
    /// frame's own size. A frame is scaled down to fit, keeping its shape.
    open var maximumSize: CGSize = .zero
    open var apertureMode: ApertureMode? = .cleanAperture
    open var dynamicRangePolicy: DynamicRangePolicy = .forceSDR
    /// How far before and after the asked time the frame may be (the browser seeks to the frame it
    /// shows at that time).
    open var requestedTimeToleranceBefore: CMTime = .positiveInfinity
    open var requestedTimeToleranceAfter: CMTime = .positiveInfinity

    /// One request's answer (a box, as an image is not Sendable everywhere).
    private struct Answer: @unchecked Sendable {
        var image: CGImage?
        var actualTime: CMTime
        var result: Result
        var error: (any Error)?
    }
    private var queue: [(time: CMTime, answer: @Sendable (Answer) -> Void)] = []
    private var reading = false
    private var generation = 0

    public init(asset: AVAsset) {
        self.asset = asset
        super.init()
    }

    /// Reads the frame at each time, calling `handler` once for each, in order.
    open func generateCGImagesAsynchronously(forTimes requestedTimes: [NSValue],
                                             completionHandler handler: @escaping AVAssetImageGeneratorCompletionHandler) {
        for value in requestedTimes {
            let time = value.timeValue
            enqueue(time) { answer in handler(time, answer.image, answer.actualTime, answer.result, answer.error) }
        }
    }

    /// The frame at `time`, and the time it is from.
    open func image(at time: CMTime) async throws -> (image: CGImage, actualTime: CMTime) {
        let answer = await withCheckedContinuation { (continuation: CheckedContinuation<Answer, Never>) in
            enqueue(time) { continuation.resume(returning: $0) }
        }
        guard let image = answer.image, answer.result == .succeeded else { throw answer.error ?? CancellationError() }
        return (image, answer.actualTime)
    }

    /// The frame at `time`, read synchronously: the browser answers only later, so this throws.
    open func copyCGImage(at requestedTime: CMTime, actualTime: UnsafeMutablePointer<CMTime>?) throws -> CGImage {
        throw AVError(.operationNotSupportedForAsset, userInfo: [AVErrorTimeKey: requestedTime])
    }

    /// Ends every request not yet answered; each is answered as cancelled.
    open func cancelAllCGImageGeneration() {
        generation += 1
        let pending = queue
        queue = []
        reading = false
        for request in pending {
            Self.onMain { request.answer(Answer(image: nil, actualTime: .invalid, result: .cancelled)) }
        }
    }

    // MARK: Reading

    private func enqueue(_ time: CMTime, _ answer: @escaping @Sendable (Answer) -> Void) {
        queue.append((time, answer))
        if !reading { readNext() }
    }

    private func readNext() {
        guard !queue.isEmpty else { reading = false; return }
        reading = true
        let request = queue[0]
        let current = generation
        let finish: @Sendable (Answer) -> Void = { [weak self] answer in
            guard let self, self.generation == current, !self.queue.isEmpty else { return }
            self.queue.removeFirst()
            request.answer(answer)
            self.readNext()
        }
        let failed = Answer(image: nil, actualTime: .invalid, result: .failed, error: AVError(.decodeFailed, userInfo: [AVErrorTimeKey: request.time]))
        guard let host = _AVFrameHost.frame, request.time.isValid, request.time.seconds >= 0 else {
            Self.onMain { finish(failed) }
            return
        }
        let size = maximumSize
        host(asset.url.absoluteString, request.time.seconds, Self.side(size.width), Self.side(size.height)) { frame in
            guard let frame, let image = Self.image(frame) else { finish(failed); return }
            finish(Answer(image: image, actualTime: CMTime(seconds: frame.seconds, preferredTimescale: 600), result: .succeeded))
        }
    }

    /// A side of `maximumSize` in whole pixels; 0 for a free side.
    private static func side(_ value: CGFloat) -> Int {
        value.isFinite && value >= 1 ? Int(value) : 0
    }

    private static func image(_ frame: _AVFrame) -> CGImage? {
        guard frame.width > 0, frame.height > 0, frame.rgba.count >= frame.width * frame.height * 4 else { return nil }
        #if os(WASI) || !canImport(CoreGraphics)
        guard let provider = CGDataProvider(data: Data(frame.rgba)) else { return nil }
        #else
        guard let provider = CGDataProvider(data: Data(frame.rgba) as CFData) else { return nil }
        #endif
        return CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// Runs `body` on the main actor later, never from within the caller.
    private static func onMain(_ body: @escaping @Sendable () -> Void) {
        Task { @MainActor in body() }
    }
}

// MARK: - Times in values

#if os(WASI)
extension NSValue {
    /// A time, boxed (the times `generateCGImagesAsynchronously(forTimes:)` takes).
    public convenience init(time: CMTime) { self.init(_webValue: time) }
    /// The time this value holds; `.invalid` for any other value.
    public var timeValue: CMTime { (_webValue as? CMTime) ?? .invalid }
}
#else
extension NSValue {
    /// A time, boxed (the times `generateCGImagesAsynchronously(forTimes:)` takes): its seconds.
    public convenience init(time: CMTime) {
        var seconds = time.seconds
        self.init(bytes: &seconds, objCType: "d")
    }
    /// The time this value holds.
    public var timeValue: CMTime {
        var seconds = Double.nan
        #if canImport(Darwin)
        getValue(&seconds, size: MemoryLayout<Double>.size)
        #else
        getValue(&seconds)
        #endif
        return CMTime(seconds: seconds)
    }
}
#endif
