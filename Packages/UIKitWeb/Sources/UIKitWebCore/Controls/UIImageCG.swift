// UIImage and CGImage where CGImage is WebGraphics's (wasm and Linux; Apple platforms keep
// CoreGraphics's), Docs/elements/UIKit/Drawing.md, "CGImage". An image made from a CGImage
// keeps it for `cgImage` and draws it: a whole image file as the file (a data URL, so
// `pngData()` and `jpegData` hand back its bytes), a bitmap as a PNG of its pixels, anything
// else (a recording, a cropped file) as a recording of the CGImage's draw, turned by the
// orientation. Images from data or drawings make their CGImage when asked.

#if !canImport(CoreGraphics) || os(WASI)
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

extension UIImage {
    /// An image of `cgImage` at `scale` (pixels per point), shown turned by `orientation`.
    public convenience init(cgImage: CGImage, scale: CGFloat, orientation: Orientation) {
        let pixels = CGSize(width: cgImage.width, height: cgImage.height)
        let turned = orientation.swapsSides ? CGSize(width: pixels.height, height: pixels.width) : pixels
        let size = CGSize(width: turned.width / scale, height: turned.height / scale)
        if orientation == .up, let data = cgImage._fileData ?? cgImage._pngData, let info = _ImageFileInfo(data) {
            let file = "data:\(info.kind.mimeType);base64," + data.base64EncodedString()
            self.init(name: file, isSystemSymbol: false, scale: scale, size: size, data: data, pixelSize: pixels,
                      orientation: orientation, cgImage: cgImage)
            return
        }
        // Drawn unturned into the image's pixel-sized space, then turned into its points.
        let raw = CGRect(origin: .zero, size: CGSize(width: pixels.width / scale, height: pixels.height / scale))
        let commands: [DisplayCommand] = [.save, .concat(orientation.transform(for: raw.size))] + cgImage._commands(in: raw) + [.restore]
        self.init(name: "", isSystemSymbol: false, scale: scale, size: size,
                  drawing: UIImageDrawing(commands: commands, size: size, scale: scale),
                  orientation: orientation, cgImage: cgImage)
    }

    /// An image of `cgImage` at one pixel per point, upright.
    public convenience init(cgImage: CGImage) { self.init(cgImage: cgImage, scale: 1, orientation: .up) }

    /// The image's CGImage: the one it was made from, its file's, or its recording's. Nil for
    /// a catalog image or a symbol, which only the painters draw.
    public var cgImage: CGImage? {
        if let made = madeFromCGImage as? CGImage { return made }
        if let data, let info = _ImageFileInfo(data) { return CGImage(_content: .file(data, info, frame: 0)) }
        if let drawing { return CGImage(_content: .recording(drawing.commands, size: drawing.size, scale: drawing.scale)) }
        return nil
    }
}

extension UIImage.Orientation {
    /// Whether the image shows a quarter turn from its pixels (width and height swap).
    var swapsSides: Bool { [.left, .right, .leftMirrored, .rightMirrored].contains(self) }

    /// The transform from the unturned pixels' space (`size`, in points) to the shown image's.
    func transform(for size: CGSize) -> CGAffineTransform {
        let w = size.width, h = size.height
        switch self {
        case .up: return .identity
        case .down: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: w, ty: h)
        case .left: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
        case .right: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0)
        case .upMirrored: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: w, ty: 0)
        case .downMirrored: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: h)
        case .leftMirrored: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .rightMirrored: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: h, ty: w)
        }
    }
}
#endif
