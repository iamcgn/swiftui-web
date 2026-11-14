// Apple's `Accelerate` module for wasm, as far as image code reaches into it: vImage's buffers
// and its box filter over 8-bit pixels, which Kingfisher's blur processor runs three times to
// approximate a Gaussian (Kingfisher reaches EhPanda, GistHub and IceCubes). The filter is
// WebFoundationFormats' `_boxConvolve`, held to Apple's vImage by the host tests. A function
// answers vImage's error codes for the arguments vImage refuses (an even kernel, a region past
// the input, no edge style or more than one).
#if os(WASI)
import WebFoundationFormats

/// A count of pixels.
public typealias vImagePixelCount = UInt
/// Options for a vImage call (`kvImage…` values).
public typealias vImage_Flags = UInt32
/// A vImage call's result: `kvImageNoError`, a negative error, or (with
/// `kvImageGetTempBufferSize`) a size.
public typealias vImage_Error = Int
/// One 8-bit channel.
public typealias Pixel_8 = UInt8
/// Four 8-bit channels.
public typealias Pixel_8888 = (UInt8, UInt8, UInt8, UInt8)

/// An image's pixels in memory: where they start, its size, and the bytes from a row to the next.
public struct vImage_Buffer {
    public var data: UnsafeMutableRawPointer!
    public var height: vImagePixelCount
    public var width: vImagePixelCount
    public var rowBytes: Int
    public init() {
        data = nil
        height = 0
        width = 0
        rowBytes = 0
    }
    public init(data: UnsafeMutableRawPointer!, height: vImagePixelCount, width: vImagePixelCount, rowBytes: Int) {
        self.data = data
        self.height = height
        self.width = width
        self.rowBytes = rowBytes
    }
    /// Frees memory `vImageBuffer_Init` allocated.
    public func free() { data?.deallocate() }
}

public var kvImageNoFlags: Int { 0 }
public var kvImageLeaveAlphaUnchanged: Int { 1 }
public var kvImageCopyInPlace: Int { 2 }
public var kvImageBackgroundColorFill: Int { 4 }
public var kvImageEdgeExtend: Int { 8 }
public var kvImageDoNotTile: Int { 16 }
public var kvImageHighQualityResampling: Int { 32 }
public var kvImageTruncateKernel: Int { 64 }
public var kvImageGetTempBufferSize: Int { 128 }
public var kvImagePrintDiagnosticsToConsole: Int { 256 }
public var kvImageNoAllocate: Int { 512 }

public var kvImageNoError: Int { 0 }
public var kvImageRoiLargerThanInputBuffer: Int { -21766 }
public var kvImageInvalidKernelSize: Int { -21767 }
public var kvImageInvalidEdgeStyle: Int { -21768 }
public var kvImageInvalidOffset_X: Int { -21769 }
public var kvImageInvalidOffset_Y: Int { -21770 }
public var kvImageMemoryAllocationError: Int { -21771 }
public var kvImageNullPointerArgument: Int { -21772 }
public var kvImageInvalidParameter: Int { -21773 }
public var kvImageBufferSizeMismatch: Int { -21774 }
public var kvImageUnknownFlagsBit: Int { -21775 }

/// Allocates `height` rows of `width` pixels of `pixelBits` bits into `buf` (rows a multiple of
/// 16 bytes, as vImage's are).
public func vImageBuffer_Init(_ buf: UnsafeMutablePointer<vImage_Buffer>, _ height: vImagePixelCount, _ width: vImagePixelCount,
                              _ pixelBits: UInt32, _ flags: vImage_Flags) -> vImage_Error {
    guard pixelBits > 0 else { return kvImageInvalidParameter }
    let rowBytes = (Int(width) * Int(pixelBits) + 7) / 8
    let aligned = (rowBytes + 15) / 16 * 16
    if flags & vImage_Flags(kvImageNoAllocate) != 0 {
        buf.pointee = vImage_Buffer(data: buf.pointee.data, height: height, width: width, rowBytes: aligned)
        return kvImageNoError
    }
    let data = UnsafeMutableRawPointer.allocate(byteCount: max(1, aligned * Int(height)), alignment: 16)
    buf.pointee = vImage_Buffer(data: data, height: height, width: width, rowBytes: aligned)
    return kvImageNoError
}

/// The edge style the flags ask for, or vImage's error for none or several.
private func edgeStyle(_ flags: vImage_Flags, background: [UInt8]) -> _BoxEdge? {
    let styles: [(Int, _BoxEdge)] = [(kvImageEdgeExtend, .extend), (kvImageBackgroundColorFill, .background(background)),
                                     (kvImageTruncateKernel, .truncate), (kvImageCopyInPlace, .copyInPlace)]
    let chosen = styles.filter { flags & vImage_Flags($0.0) != 0 }
    return chosen.count == 1 ? chosen[0].1 : nil
}

private func boxConvolve(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                         _ offsetX: vImagePixelCount, _ offsetY: vImagePixelCount, _ kernelHeight: UInt32, _ kernelWidth: UInt32,
                         background: [UInt8], channels: Int, _ flags: vImage_Flags) -> vImage_Error {
    if flags & vImage_Flags(kvImageGetTempBufferSize) != 0 { return 0 }
    let source = src.pointee, target = dest.pointee
    guard let input = source.data, let output = target.data else { return kvImageNullPointerArgument }
    guard kernelWidth % 2 == 1, kernelHeight % 2 == 1 else { return kvImageInvalidKernelSize }
    guard offsetX < source.width else { return kvImageInvalidOffset_X }
    guard offsetY < source.height else { return kvImageInvalidOffset_Y }
    guard offsetX + target.width <= source.width, offsetY + target.height <= source.height else { return kvImageRoiLargerThanInputBuffer }
    guard let edge = edgeStyle(flags, background: background) else { return kvImageInvalidEdgeStyle }
    _boxConvolve(source: UnsafeRawPointer(input), sourceWidth: Int(source.width), sourceHeight: Int(source.height), sourceRowBytes: source.rowBytes,
                 destination: output, width: Int(target.width), height: Int(target.height), destinationRowBytes: target.rowBytes,
                 offsetX: Int(offsetX), offsetY: Int(offsetY), kernelWidth: Int(kernelWidth), kernelHeight: Int(kernelHeight),
                 channels: channels, edge: edge, keepsFirstChannel: channels == 4 && flags & vImage_Flags(kvImageLeaveAlphaUnchanged) != 0)
    return kvImageNoError
}

/// Box-filters four-channel 8-bit pixels: each is the mean of the `kernel_width` by
/// `kernel_height` pixels around it (both odd), from the source region at the offsets.
public func vImageBoxConvolve_ARGB8888(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                       _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount,
                                       _ srcOffsetToROI_Y: vImagePixelCount, _ kernel_height: UInt32, _ kernel_width: UInt32,
                                       _ backgroundColor: UnsafePointer<UInt8>!, _ flags: vImage_Flags) -> vImage_Error {
    let background = backgroundColor.map { Array(UnsafeBufferPointer(start: $0, count: 4)) } ?? [0, 0, 0, 0]
    return boxConvolve(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel_height, kernel_width,
                       background: background, channels: 4, flags)
}

/// Box-filters one-channel 8-bit pixels, as `vImageBoxConvolve_ARGB8888` does four.
public func vImageBoxConvolve_Planar8(_ src: UnsafePointer<vImage_Buffer>, _ dest: UnsafePointer<vImage_Buffer>,
                                      _ tempBuffer: UnsafeMutableRawPointer!, _ srcOffsetToROI_X: vImagePixelCount,
                                      _ srcOffsetToROI_Y: vImagePixelCount, _ kernel_height: UInt32, _ kernel_width: UInt32,
                                      _ backgroundColor: Pixel_8, _ flags: vImage_Flags) -> vImage_Error {
    boxConvolve(src, dest, srcOffsetToROI_X, srcOffsetToROI_Y, kernel_height, kernel_width,
                background: [backgroundColor], channels: 1, flags)
}
#endif
