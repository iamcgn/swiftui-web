// The box filter the `Accelerate` shadow's vImage calls run (WebFoundationFormats'
// BoxConvolve.swift): every edge style matches the filter's definition worked pixel by pixel,
// for one and four channels, kernels wider and taller than the image, and a region off the
// image's corner; and on macOS, where Apple's vImage is at hand, the bytes match vImage's.
import Testing
@testable import WebFoundationFormats
#if canImport(Accelerate)
import Accelerate
#endif

@Suite struct BoxConvolveTests {
    static let width = 13, height = 9

    /// Bytes from a fixed generator, so every run filters the same image.
    static func image(channels: Int) -> [UInt8] {
        var state: UInt32 = 12_345
        return (0..<(width * height * channels)).map { _ in
            state = state &* 1_103_515_245 &+ 12_345
            return UInt8(truncatingIfNeeded: state >> 16)
        }
    }

    struct Case: Sendable {
        var channels: Int
        var offsetX: Int, offsetY: Int
        var outWidth: Int, outHeight: Int
        var kernelWidth: Int, kernelHeight: Int
    }

    static let cases: [Case] = [
        Case(channels: 4, offsetX: 0, offsetY: 0, outWidth: 13, outHeight: 9, kernelWidth: 5, kernelHeight: 3),
        Case(channels: 4, offsetX: 2, offsetY: 1, outWidth: 9, outHeight: 7, kernelWidth: 3, kernelHeight: 7),
        Case(channels: 4, offsetX: 0, offsetY: 0, outWidth: 13, outHeight: 9, kernelWidth: 31, kernelHeight: 21),
        Case(channels: 1, offsetX: 1, offsetY: 3, outWidth: 12, outHeight: 6, kernelWidth: 9, kernelHeight: 5),
        Case(channels: 4, offsetX: 4, offsetY: 4, outWidth: 1, outHeight: 1, kernelWidth: 1, kernelHeight: 1),
    ]

    static let edges: [_BoxEdge] = [.extend, .background([10, 200, 30, 250]), .truncate, .copyInPlace]

    /// The filter by its definition: every pixel the mean of its kernel's pixels, rounded.
    static func definition(_ input: [UInt8], _ c: Case, _ edge: _BoxEdge, keepsFirst: Bool) -> [UInt8] {
        let rw = c.kernelWidth / 2, rh = c.kernelHeight / 2, n = c.channels
        var out = [UInt8](repeating: 0, count: c.outWidth * c.outHeight * n)
        for y in 0..<c.outHeight {
            for x in 0..<c.outWidth {
                let cx = c.offsetX + x, cy = c.offsetY + y
                let crosses = cx - rw < 0 || cx + rw >= width || cy - rh < 0 || cy + rh >= height
                for ch in 0..<n {
                    let own = input[(cy * width + cx) * n + ch]
                    if (keepsFirst && ch == 0) || (edge == .copyInPlace && crosses) {
                        out[(y * c.outWidth + x) * n + ch] = own
                        continue
                    }
                    var sum = 0, count = 0
                    for yy in (cy - rh)...(cy + rh) {
                        for xx in (cx - rw)...(cx + rw) {
                            let inside = xx >= 0 && xx < width && yy >= 0 && yy < height
                            switch edge {
                            case .extend, .copyInPlace:
                                let sx = min(max(xx, 0), width - 1), sy = min(max(yy, 0), height - 1)
                                sum += Int(input[(sy * width + sx) * n + ch]); count += 1
                            case .background(let colour):
                                sum += inside ? Int(input[(yy * width + xx) * n + ch]) : Int(colour[ch]); count += 1
                            case .truncate:
                                if inside { sum += Int(input[(yy * width + xx) * n + ch]); count += 1 }
                            }
                        }
                    }
                    out[(y * c.outWidth + x) * n + ch] = UInt8((sum + count / 2) / count)
                }
            }
        }
        return out
    }

    static func filtered(_ input: [UInt8], _ c: Case, _ edge: _BoxEdge, keepsFirst: Bool) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: c.outWidth * c.outHeight * c.channels)
        input.withUnsafeBytes { source in
            out.withUnsafeMutableBytes { destination in
                _boxConvolve(source: source.baseAddress!, sourceWidth: width, sourceHeight: height, sourceRowBytes: width * c.channels,
                             destination: destination.baseAddress!, width: c.outWidth, height: c.outHeight,
                             destinationRowBytes: c.outWidth * c.channels, offsetX: c.offsetX, offsetY: c.offsetY,
                             kernelWidth: c.kernelWidth, kernelHeight: c.kernelHeight, channels: c.channels,
                             edge: edge, keepsFirstChannel: keepsFirst)
            }
        }
        return out
    }

    @Test func everyEdgeStyleMatchesTheDefinition() {
        for c in Self.cases {
            let input = Self.image(channels: c.channels)
            for edge in Self.edges {
                for keeps in c.channels == 4 ? [false, true] : [false] {
                    #expect(Self.filtered(input, c, edge, keepsFirst: keeps) == Self.definition(input, c, edge, keepsFirst: keeps),
                            "\(c) \(edge) keepsFirst \(keeps)")
                }
            }
        }
    }

    @Test func uniformImageStaysUniform() {
        let input = [UInt8](repeating: 128, count: Self.width * Self.height * 4)
        let c = Case(channels: 4, offsetX: 0, offsetY: 0, outWidth: 13, outHeight: 9, kernelWidth: 7, kernelHeight: 7)
        #expect(Self.filtered(input, c, .extend, keepsFirst: false) == input)
    }

    #if canImport(Accelerate)
    /// The same filter by Apple's vImage.
    static func apple(_ input: [UInt8], _ c: Case, flags: Int, background: [UInt8]) -> [UInt8] {
        var bytes = input
        var out = [UInt8](repeating: 0, count: c.outWidth * c.outHeight * c.channels)
        let error = bytes.withUnsafeMutableBytes { source in
            out.withUnsafeMutableBytes { destination in
                var src = vImage_Buffer(data: source.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                        rowBytes: width * c.channels)
                var dest = vImage_Buffer(data: destination.baseAddress, height: vImagePixelCount(c.outHeight),
                                         width: vImagePixelCount(c.outWidth), rowBytes: c.outWidth * c.channels)
                if c.channels == 4 {
                    return background.withUnsafeBufferPointer { colour in
                        vImageBoxConvolve_ARGB8888(&src, &dest, nil, vImagePixelCount(c.offsetX), vImagePixelCount(c.offsetY),
                                                   UInt32(c.kernelHeight), UInt32(c.kernelWidth), colour.baseAddress, vImage_Flags(flags))
                    }
                }
                return vImageBoxConvolve_Planar8(&src, &dest, nil, vImagePixelCount(c.offsetX), vImagePixelCount(c.offsetY),
                                                 UInt32(c.kernelHeight), UInt32(c.kernelWidth), background[0], vImage_Flags(flags))
            }
        }
        #expect(error == kvImageNoError)
        return out
    }

    @Test func matchesApplesVImage() {
        let styles: [(Int, _BoxEdge)] = [(kvImageEdgeExtend, .extend), (kvImageBackgroundColorFill, .background([10, 200, 30, 250])),
                                         (kvImageTruncateKernel, .truncate), (kvImageCopyInPlace, .copyInPlace)]
        for c in Self.cases {
            let input = Self.image(channels: c.channels)
            for (flag, edge) in styles {
                let background: [UInt8] = [10, 200, 30, 250]   // one channel takes the first
                #expect(Self.filtered(input, c, edge, keepsFirst: false) == Self.apple(input, c, flags: flag, background: background),
                        "\(c) \(edge)")
                if c.channels == 4 {
                    #expect(Self.filtered(input, c, edge, keepsFirst: true)
                            == Self.apple(input, c, flags: flag | kvImageLeaveAlphaUnchanged, background: background), "\(c) \(edge) alpha")
                }
            }
        }
    }
    #endif
}
