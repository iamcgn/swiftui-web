#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
// UIImage and UIImageView (Docs/elements/UIKit/Drawing.md): catalog images (decision 0011),
// symbols, images from PNG or JPEG data (a data URL the painters load) and recorded drawings,
// drawn by content mode (uikit/imageview/modes) with their rendering mode and tint
// (uikit/imageview/tints); animated images step on the scene's clock.

/// An object that manages image data in your app.
public final class UIImage: Hashable, @unchecked Sendable {
    public enum RenderingMode: Int, Sendable { case automatic = 0, alwaysOriginal, alwaysTemplate }

    /// A catalog image by name, or a symbol by system name.
    public let name: String
    public let isSystemSymbol: Bool
    public let renderingMode: RenderingMode
    /// The scale the image was made for, and its point size (from the catalog, else zero).
    public let scale: CGFloat
    public let size: CGSize
    public let tint: UIColor?
    public let symbolConfiguration: SymbolConfiguration?
    /// The recording an image context made (`UIGraphicsImageRenderer`), replayed when drawn.
    public let drawing: UIImageDrawing?
    /// The bytes an image made from data holds (PNG or JPEG), and their pixel size.
    public let data: Data?
    let pixelSize: CGSize
    /// The frames of an animated image (`animatedImage(with:duration:)`) and their total duration.
    public let images: [UIImage]?
    public let duration: TimeInterval

    init(name: String, isSystemSymbol: Bool, renderingMode: RenderingMode = .automatic, scale: CGFloat = 2, size: CGSize, tint: UIColor? = nil,
         symbolConfiguration: SymbolConfiguration? = nil, drawing: UIImageDrawing? = nil, data: Data? = nil, pixelSize: CGSize = .zero,
         images: [UIImage]? = nil, duration: TimeInterval = 0) {
        self.name = name
        self.isSystemSymbol = isSystemSymbol
        self.renderingMode = renderingMode
        self.scale = scale
        self.size = size
        self.tint = tint
        self.symbolConfiguration = symbolConfiguration
        self.drawing = drawing
        self.data = data
        self.pixelSize = pixelSize
        self.images = images
        self.duration = duration
    }

    /// An image from PNG or JPEG bytes at `scale` (1 by default: a 40 × 40 pixel PNG is 40
    /// points wide); nil for bytes of another kind. The painters load it as a data URL.
    public convenience init?(data: Data, scale: CGFloat = 1) {
        guard let (pixels, kind) = Self.imageHeader(data) else { return nil }
        let file = "data:image/\(kind);base64," + data.base64EncodedString()
        self.init(name: file, isSystemSymbol: false, scale: scale, size: CGSize(width: pixels.width / scale, height: pixels.height / scale), data: data, pixelSize: pixels)
    }

    /// The pixel size and kind ("png" or "jpeg") from the file's header.
    static func imageHeader(_ data: Data) -> (CGSize, String)? {
        let bytes = [UInt8](data)
        if bytes.count >= 24, bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            func word(_ i: Int) -> CGFloat { CGFloat(Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])) }
            return (CGSize(width: word(16), height: word(20)), "png")
        }
        if bytes.count >= 4, bytes[0] == 0xFF, bytes[1] == 0xD8 {
            // JPEG: walk the segments to the first frame header (SOFn) for its dimensions.
            var i = 2
            while i + 9 < bytes.count {
                guard bytes[i] == 0xFF else { i += 1; continue }
                let marker = bytes[i + 1]
                if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 || marker == 0xFF { i += 2; continue }
                let length = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
                if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                    let height = CGFloat(Int(bytes[i + 5]) << 8 | Int(bytes[i + 6]))
                    let width = CGFloat(Int(bytes[i + 7]) << 8 | Int(bytes[i + 8]))
                    return (CGSize(width: width, height: height), "jpeg")
                }
                i += 2 + length
            }
            return nil
        }
        return nil
    }

    /// An image that cycles through `images` over `duration` seconds in an image view.
    public static func animatedImage(with images: [UIImage], duration: TimeInterval) -> UIImage? {
        guard let first = images.first else { return nil }
        return UIImage(name: first.name, isSystemSymbol: first.isSystemSymbol, renderingMode: first.renderingMode, scale: first.scale, size: first.size,
                       tint: first.tint, symbolConfiguration: first.symbolConfiguration, drawing: first.drawing, data: first.data, pixelSize: first.pixelSize,
                       images: images, duration: duration)
    }

    /// An image made by an image context.
    convenience init(drawing: UIImageDrawing) {
        self.init(name: "", isSystemSymbol: false, scale: drawing.scale, size: drawing.size, drawing: drawing)
    }

    /// An image from the app's asset catalog; nil when the catalog has no such name.
    @MainActor
    public convenience init?(named name: String) {
        guard let resource = UIKitScene.shared.assetCatalog.image(named: name) else { return nil }
        let size = resource.variants.max { $0.scale < $1.scale }?.pointSize ?? .zero
        self.init(name: name, isSystemSymbol: false, renderingMode: resource.isTemplate ? .alwaysTemplate : .automatic, size: size)
    }

    /// A symbol image (drawn from the substrate's symbol table at the body size).
    @MainActor
    public convenience init?(systemName name: String, withConfiguration configuration: SymbolConfiguration? = nil) {
        guard SystemSymbolGlyphs.glyph(named: name) != nil else { return nil }
        let pointSize = configuration?.pointSize ?? 17
        let side = (pointSize * 1.25).rounded()
        self.init(name: name, isSystemSymbol: true, renderingMode: .alwaysTemplate, size: CGSize(width: side, height: side), symbolConfiguration: configuration)
    }

    public func withRenderingMode(_ mode: RenderingMode) -> UIImage {
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: mode, scale: scale, size: size, tint: tint, symbolConfiguration: symbolConfiguration, drawing: drawing, data: data, pixelSize: pixelSize, images: images, duration: duration)
    }

    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode = .alwaysOriginal) -> UIImage {
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: size, tint: color, symbolConfiguration: symbolConfiguration, drawing: drawing, data: data, pixelSize: pixelSize, images: images, duration: duration)
    }

    /// The image as PNG data: the bytes an image made from PNG data holds, else a recorded
    /// drawing rasterised by the host (nil without a host rasteriser, and for catalog images
    /// and symbols, whose files the host already has).
    @MainActor
    public func pngData() -> Data? {
        if let data, name.hasPrefix("data:image/png") { return data }
        guard let drawing, let rasterizer = UIKitScene.shared.imageRasterizer else { return nil }
        var list = DisplayList()
        for command in drawing.commands { list.append(command) }
        return rasterizer(list, drawing.size, drawing.scale)
    }

    /// JPEG is not made in this substrate: an image made from JPEG data returns its bytes,
    /// another its PNG data, the quality ignored.
    @MainActor
    public func jpegData(compressionQuality: CGFloat) -> Data? {
        if let data, name.hasPrefix("data:image/jpeg") { return data }
        return pngData()
    }

    public func withConfiguration(_ configuration: SymbolConfiguration) -> UIImage {
        let pointSize = configuration.pointSize ?? 17
        let side = isSystemSymbol ? (pointSize * 1.25).rounded() : size.width
        return UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: CGSize(width: side, height: side), tint: tint, symbolConfiguration: configuration)
    }

    public static func == (lhs: UIImage, rhs: UIImage) -> Bool {
        lhs.name == rhs.name && lhs.isSystemSymbol == rhs.isSystemSymbol && lhs.renderingMode == rhs.renderingMode && lhs.size == rhs.size && lhs.tint == rhs.tint && lhs.drawing === rhs.drawing && lhs.images?.count == rhs.images?.count
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// How a symbol image is sized and weighted.
    public struct SymbolConfiguration: Equatable, Sendable {
        public var pointSize: CGFloat?
        public var weight: UIFont.Weight?
        public var scale: Scale?
        public enum Scale: Int, Sendable { case `default` = -1, unspecified = 0, small = 1, medium = 2, large = 3 }
        public init(pointSize: CGFloat, weight: UIFont.Weight = .regular, scale: Scale = .default) {
            self.pointSize = pointSize; self.weight = weight; self.scale = scale
        }
        public init(scale: Scale) { self.scale = scale }
        public init(textStyle: UIFont.TextStyle) { pointSize = textStyle.metrics.size }
        public init(weight: UIFont.Weight) { self.weight = weight }
    }
}

/// An object that displays a single image or a sequence of animated images in your interface.
@MainActor
open class UIImageView: UIView, ClockAnimating {
    open var image: UIImage? { didSet { if image != oldValue { imageDidChange() } } }

    private func imageDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
        // An animated image plays on its own as UIKit plays it.
        if let frames = image?.images, frames.count > 1, animationImages == nil { startAnimating() } else if animationImages == nil, isAnimating { stopAnimating() }
    }
    open var highlightedImage: UIImage?
    open var isHighlighted = false { didSet { setNeedsDisplay() } }
    open var preferredSymbolConfiguration: UIImage.SymbolConfiguration?

    // MARK: Animation (`animationImages`, or an `animatedImage`): the frames cycle over
    // `animationDuration` (the image's duration, else a 30th of a second per frame) on the
    // scene's clock, `animationRepeatCount` times (0 forever).

    open var animationImages: [UIImage]? { didSet { if animationImages == nil, isAnimating { stopAnimating() }; setNeedsDisplay() } }
    open var highlightedAnimationImages: [UIImage]?
    open var animationDuration: TimeInterval = 0
    open var animationRepeatCount = 0
    public private(set) var isAnimating = false
    private var clock: Double = 0

    /// The frames playing: `animationImages` first, else the image's own.
    private var frames: [UIImage]? {
        if let animationImages, !animationImages.isEmpty { return isHighlighted ? (highlightedAnimationImages ?? animationImages) : animationImages }
        if let frames = image?.images, frames.count > 1 { return frames }
        return nil
    }
    private var frameDuration: TimeInterval {
        guard let frames else { return 0 }
        if animationDuration > 0 { return animationDuration }
        if let image, image.images != nil, image.duration > 0 { return image.duration }
        return Double(frames.count) / 30
    }
    /// The frame showing: the clock's position in the cycle while animating; at rest the
    /// `image` (an animated image's first frame) as UIKit shows it.
    var currentFrame: UIImage? {
        guard let frames, isAnimating, frameDuration > 0 else { return animationImages?.isEmpty == false ? image : (image?.images?.first ?? image) }
        let cycles = clock / frameDuration
        let fraction = cycles - cycles.rounded(.down)
        return frames[min(frames.count - 1, Int(fraction * Double(frames.count)))]
    }

    open func startAnimating() {
        guard frames != nil, !isAnimating else { return }
        isAnimating = true
        clock = 0
        UIKitScene.shared.spinners.append(WeakActivityIndicator(view: self))
        UIKitScene.shared.setNeedsFrame()
        setNeedsDisplay()
    }

    open func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        UIKitScene.shared.spinners.removeAll { $0.view === self || $0.view == nil }
        setNeedsDisplay()
    }

    func advance(elapsed: Double) {
        let before = currentFrame
        clock += elapsed
        // The repeats done, the view shows its `image` again.
        if animationRepeatCount > 0, frameDuration > 0, clock / frameDuration >= Double(animationRepeatCount) { stopAnimating() }
        if currentFrame != before { setNeedsDisplay() }
    }

    public init(image: UIImage?) {
        super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
        self.image = image
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
        if image != nil { imageDidChange() }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    public convenience init(image: UIImage?, highlightedImage: UIImage?) {
        self.init(image: image)
        self.highlightedImage = highlightedImage
    }

    override open var intrinsicContentSize: CGSize { image?.size ?? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
    override open func sizeThatFits(_ size: CGSize) -> CGSize { image?.size ?? .zero }

    override open var accessibilityTraits: UIAccessibilityTraits {
        get { super.accessibilityTraits.union(.image) }
        set { super.accessibilityTraits = newValue }
    }

    /// The rectangle the image draws in for the content mode.
    func imageRect(for size: CGSize) -> CGRect {
        let b = bounds
        switch contentMode {
        case .scaleToFill, .redraw: return b
        case .scaleAspectFit, .scaleAspectFill:
            guard size.width > 0, size.height > 0 else { return b }
            let scale = contentMode == .scaleAspectFit ? min(b.width / size.width, b.height / size.height) : max(b.width / size.width, b.height / size.height)
            let w = size.width * scale, h = size.height * scale
            return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
        case .center: return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .top: return CGRect(x: b.midX - size.width / 2, y: b.minY, width: size.width, height: size.height)
        case .bottom: return CGRect(x: b.midX - size.width / 2, y: b.maxY - size.height, width: size.width, height: size.height)
        case .left: return CGRect(x: b.minX, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .right: return CGRect(x: b.maxX - size.width, y: b.midY - size.height / 2, width: size.width, height: size.height)
        case .topLeft: return CGRect(origin: b.origin, size: size)
        case .topRight: return CGRect(x: b.maxX - size.width, y: b.minY, width: size.width, height: size.height)
        case .bottomLeft: return CGRect(x: b.minX, y: b.maxY - size.height, width: size.width, height: size.height)
        case .bottomRight: return CGRect(x: b.maxX - size.width, y: b.maxY - size.height, width: size.width, height: size.height)
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let image = isAnimating ? currentFrame : (isHighlighted ? (highlightedImage ?? self.image?.images?.first ?? self.image) : (self.image?.images?.first ?? self.image)) else { return }
        let rect = context.absoluteRect(imageRect(for: image.size))
        let tint: RGBA? = image.renderingMode == .alwaysTemplate || (image.renderingMode == .automatic && image.isSystemSymbol)
            ? (image.tint ?? tintColor).rgba(for: style) : image.tint?.rgba(for: style)
        if let drawing = image.drawing {
            for command in drawing.commands(in: rect) { list.append(command) }
            return
        }
        if image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: rect, color: tint ?? UIColor.label.rgba(for: style), weight: image.symbolConfiguration?.weight?.css ?? 400, into: &list)
            return
        }
        if image.data != nil {
            var draw = ImageDraw(file: image.name, scale: image.scale, pixelSize: image.pixelSize, rect: rect)
            draw.tint = tint
            list.append(.drawImage(draw))
            return
        }
        let catalog = UIKitScene.shared.assetCatalog
        guard let resource = catalog.image(named: image.name),
              let variant = resource.variants.first(where: { $0.scale == context.scale }) ?? resource.variants.max(by: { $0.scale < $1.scale }) else { return }
        var draw = ImageDraw(file: variant.file, scale: variant.scale, pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: rect)
        draw.tint = tint
        list.append(.drawImage(draw))
    }
}
