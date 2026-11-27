// Core Image's images of a pixel buffer, which Apple's CoreImage declares over CoreVideo: a
// camera frame (a video data output's `CVPixelBuffer`) as a `CIImage`, so a capture app can
// filter it or render it with a `CIContext` (OldOS's Camera-SwiftUI flips each frame that way).
// The image is a copy of the buffer's pixels at the time it is made, in the buffer's layout:
// BGRA (what the web camera delivers), ARGB or RGBA, with alpha as it is stored.
#if os(WASI) || !canImport(CoreGraphics)
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import WebGraphics
import WebCoreImage

extension CIImage {
    public convenience init(cvPixelBuffer pixelBuffer: CVPixelBuffer) {
        self.init(cgImage: CGImage(_content: .bitmap(pixelBuffer._displayBitmap)))
    }

    public convenience init(cvPixelBuffer pixelBuffer: CVPixelBuffer, options: [CIImageOption: Any]?) {
        self.init(cvPixelBuffer: pixelBuffer)
    }

    public convenience init(cvImageBuffer imageBuffer: CVImageBuffer) {
        self.init(cvPixelBuffer: imageBuffer)
    }

    public convenience init(cvImageBuffer imageBuffer: CVImageBuffer, options: [CIImageOption: Any]?) {
        self.init(cvPixelBuffer: imageBuffer)
    }
}

extension CVPixelBuffer {
    /// The pixels as RGBA, the order a display bitmap keeps.
    var _displayBitmap: DisplayBitmap {
        let source = UnsafeRawBufferPointer(start: storage, count: bytesPerRow * height)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        // Where red, green, blue and alpha sit in a stored pixel.
        let (r, g, b, a): (Int, Int, Int, Int)
        switch pixelFormatType {
        case kCVPixelFormatType_32ARGB: (r, g, b, a) = (1, 2, 3, 0)
        case kCVPixelFormatType_32RGBA: (r, g, b, a) = (0, 1, 2, 3)
        default: (r, g, b, a) = (2, 1, 0, 3)
        }
        for y in 0..<height {
            for x in 0..<width {
                let s = y * bytesPerRow + x * 4, d = (y * width + x) * 4
                rgba[d] = source[s + r]
                rgba[d + 1] = source[s + g]
                rgba[d + 2] = source[s + b]
                rgba[d + 3] = source[s + a]
            }
        }
        return DisplayBitmap(width: width, height: height, pixels: rgba)
    }
}
#endif
