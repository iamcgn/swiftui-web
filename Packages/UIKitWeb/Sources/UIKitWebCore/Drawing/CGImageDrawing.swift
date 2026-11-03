// A recording context and CGImages where CGImage is WebGraphics's (wasm and Linux; Apple
// platforms keep CoreGraphics's), Docs/elements/UIKit/Drawing.md, "CGImage": an image drawn
// into a context the way CoreGraphics draws it (its first row at the rectangle's maximum y,
// which code that flips the context first, as image code does, sees upright), and what an
// image context has drawn so far as a CGImage. A context reports the pixel size of the image
// it draws; it holds no pixels, so `data` is nil. A layer's `contents` CGImage is painted here
// too, placed by its gravity.

#if !canImport(CoreGraphics) || os(WASI)
extension UIGraphicsRecordingContext {
    /// Draws `image` scaled into `rect`, flipped as CoreGraphics draws it.
    public func draw(_ image: CGImage, in rect: CGRect) {
        let flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: rect.minY + rect.maxY)
        let local: [DisplayCommand] = [.save, .concat(flip)] + image._commands(in: rect) + [.restore]
        let opacity = Double(currentAlpha)
        record(opacity < 1 ? [.beginGroup(opacity: opacity)] + local + [.endGroup] : local, bounds: rect)
    }

    /// Draws `image` into `rect`; tiling is drawn as one image scaled into the rectangle.
    public func draw(_ image: CGImage, in rect: CGRect, byTiling: Bool) { draw(image, in: rect) }

    /// What the image context has drawn so far as an image; nil for a view's context.
    public func makeImage() -> CGImage? {
        guard let canvasSize, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        return CGImage(_content: .recording(closedCommands, size: canvasSize, scale: scale))
    }

    /// The image's size in pixels (0 for a view's context).
    public var width: Int { Int(((canvasSize?.width ?? 0) * scale).rounded()) }
    public var height: Int { Int(((canvasSize?.height ?? 0) * scale).rounded()) }
    public var bitsPerComponent: Int { 8 }
    public var bitsPerPixel: Int { 32 }
    public var bytesPerRow: Int { width * 4 }
    /// No pixels are held: the painters make them.
    public var data: UnsafeMutableRawPointer? { nil }
    public var colorSpace: CGColorSpace? { CGColorSpaceCreateDeviceRGB() }
    public var bitmapInfo: CGBitmapInfo { CGBitmapInfo(alphaInfo: .premultipliedLast) }
    public var alphaInfo: CGImageAlphaInfo { .premultipliedLast }

    /// Resampling quality: images are drawn smoothly whatever is asked.
    public var interpolationQuality: CGInterpolationQuality {
        get { .default }
        set {}
    }
}

extension CALayer {
    /// Paints `contents` when it is a CGImage, in the layer's rectangle `rect` (absolute): its
    /// `contentsRect` part, placed by `contentsGravity` at `contentsScale` pixels per point.
    /// Whether contents were painted (they then stand in for the view's own content).
    func paintContents(into list: inout DisplayList, in rect: CGRect) -> Bool {
        guard let contents else { return false }
        guard let image = contents as? CGImage else { return false }
        var shown = image
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        if contentsRect != unit {
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let part = contentsRect.intersection(unit)
            guard !part.isNull, let cropped = image.cropping(to: CGRect(x: part.minX * w, y: part.minY * h, width: part.width * w, height: part.height * h)) else { return true }
            shown = cropped
        }
        let scale = contentsScale > 0 ? contentsScale : 1
        let natural = CGSize(width: CGFloat(shown.width) / scale, height: CGFloat(shown.height) / scale)
        for command in shown._commands(in: Self.contentsFrame(contentsGravity, natural: natural, in: rect)) { list.append(command) }
        return true
    }

    /// Where an image of `natural` size sits in `r` for `gravity`. Core Animation's y axis
    /// points up, so on iOS the "top" gravities place the image at the layer's bottom edge and
    /// the "bottom" ones at its top, which is kept here.
    static func contentsFrame(_ gravity: CALayerContentsGravity, natural s: CGSize, in r: CGRect) -> CGRect {
        switch gravity {
        case .resize:
            return r
        case .resizeAspect, .resizeAspectFill:
            guard s.width > 0, s.height > 0 else { return r }
            let k = gravity == .resizeAspect ? min(r.width / s.width, r.height / s.height) : max(r.width / s.width, r.height / s.height)
            return CGRect(x: r.midX - s.width * k / 2, y: r.midY - s.height * k / 2, width: s.width * k, height: s.height * k)
        default:
            let name = gravity.rawValue
            var x = r.midX - s.width / 2, y = r.midY - s.height / 2
            if name == "left" || name.hasSuffix("Left") { x = r.minX }
            if name == "right" || name.hasSuffix("Right") { x = r.maxX - s.width }
            if name.hasPrefix("top") { y = r.maxY - s.height }
            if name.hasPrefix("bottom") { y = r.minY }
            return CGRect(x: x, y: y, width: s.width, height: s.height)
        }
    }
}
#endif
