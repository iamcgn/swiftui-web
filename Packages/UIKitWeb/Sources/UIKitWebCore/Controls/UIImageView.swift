// UIImage and UIImageView: catalog images (decision 0011) and symbols, drawn by content mode.

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

    init(name: String, isSystemSymbol: Bool, renderingMode: RenderingMode = .automatic, scale: CGFloat = 2, size: CGSize, tint: UIColor? = nil, symbolConfiguration: SymbolConfiguration? = nil, drawing: UIImageDrawing? = nil) {
        self.name = name
        self.isSystemSymbol = isSystemSymbol
        self.renderingMode = renderingMode
        self.scale = scale
        self.size = size
        self.tint = tint
        self.symbolConfiguration = symbolConfiguration
        self.drawing = drawing
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
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: mode, scale: scale, size: size, tint: tint, symbolConfiguration: symbolConfiguration, drawing: drawing)
    }

    public func withTintColor(_ color: UIColor, renderingMode: RenderingMode = .alwaysOriginal) -> UIImage {
        UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: size, tint: color, symbolConfiguration: symbolConfiguration, drawing: drawing)
    }

    public func withConfiguration(_ configuration: SymbolConfiguration) -> UIImage {
        let pointSize = configuration.pointSize ?? 17
        let side = isSystemSymbol ? (pointSize * 1.25).rounded() : size.width
        return UIImage(name: name, isSystemSymbol: isSystemSymbol, renderingMode: renderingMode, scale: scale, size: CGSize(width: side, height: side), tint: tint, symbolConfiguration: configuration)
    }

    public static func == (lhs: UIImage, rhs: UIImage) -> Bool {
        lhs.name == rhs.name && lhs.isSystemSymbol == rhs.isSystemSymbol && lhs.renderingMode == rhs.renderingMode && lhs.size == rhs.size && lhs.tint == rhs.tint && lhs.drawing === rhs.drawing
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
open class UIImageView: UIView {
    open var image: UIImage? { didSet { if image != oldValue { invalidateIntrinsicContentSize(); setNeedsDisplay() } } }
    open var highlightedImage: UIImage?
    open var isHighlighted = false
    open var preferredSymbolConfiguration: UIImage.SymbolConfiguration?

    public init(image: UIImage?) {
        super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
        self.image = image
        isUserInteractionEnabled = false
        contentMode = .scaleToFill
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
        guard let image = isHighlighted ? (highlightedImage ?? self.image) : self.image else { return }
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
        let catalog = UIKitScene.shared.assetCatalog
        guard let resource = catalog.image(named: image.name),
              let variant = resource.variants.first(where: { $0.scale == context.scale }) ?? resource.variants.max(by: { $0.scale < $1.scale }) else { return }
        var draw = ImageDraw(file: variant.file, scale: variant.scale, pixelSize: CGSize(width: variant.pixelWidth, height: variant.pixelHeight), rect: rect)
        draw.tint = tint
        list.append(.drawImage(draw))
    }
}
