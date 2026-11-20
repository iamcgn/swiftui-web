// What Apple's UIKit brings with Core Image (Docs/elements/CoreImage.md): UIKit's headers import
// CoreImage, so a file with only `import UIKit` names CIImage and CIFilter (Nuke's processors), and
// UIKit declares the bridges between them: UIColor and CIColor, UIImage and CIImage.
// WebCoreImage is empty where CoreGraphics is Apple's, and so is this file.

#if !canImport(CoreGraphics) || os(WASI)
import UIKitWebCore
import WebFoundation
import WebCoreImage

extension CIColor {
    /// The UIKit colour's components.
    public convenience init(color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}

extension UIColor {
    public convenience init(ciColor: CIColor) {
        self.init(red: ciColor.red, green: ciColor.green, blue: ciColor.blue, alpha: ciColor.alpha)
    }
}

extension CIImage {
    /// The image of a UIImage's CGImage; nil for one with none (a symbol or a catalog image).
    public convenience init?(image: UIImage) {
        guard let cgImage = image.cgImage else { return nil }
        self.init(cgImage: cgImage)
    }

    public convenience init?(image: UIImage, options: [CIImageOption: Any]?) { self.init(image: image) }
}

extension UIImage {
    /// An image of a Core Image recipe, rendered over its extent; empty for an endless one.
    /// It keeps the recipe, which `ciImage` returns.
    public convenience init(ciImage: CIImage, scale: CGFloat, orientation: UIImage.Orientation) {
        let made = CIContext().createCGImage(ciImage, from: ciImage.extent)
            ?? CIContext().createCGImage(CIImage.clear, from: CGRect(x: 0, y: 0, width: 1, height: 1))!
        self.init(cgImage: made, scale: scale, orientation: orientation)
        _madeFromCIImage = ciImage
    }

    /// The Core Image recipe the image was made from; nil for an image made any other way, as on
    /// Apple's platforms (an image from a CGImage or from data has a `cgImage` instead).
    public var ciImage: CIImage? { _madeFromCIImage as? CIImage }

    public convenience init(ciImage: CIImage) { self.init(ciImage: ciImage, scale: 1, orientation: .up) }
}
#endif
