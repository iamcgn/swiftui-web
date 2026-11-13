// The CoreVideo and CoreMedia names a camera app's frames arrive in, which Apple's AVFoundation
// brings with it: `CMSampleBuffer` holding a `CVPixelBuffer` of BGRA pixels (the one format the
// web camera delivers), the lock, base address and size functions code reads pixels with, and the
// pixel format constants it asks for them by.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

public typealias OSType = UInt32
public typealias CVReturn = Int32
public let kCVReturnSuccess: CVReturn = 0
public let kCVReturnError: CVReturn = -6660
public let kCVReturnInvalidArgument: CVReturn = -6661

// MARK: - Pixel formats

public let kCVPixelFormatType_32ARGB: OSType = 0x0000_0020
public let kCVPixelFormatType_32BGRA: OSType = 0x4247_5241   // 'BGRA'
public let kCVPixelFormatType_32RGBA: OSType = 0x5247_4241   // 'RGBA'
public let kCVPixelFormatType_24RGB: OSType = 0x0000_0018
public let kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: OSType = 0x3432_3076   // '420v'
public let kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: OSType = 0x3432_3066    // '420f'
public let kCVPixelFormatType_OneComponent8: OSType = 0x4C30_3038   // 'L008'

/// Keys of the pixel buffer attributes (`videoSettings`, `previewPhotoFormat`): strings here,
/// which `as String` leaves as they are.
public let kCVPixelBufferPixelFormatTypeKey = "PixelFormatType"
public let kCVPixelBufferWidthKey = "Width"
public let kCVPixelBufferHeightKey = "Height"
public let kCVPixelBufferBytesPerRowAlignmentKey = "BytesPerRowAlignment"
public let kCVPixelBufferCGImageCompatibilityKey = "CGImageCompatibility"
public let kCVPixelBufferCGBitmapContextCompatibilityKey = "CGBitmapContextCompatibility"
public let kCVPixelBufferIOSurfacePropertiesKey = "IOSurfaceProperties"

// MARK: - CVPixelBuffer

/// An image's pixels in memory: rows of `bytesPerRow` bytes, four a pixel.
public final class CVPixelBuffer: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let pixelFormatType: OSType
    let storage: UnsafeMutableRawPointer
    var locks = 0

    /// A buffer holding a copy of the bytes (`width * 4` a row).
    public init(width: Int, height: Int, pixelFormatType: OSType = kCVPixelFormatType_32BGRA, bytes: [UInt8]) {
        self.width = max(width, 0)
        self.height = max(height, 0)
        self.bytesPerRow = self.width * 4
        self.pixelFormatType = pixelFormatType
        let size = max(self.bytesPerRow * self.height, 1)
        storage = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
        storage.initializeMemory(as: UInt8.self, repeating: 0, count: size)
        bytes.withUnsafeBytes { source in
            if let base = source.baseAddress { storage.copyMemory(from: base, byteCount: min(source.count, size)) }
        }
    }

    deinit { storage.deallocate() }

    /// The pixels as bytes (a copy).
    public var bytes: [UInt8] {
        Array(UnsafeRawBufferPointer(start: storage, count: bytesPerRow * height))
    }
}

public typealias CVImageBuffer = CVPixelBuffer
public typealias CVBuffer = CVPixelBuffer

public struct CVPixelBufferLockFlags: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let readOnly = CVPixelBufferLockFlags(rawValue: 1)
}

@discardableResult
public func CVPixelBufferLockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ lockFlags: CVPixelBufferLockFlags) -> CVReturn {
    pixelBuffer.locks += 1
    return kCVReturnSuccess
}

@discardableResult
public func CVPixelBufferUnlockBaseAddress(_ pixelBuffer: CVPixelBuffer, _ unlockFlags: CVPixelBufferLockFlags) -> CVReturn {
    guard pixelBuffer.locks > 0 else { return kCVReturnError }
    pixelBuffer.locks -= 1
    return kCVReturnSuccess
}

public func CVPixelBufferGetBaseAddress(_ pixelBuffer: CVPixelBuffer) -> UnsafeMutableRawPointer? { pixelBuffer.storage }
public func CVPixelBufferGetWidth(_ pixelBuffer: CVPixelBuffer) -> Int { pixelBuffer.width }
public func CVPixelBufferGetHeight(_ pixelBuffer: CVPixelBuffer) -> Int { pixelBuffer.height }
public func CVPixelBufferGetBytesPerRow(_ pixelBuffer: CVPixelBuffer) -> Int { pixelBuffer.bytesPerRow }
public func CVPixelBufferGetDataSize(_ pixelBuffer: CVPixelBuffer) -> Int { pixelBuffer.bytesPerRow * pixelBuffer.height }
public func CVPixelBufferGetPixelFormatType(_ pixelBuffer: CVPixelBuffer) -> OSType { pixelBuffer.pixelFormatType }
public func CVPixelBufferIsPlanar(_ pixelBuffer: CVPixelBuffer) -> Bool { false }
public func CVPixelBufferGetPlaneCount(_ pixelBuffer: CVPixelBuffer) -> Int { 0 }

// MARK: - CMSampleBuffer

/// The size of a video's frames.
public struct CMVideoDimensions: Hashable, Sendable {
    public var width: Int32
    public var height: Int32
    public init() { width = 0; height = 0 }
    public init(width: Int32, height: Int32) { self.width = width; self.height = height }
}

/// One frame a video data output delivers: its pixels and when it was captured.
public final class CMSampleBuffer: @unchecked Sendable {
    public let imageBuffer: CVImageBuffer?
    public let presentationTimeStamp: CMTime
    public var duration: CMTime { .invalid }
    public var decodeTimeStamp: CMTime { .invalid }
    public var isValid: Bool { true }
    public var numSamples: Int { 1 }

    public init(imageBuffer: CVImageBuffer?, presentationTimeStamp: CMTime) {
        self.imageBuffer = imageBuffer
        self.presentationTimeStamp = presentationTimeStamp
    }
}

public func CMSampleBufferGetImageBuffer(_ sbuf: CMSampleBuffer) -> CVImageBuffer? { sbuf.imageBuffer }
public func CMSampleBufferGetPresentationTimeStamp(_ sbuf: CMSampleBuffer) -> CMTime { sbuf.presentationTimeStamp }
public func CMSampleBufferGetDuration(_ sbuf: CMSampleBuffer) -> CMTime { sbuf.duration }
public func CMSampleBufferIsValid(_ sbuf: CMSampleBuffer) -> Bool { sbuf.isValid }
public func CMSampleBufferGetNumSamples(_ sbuf: CMSampleBuffer) -> Int { sbuf.numSamples }
