// The box filter Accelerate's `vImageBoxConvolve_ARGB8888` and `_Planar8` run, for the
// `Accelerate` shadow (Packages/Shadows): each output pixel is the mean of the kernel's rectangle
// of input pixels around it, rounded to the nearest. The sums are kept whole (a row's sums, then
// a running sum of the kernel's rows), so a large kernel costs no more than a small one: Kingfisher
// blurs an image with three passes of a kernel tens of pixels wide. The four edge styles are
// vImage's: extend the edge pixels, fill with a background colour, average only the pixels inside
// the image (truncate the kernel), or copy the input pixel where the kernel leaves the image.
// Not limited to wasm, so the host tests hold the results to Apple's vImage.

/// What a box filter does where its kernel reaches past the image's edge.
public enum _BoxEdge: Equatable, Sendable {
    /// The nearest edge pixel stands in for a pixel past the edge.
    case extend
    /// The colour (one value for each channel) stands in for a pixel past the edge.
    case background([UInt8])
    /// Only the pixels inside the image are averaged.
    case truncate
    /// Where the kernel reaches past the edge, the input pixel is copied unchanged.
    case copyInPlace
}

/// Box-filters `width` by `height` pixels of `channels` bytes each into `destination`, from the
/// source rectangle at (`offsetX`, `offsetY`) of an image `sourceWidth` by `sourceHeight`.
/// `kernelWidth` and `kernelHeight` are odd. With `keepsFirstChannel` the first channel (ARGB's
/// alpha) is copied from the input instead of filtered.
public func _boxConvolve(source: UnsafeRawPointer, sourceWidth: Int, sourceHeight: Int, sourceRowBytes: Int,
                         destination: UnsafeMutableRawPointer, width: Int, height: Int, destinationRowBytes: Int,
                         offsetX: Int, offsetY: Int, kernelWidth: Int, kernelHeight: Int, channels: Int,
                         edge: _BoxEdge, keepsFirstChannel: Bool = false) {
    guard width > 0, height > 0, channels > 0 else { return }
    let rw = kernelWidth / 2, rh = kernelHeight / 2
    let input = source.assumingMemoryBound(to: UInt8.self)
    let output = destination.assumingMemoryBound(to: UInt8.self)
    var background = [UInt64](repeating: 0, count: channels)
    if case .background(let colour) = edge {
        for c in 0..<min(channels, colour.count) { background[c] = UInt64(colour[c]) }
    }

    // Channel `c` of the source pixel at (x, y), which may be past the edge (where a truncated
    // kernel counts nothing).
    @inline(__always) func sample(_ x: Int, _ y: Int, _ c: Int) -> UInt64 {
        let inside = x >= 0 && x < sourceWidth && y >= 0 && y < sourceHeight
        switch edge {
        case .extend, .copyInPlace:
            let cx = min(max(x, 0), sourceWidth - 1), cy = min(max(y, 0), sourceHeight - 1)
            return UInt64(input[cy * sourceRowBytes + cx * channels + c])
        case .background:
            return inside ? UInt64(input[y * sourceRowBytes + x * channels + c]) : background[c]
        case .truncate:
            return inside ? UInt64(input[y * sourceRowBytes + x * channels + c]) : 0
        }
    }

    // Each kernel row's sums across the kernel, for every output column: one row for each source
    // row from offsetY - rh to offsetY + height - 1 + rh, kept in a ring of kernelHeight rows.
    let span = width + 2 * rw
    var ring = [[UInt64]](repeating: [UInt64](repeating: 0, count: width * channels), count: kernelHeight)
    var running = [UInt64](repeating: 0, count: width * channels)
    var line = [UInt64](repeating: 0, count: (span + 1) * channels)

    func rowSums(_ y: Int, into sums: inout [UInt64]) {
        // Prefix sums of the row's samples from column offsetX - rw.
        for c in 0..<channels { line[c] = 0 }
        for i in 0..<span {
            for c in 0..<channels {
                line[(i + 1) * channels + c] = line[i * channels + c] + sample(offsetX - rw + i, y, c)
            }
        }
        for x in 0..<width {
            for c in 0..<channels {
                sums[x * channels + c] = line[(x + kernelWidth) * channels + c] - line[x * channels + c]
            }
        }
    }

    // How many of a window's columns or rows are inside the image (the truncated kernel's divisor).
    @inline(__always) func insideCount(_ center: Int, _ radius: Int, _ size: Int) -> UInt64 {
        UInt64(max(0, min(center + radius, size - 1) - max(center - radius, 0) + 1))
    }

    for k in 0..<(kernelHeight - 1) {
        rowSums(offsetY - rh + k, into: &ring[k])
        for i in 0..<running.count { running[i] += ring[k][i] }
    }
    let full = UInt64(kernelWidth * kernelHeight)
    for y in 0..<height {
        let incoming = (y + kernelHeight - 1) % kernelHeight
        rowSums(offsetY + y + rh, into: &ring[incoming])
        for i in 0..<running.count { running[i] += ring[incoming][i] }

        let cy = offsetY + y
        let rows = edge == .truncate ? insideCount(cy, rh, sourceHeight) : UInt64(kernelHeight)
        let rowInside = cy - rh >= 0 && cy + rh < sourceHeight
        let out = output + y * destinationRowBytes
        for x in 0..<width {
            let cx = offsetX + x
            let copies = edge == .copyInPlace && !(rowInside && cx - rw >= 0 && cx + rw < sourceWidth)
            let divisor = edge == .truncate ? insideCount(cx, rw, sourceWidth) * rows : full
            for c in 0..<channels {
                if copies || (keepsFirstChannel && c == 0) || divisor == 0 {
                    out[x * channels + c] = input[cy * sourceRowBytes + cx * channels + c]
                } else {
                    out[x * channels + c] = UInt8(min(255, (running[x * channels + c] + divisor / 2) / divisor))
                }
            }
        }

        // The oldest row leaves the window.
        let outgoing = y % kernelHeight
        for i in 0..<running.count { running[i] -= ring[outgoing][i] }
    }
}
