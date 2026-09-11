// UIButton (Docs/elements/UIKit/UIButton.md): the system button (a tinted 15 pt title with
// 6 pt above and below, at least 30 wide) and the plain, gray, tinted and filled configurations
// of iOS 15 (a body title in 7 × 12 insets).

/// A control that executes your custom code in response to user interactions.
@MainActor
open class UIButton: UIControl {
    public enum ButtonType: Int, Sendable {
        case custom = 0, system, detailDisclosure, infoLight, infoDark, contactAdd, close
        public static let roundedRect = ButtonType.system
    }

    public let buttonType: ButtonType
    public let titleLabel: UILabel? = UILabel()
    public let imageView: UIImageView? = UIImageView()
    private var titles: [State: String] = [:]
    private var titleColors: [State: UIColor] = [:]
    private var images: [State: UIImage] = [:]
    open var contentEdgeInsets = UIEdgeInsets.zero { didSet { invalidateIntrinsicContentSize() } }
    open var titleEdgeInsets = UIEdgeInsets.zero
    open var imageEdgeInsets = UIEdgeInsets.zero
    open var configuration: Configuration? { didSet { configurationDidChange() } }
    open var isPointerInteractionEnabled = false
    open var role: Role = .normal

    public init(type: ButtonType) {
        buttonType = type
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        // A system button's title is 15 pt (measured; a custom button's is not yet).
        titleLabel?.font = .systemFont(ofSize: type == .system ? 15 : 17)
        titleLabel?.textAlignment = .center
        titleLabel?.isUserInteractionEnabled = false
        titleLabel?.isAccessibilityElement = false
        if let titleLabel { addSubview(titleLabel) }
        if let imageView { imageView.isAccessibilityElement = false; addSubview(imageView) }
    }

    public convenience override init(frame: CGRect) {
        self.init(type: .custom)
        self.frame = frame
    }

    public convenience init(type: ButtonType = .system, primaryAction: UIAction?) {
        self.init(type: type)
        if let primaryAction {
            setTitle(primaryAction.title, for: .normal)
            if let image = primaryAction.image { setImage(image, for: .normal) }
            addAction(primaryAction, for: .primaryActionTriggered)
        }
    }

    public convenience init(configuration: Configuration, primaryAction: UIAction? = nil) {
        self.init(type: .system, primaryAction: primaryAction)
        self.configuration = configuration
        configurationDidChange()
    }

    // MARK: Titles and images

    open func setTitle(_ title: String?, for state: State) {
        titles[state] = title
        if state == .normal || self.state == state { updateContent() }
        invalidateIntrinsicContentSize()
    }

    open func title(for state: State) -> String? { titles[state] ?? titles[.normal] }
    open var currentTitle: String? { title(for: state) }

    open func setTitleColor(_ color: UIColor?, for state: State) {
        titleColors[state] = color
        updateContent()
    }

    open func titleColor(for state: State) -> UIColor? {
        if let color = titleColors[state] { return color }
        if state.contains(.disabled) { return titleColors[.disabled] ?? UIColor.tertiaryLabel }
        if state.contains(.highlighted) {
            let normal = titleColors[.normal] ?? defaultTitleColor
            return titleColors[.highlighted] ?? normal.withAlphaComponent(normal.light.alpha * 0.3)
        }
        return titleColors[.normal] ?? defaultTitleColor
    }

    open var currentTitleColor: UIColor { titleColor(for: state) ?? defaultTitleColor }

    /// System buttons tint their title; custom ones use white, like UIKit.
    private var defaultTitleColor: UIColor {
        if let configuration {
            switch configuration.style {
            case .filled: return .white
            case .gray, .tinted, .plain: return tintColor
            }
        }
        return buttonType == .system ? tintColor : .white
    }

    open func setImage(_ image: UIImage?, for state: State) {
        images[state] = image
        updateContent()
        invalidateIntrinsicContentSize()
    }

    open func image(for state: State) -> UIImage? { images[state] ?? images[.normal] }
    open var currentImage: UIImage? { image(for: state) }

    override open func stateDidChange() {
        super.stateDidChange()
        updateContent()
    }

    override open func tintColorDidChange() {
        super.tintColorDidChange()
        updateContent()
    }

    private func configurationDidChange() {
        guard let configuration else { return }
        if let title = configuration.title { titles[.normal] = title }
        if let image = configuration.image { images[.normal] = image }
        // A configured title is the body style in a label without a line limit.
        titleLabel?.font = configuration.titleFont ?? .preferredFont(forTextStyle: .body)
        titleLabel?.numberOfLines = 0
        contentEdgeInsets = UIEdgeInsets(top: configuration.contentInsets.top, left: configuration.contentInsets.leading,
                                         bottom: configuration.contentInsets.bottom, right: configuration.contentInsets.trailing)
        updateContent()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func updateContent() {
        titleLabel?.text = currentTitle
        titleLabel?.textColor = currentTitleColor
        imageView?.image = currentImage
        if let imageView, currentImage != nil {
            imageView.tintColor = currentTitleColor
        }
        setNeedsDisplay()
        setNeedsLayout()
    }

    // MARK: Layout

    /// The padding a configured button adds around its content (iOS 15's defaults).
    private var insets: UIEdgeInsets {
        if configuration != nil { return contentEdgeInsets }
        return contentEdgeInsets
    }

    private var imageTitleSpacing: CGFloat { configuration?.imagePadding ?? 0 }

    /// The title's size: the label's, and for a configured button its label height plus the
    /// font's leading, on the pixel grid (a body title takes 26.5 in a 40.5 pt button; measured).
    private func measuredTitleSize(within width: CGFloat) -> CGSize {
        guard let titleLabel, let text = titleLabel.text, !text.isEmpty else { return .zero }
        var size = titleLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        if configuration != nil { size.height = (size.height + titleLabel.font.leading).roundedUp(to: UIScreen.main.scale) }
        return size
    }

    /// A system button's padding above and below its title, and its minimum width (measured).
    private static let systemVerticalPadding: CGFloat = 6
    private static let systemMinimumWidth: CGFloat = 30

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let titleSize = measuredTitleSize(within: CGFloat.greatestFiniteMagnitude)
        let imageSize = currentImage?.size ?? .zero
        let spacing = titleSize.width > 0 && imageSize.width > 0 ? imageTitleSpacing : 0
        var width = titleSize.width + imageSize.width + spacing + insets.left + insets.right
        var height = max(titleSize.height, imageSize.height) + insets.top + insets.bottom
        if configuration == nil, buttonType == .system {
            width = max(width, Self.systemMinimumWidth)
            height += 2 * Self.systemVerticalPadding
        }
        return CGSize(width: width, height: height)
    }

    override open var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let content = bounds.inset(by: insets)
        let titleSize = measuredTitleSize(within: content.width)
        let imageSize = currentImage?.size ?? .zero
        let spacing = titleSize.width > 0 && imageSize.width > 0 ? imageTitleSpacing : 0
        let total = titleSize.width + imageSize.width + spacing
        var x: CGFloat
        switch contentHorizontalAlignment {
        case .left, .leading: x = content.minX
        case .right, .trailing: x = content.maxX - total
        default: x = content.minX + (content.width - total) / 2
        }
        imageView?.frame = CGRect(x: x, y: content.minY + (content.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height)
        x += imageSize.width + spacing
        titleLabel?.frame = CGRect(x: x, y: content.minY + (content.height - titleSize.height) / 2, width: titleSize.width, height: titleSize.height)
    }

    // MARK: Painting

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard let configuration else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let tint = tintColor.rgba(for: style)
        let fill: RGBA?
        switch configuration.style {
        case .plain: fill = nil
        case .gray: fill = UIColor.secondarySystemFill.rgba(for: style)
        case .tinted: fill = tint.multiplyingAlpha(by: 0.15)
        case .filled: fill = tint
        }
        guard let fill else { return }
        let dim = isEnabled ? (isHighlighted ? 0.75 : 1) : 0.35
        let radius: CGFloat
        switch configuration.cornerStyle {
        case .capsule: radius = rect.height / 2
        case .small: radius = 6
        case .medium: radius = 8
        case .large: radius = 12
        case .fixed, .dynamic: radius = configuration.background.cornerRadius
        }
        list.append(.fillPath(Path(roundedRect: rect, cornerRadius: radius, style: .continuous), fill.multiplyingAlpha(by: dim)))
    }

    override open var accessibilityLabel: String? {
        get { super.accessibilityLabel ?? currentTitle }
        set { super.accessibilityLabel = newValue }
    }

    // MARK: Nested types

    public enum Role: Int, Sendable { case normal = 0, primary, cancel, destructive }

    /// The iOS 15 configuration: a style, a corner style, content and insets.
    public struct Configuration: Equatable, Sendable {
        public enum Style: Sendable { case plain, gray, tinted, filled }
        public enum CornerStyle: Sendable { case fixed, dynamic, small, medium, large, capsule }
        public enum Size: Sendable { case mini, small, medium, large }
        public enum TitleAlignment: Sendable { case automatic, leading, center, trailing }
        public enum ImagePlacement: Sendable { case leading, trailing, top, bottom }

        public struct Background: Equatable, Sendable {
            public var cornerRadius: CGFloat = 5.95
            public var backgroundColor: UIColor?
            public var strokeColor: UIColor?
            public var strokeWidth: CGFloat = 0
            public init() {}
        }

        public var style: Style
        public var title: String?
        public var subtitle: String?
        public var image: UIImage?
        public var titleFont: UIFont?
        public var baseForegroundColor: UIColor?
        public var baseBackgroundColor: UIColor?
        public var cornerStyle: CornerStyle = .dynamic
        public var buttonSize: Size = .medium
        public var titleAlignment: TitleAlignment = .automatic
        public var imagePlacement: ImagePlacement = .leading
        public var imagePadding: CGFloat = 0
        public var titlePadding: CGFloat = 0
        public var contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
        public var background = Background()
        public var showsActivityIndicator = false

        public init(style: Style) {
            self.style = style
            if style == .plain { contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12) }
        }

        public static func plain() -> Configuration { Configuration(style: .plain) }
        public static func gray() -> Configuration { Configuration(style: .gray) }
        public static func tinted() -> Configuration { Configuration(style: .tinted) }
        public static func filled() -> Configuration { Configuration(style: .filled) }
        public static func borderless() -> Configuration { Configuration(style: .plain) }
        public static func bordered() -> Configuration { Configuration(style: .gray) }
        public static func borderedTinted() -> Configuration { Configuration(style: .tinted) }
        public static func borderedProminent() -> Configuration { Configuration(style: .filled) }
    }
}
