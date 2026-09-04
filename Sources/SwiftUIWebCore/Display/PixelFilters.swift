// Pixel operations painters share for `DisplayFilter`: a Gaussian blur over premultiplied
// 8-bit RGBA rows. The browser painter uses the canvas blur where it exists; the CoreGraphics
// painter (and any host without a native blur) uses this.

public enum PixelFilters {
    /// The taps of a normalised Gaussian kernel with the given sigma (in pixels), three sigma
    /// each side; a single tap for sigma ≤ 0.
    public static func gaussianKernel(sigma: Double) -> [Double] {
        guard sigma > 0 else { return [1] }
        let radius = Int((sigma * 3).rounded(.up))
        var taps = (-radius...radius).map { _exp(-Double($0 * $0) / (2 * sigma * sigma)) }
        let sum = taps.reduce(0, +)
        for i in taps.indices { taps[i] /= sum }
        return taps
    }

    /// Blurs premultiplied RGBA8 pixels in place (rows of `width` pixels, `height` rows, packed).
    /// Outside the bitmap counts as transparent. With `keepAlpha` the alpha channel is left as
    /// it was and the colours are blurred as if every neighbour inside the content were opaque
    /// (an edge-normalised blur), which is SwiftUI's `blur(radius:opaque: true)`.
    public static func gaussianBlur(_ pixels: UnsafeMutableBufferPointer<UInt8>, width: Int, height: Int, sigma: Double, keepAlpha: Bool) {
        guard width > 0, height > 0, sigma > 0, pixels.count >= width * height * 4 else { return }
        let kernel = gaussianKernel(sigma: sigma)
        let radius = kernel.count / 2
        let count = width * height * 4
        var source = [Float](repeating: 0, count: count)
        for i in 0..<count { source[i] = Float(pixels[i]) }
        var pass = [Float](repeating: 0, count: count)
        // Horizontal pass into `pass`, vertical pass back into `source`.
        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for (k, weight) in kernel.enumerated() {
                    let sx = x + k - radius
                    guard sx >= 0, sx < width else { continue }
                    let w = Float(weight), o = (row + sx) * 4
                    r += source[o] * w; g += source[o + 1] * w; b += source[o + 2] * w; a += source[o + 3] * w
                }
                let o = (row + x) * 4
                pass[o] = r; pass[o + 1] = g; pass[o + 2] = b; pass[o + 3] = a
            }
        }
        for x in 0..<width {
            for y in 0..<height {
                var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                for (k, weight) in kernel.enumerated() {
                    let sy = y + k - radius
                    guard sy >= 0, sy < height else { continue }
                    let w = Float(weight), o = (sy * width + x) * 4
                    r += pass[o] * w; g += pass[o + 1] * w; b += pass[o + 2] * w; a += pass[o + 3] * w
                }
                let o = (y * width + x) * 4
                if keepAlpha {
                    let original = Float(pixels[o + 3])
                    if a > 0, original > 0 {
                        let factor = original / a
                        pixels[o] = clamp(r * factor); pixels[o + 1] = clamp(g * factor); pixels[o + 2] = clamp(b * factor)
                    }
                } else {
                    pixels[o] = clamp(r); pixels[o + 1] = clamp(g); pixels[o + 2] = clamp(b); pixels[o + 3] = clamp(a)
                }
            }
        }
    }

    private static func clamp(_ value: Float) -> UInt8 {
        UInt8(min(255, max(0, value.rounded())))
    }
}
