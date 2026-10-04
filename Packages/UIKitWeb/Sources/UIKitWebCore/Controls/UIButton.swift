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
    /// The menu a long press opens, or a tap with `showsMenuAsPrimaryAction`; with
    /// `changesSelectionAsPrimaryAction` the chosen action becomes the button's title and state.
    open var menu: UIMenu?
    open var changesSelectionAsPrimaryAction = false { didSet { if changesSelectionAsPrimaryAction { showSelectedAction() } } }
    override var longPressMenu: UIMenu? { showsMenuAsPrimaryAction ? nil : menu }

    /// The action with the `on` state (a selection menu), shown as the button's title.
    private func showSelectedAction() {
        guard changesSelectionAsPrimaryAction, let selected = menu?.flattenedActions.first(where: { $0.state == .on }) ?? menu?.flattenedActions.first else { return }
        setTitle(selected.title, for: .normal)
    }

    override open func sendActions(for controlEvents: Event) {
        if controlEvents.contains(.primaryActionTriggered), showsMenuAsPrimaryAction, let menu {
            MenuPresenter.present(menu, from: self) { [weak self] action in
                guard let self, self.changesSelectionAsPrimaryAction else { return }
                for other in menu.flattenedActions { other.state = other === action ? .on : .off }
                self.showSelectedAction()
            }
            sendActionsIgnoringMenu(for: controlEvents.subtracting(.primaryActionTriggered))
            return
        }
        sendActionsIgnoringMenu(for: controlEvents)
    }

    private func sendActionsIgnoringMenu(for controlEvents: Event) { super.sendActions(for: controlEvents) }

    public init(type: ButtonType) {
        buttonType = type
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        // A system button's title is 15 pt, a custom button's 18 (uikit/button/looks).
        titleLabel?.font = .systemFont(ofSize: type == .system ? 15 : 18)
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
            // A configured button dims its fill, not its title (a pressed filled button stays white).
            if configuration != nil, titleColors[.highlighted] == nil { return normal }
            return titleColors[.highlighted] ?? normal.withAlphaComponent(normal.light.alpha * 0.3)
        }
        return titleColors[.normal] ?? defaultTitleColor
    }

    open var currentTitleColor: UIColor { titleColor(for: state) ?? defaultTitleColor }

    /// System buttons tint their title; custom ones use white, like UIKit.
    private var defaultTitleColor: UIColor {
        if let configuration {
            if let base = configuration.baseForegroundColor { return base }
            switch configuration.style {
            case .filled: return .white
            case .gray: return .label   // iOS 26: black on the gray fill (uikit/button/looks)
            case .tinted, .plain: return tintColor
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

    /// Called on every state change (and `setNeedsUpdateConfiguration`) to adjust the configuration.
    open var configurationUpdateHandler: ((UIButton) -> Void)? { didSet { setNeedsUpdateConfiguration() } }
    open var automaticallyUpdatesConfiguration = true

    override open func stateDidChange() {
        super.stateDidChange()
        if automaticallyUpdatesConfiguration { setNeedsUpdateConfiguration() }
        updateContent()
    }

    /// Runs `updateConfiguration` (and the handler) now (UIKit defers it to the next layout).
    open func setNeedsUpdateConfiguration() {
        guard configuration != nil else { return }
        updateConfiguration()
    }

    /// Adjusts the configuration for the state: the handler's job here; subclasses override.
    open func updateConfiguration() {
        configurationUpdateHandler?(self)
    }

    override open func tintColorDidChange() {
        super.tintColorDidChange()
        updateContent()
    }

    /// The subtitle under a configured title (footnote, uikit/button/looks).
    public let subtitleLabel = UILabel()

    private func configurationDidChange() {
        guard let configuration else { return }
        if let title = configuration.title { titles[.normal] = title }
        if let image = configuration.image { images[.normal] = image }
        // A configured title is the body style in a label without a line limit; the mini and
        // small sizes use the subheadline (uikit/button/looks); the subtitle the footnote.
        let sizeFont: UIFont
        switch configuration.buttonSize {
        case .mini, .small: sizeFont = .preferredFont(forTextStyle: .subheadline)
        case .medium, .large: sizeFont = .preferredFont(forTextStyle: .body)
        }
        titleLabel?.font = configuration.titleFont ?? sizeFont
        titleLabel?.numberOfLines = 0
        subtitleLabel.font = configuration.subtitleFont ?? .preferredFont(forTextStyle: .footnote)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.text = configuration.subtitle
        subtitleLabel.isUserInteractionEnabled = false
        subtitleLabel.isAccessibilityElement = false
        if subtitleLabel.superview == nil { addSubview(subtitleLabel) }
        contentEdgeInsets = UIEdgeInsets(top: configuration.contentInsets.top, left: configuration.contentInsets.leading,
                                         bottom: configuration.contentInsets.bottom, right: configuration.contentInsets.trailing)
        updateContent()
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    private func updateContent() {
        titleLabel?.text = currentTitle
        titleLabel?.textColor = currentTitleColor
        subtitleLabel.textColor = currentTitleColor
        imageView?.image = currentImage
        if let imageView, currentImage != nil {
            imageView.tintColor = currentTitleColor
        }
        setNeedsDisplay()
        setNeedsLayout()
    }

    // MARK: Layout

    /// The padding a configured button adds around its content (uikit/button/looks: 7 × 12 for
    /// the medium size, 6 × 10 for mini and small, 15 × 20 for large; `contentInsets` set by the
    /// app win).
    private var insets: UIEdgeInsets {
        guard let configuration else { return contentEdgeInsets }
        if configuration.contentInsets != Configuration.defaultInsets { return contentEdgeInsets }
        switch configuration.buttonSize {
        case .mini, .small: return UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        case .medium: return UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        case .large: return UIEdgeInsets(top: 15, left: 20, bottom: 15, right: 20)
        }
    }

    /// The gap between the image and the title: `imagePadding` for a configured button, 3 for a
    /// system button (uikit/button/looks: the heart and "Heart").
    private var imageTitleSpacing: CGFloat { configuration?.imagePadding ?? (buttonType == .system ? 3 : 0) }

    /// The title's size: the label's, and for a configured button its label height plus the
    /// font's leading, on the pixel grid (a body title takes 26.5 in a 40.5 pt button; measured).
    private func measuredTitleSize(within width: CGFloat) -> CGSize {
        guard let titleLabel, let text = titleLabel.text, !text.isEmpty else { return .zero }
        var size = titleLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        // The body title of the medium and large sizes takes its leading too (26.5); the
        // subheadline of the mini and small sizes is its 21 pt line (uikit/button/looks).
        if let configuration, configuration.buttonSize == .medium || configuration.buttonSize == .large {
            size.height = (size.height + titleLabel.font.leading).roundedUp(to: UIScreen.main.scale)
        }
        return size
    }

    /// The subtitle's size (a footnote line of 19 rounds up to 20 with its leading) and the
    /// 2 pt gap above it (a filled "Title"/"Subtitle" button is 62.5 tall).
    private func measuredSubtitleSize(within width: CGFloat) -> CGSize {
        guard configuration != nil, let text = subtitleLabel.text, !text.isEmpty else { return .zero }
        var size = subtitleLabel.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        size.height += 1
        return size
    }
    private static let subtitleGap: CGFloat = 2

    /// The room an image takes: a system symbol in a configured button sits in a 28 × 20 slot
    /// (its 23.5 × 22 glyph centred, overflowing the slot's height) and in a system button in a
    /// 22 × 23.5 slot (the glyph 20.5 × 19); other images take their size.
    private var imageSlot: CGSize {
        guard let image = currentImage else { return .zero }
        guard image.isSystemSymbol else { return image.size }
        return configuration != nil ? CGSize(width: 28, height: 20) : CGSize(width: 22, height: 23.5)
    }

    private var symbolGlyphSize: CGSize { configuration != nil ? CGSize(width: 23.5, height: 22) : CGSize(width: 20.5, height: 19) }

    /// Whether the image sits above or below the title.
    private var imageIsVertical: Bool {
        guard let placement = configuration?.imagePlacement else { return false }
        return placement == .top || placement == .bottom
    }

    /// A system button's padding above and below its title, and its minimum width (measured);
    /// a custom button is at least 34 tall.
    private static let systemVerticalPadding: CGFloat = 6
    private static let systemMinimumWidth: CGFloat = 30
    private static let customMinimumHeight: CGFloat = 34
    private static let systemImageLeading: CGFloat = 2

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        let titleSize = measuredTitleSize(within: CGFloat.greatestFiniteMagnitude)
        let subtitleSize = measuredSubtitleSize(within: CGFloat.greatestFiniteMagnitude)
        let textWidth = max(titleSize.width, subtitleSize.width)
        let textHeight = titleSize.height + (subtitleSize.height > 0 ? Self.subtitleGap + subtitleSize.height : 0)
        let slot = imageSlot
        let spacing = textWidth > 0 && slot.width > 0 ? imageTitleSpacing : 0
        var width: CGFloat
        var height: CGFloat
        if imageIsVertical {
            width = max(textWidth, slot.width) + insets.left + insets.right
            height = textHeight + spacing + slot.height + insets.top + insets.bottom
        } else {
            width = textWidth + slot.width + spacing + insets.left + insets.right
            height = max(textHeight, slot.height) + insets.top + insets.bottom
        }
        if configuration == nil {
            if buttonType == .system {
                width = max(width, Self.systemMinimumWidth)
                // A system button with an image is its slot's height (23.5) with 2 before the
                // image; a title alone has 6 above and below.
                if slot.height == 0 { height += 2 * Self.systemVerticalPadding } else { width += Self.systemImageLeading }
            } else if buttonType == .custom {
                height = max(height, Self.customMinimumHeight)
            }
        }
        return CGSize(width: width, height: height)
    }

    override open var intrinsicContentSize: CGSize { sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let content = bounds.inset(by: insets)
        let titleSize = measuredTitleSize(within: content.width)
        let subtitleSize = measuredSubtitleSize(within: content.width)
        let textWidth = max(titleSize.width, subtitleSize.width)
        let textHeight = titleSize.height + (subtitleSize.height > 0 ? Self.subtitleGap + subtitleSize.height : 0)
        let slot = imageSlot
        let spacing = textWidth > 0 && slot.width > 0 ? imageTitleSpacing : 0
        let placement = configuration?.imagePlacement ?? .leading
        var imageFrame = CGRect.zero
        var textOrigin = CGPoint.zero
        if imageIsVertical {
            let total = textHeight + spacing + slot.height
            let top = content.minY + (content.height - total) / 2
            let imageX = content.minX + (content.width - slot.width) / 2
            let textX = content.minX + (content.width - textWidth) / 2
            if placement == .top {
                imageFrame = CGRect(x: imageX, y: top, width: slot.width, height: slot.height)
                textOrigin = CGPoint(x: textX, y: top + slot.height + spacing)
            } else {
                textOrigin = CGPoint(x: textX, y: top)
                imageFrame = CGRect(x: imageX, y: top + textHeight + spacing, width: slot.width, height: slot.height)
            }
        } else {
            let leading: CGFloat = configuration == nil && buttonType == .system && slot.width > 0 ? Self.systemImageLeading : 0
            let total = textWidth + slot.width + spacing + leading
            var x: CGFloat
            switch contentHorizontalAlignment {
            case .left, .leading: x = content.minX
            case .right, .trailing: x = content.maxX - total
            default: x = content.minX + (content.width - total) / 2
            }
            x += leading
            let imageY = content.minY + (content.height - slot.height) / 2
            let textY = content.minY + (content.height - textHeight) / 2
            if placement == .trailing {
                textOrigin = CGPoint(x: x, y: textY)
                imageFrame = CGRect(x: x + textWidth + spacing, y: imageY, width: slot.width, height: slot.height)
            } else {
                imageFrame = CGRect(x: x, y: imageY, width: slot.width, height: slot.height)
                textOrigin = CGPoint(x: x + slot.width + spacing, y: textY)
            }
        }
        // A symbol's glyph is centred in its slot (overflowing a configured slot's height).
        if let image = currentImage, image.isSystemSymbol {
            let glyph = symbolGlyphSize
            imageView?.frame = CGRect(x: imageFrame.midX - glyph.width / 2, y: imageFrame.midY - glyph.height / 2, width: glyph.width, height: glyph.height)
        } else {
            imageView?.frame = imageFrame
        }
        // The automatic alignment is leading when there is a subtitle (the two lines share a left
        // edge, uikit/button/looks), centred otherwise.
        let alignment = configuration?.titleAlignment ?? .automatic
        let leadingAligned = alignment == .leading || (alignment == .automatic && subtitleSize.height > 0)
        let trailingAligned = alignment == .trailing
        func textX(_ width: CGFloat) -> CGFloat { leadingAligned ? textOrigin.x : trailingAligned ? textOrigin.x + textWidth - width : textOrigin.x + (textWidth - width) / 2 }
        titleLabel?.frame = CGRect(x: textX(titleSize.width), y: textOrigin.y, width: titleSize.width, height: titleSize.height)
        subtitleLabel.isHidden = subtitleSize.height == 0
        subtitleLabel.frame = CGRect(x: textX(subtitleSize.width), y: textOrigin.y + titleSize.height + Self.subtitleGap, width: subtitleSize.width, height: subtitleSize.height)
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
        guard var fill else { return }
        // Pressed, a filled button's fill is at 75 % ((64, 166, 255) for the blue); disabled, the
        // gray and filled fills become the tertiary fill ((238, 238, 239)) under tertiary text.
        var dim = isHighlighted ? 0.75 : 1
        if !isEnabled { fill = UIColor.tertiarySystemFill.rgba(for: style); dim = 1 }
        let radius: CGFloat
        switch configuration.cornerStyle {
        case .capsule: radius = rect.height / 2
        // iOS 26's dynamic corners (uikit/button/looks): the large size is a capsule, the others
        // round to at most 20 (a 40.5 pt medium button is nearly one; taller content keeps 20).
        case .dynamic: radius = configuration.buttonSize == .large ? rect.height / 2 : min(rect.height / 2, 20)
        case .small: radius = 6
        case .medium: radius = 8
        case .large: radius = 12
        case .fixed: radius = configuration.background.cornerRadius
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
        public var contentInsets = Configuration.defaultInsets
        public var background = Background()
        public var showsActivityIndicator = false
        public var subtitleFont: UIFont?
        /// The size-dependent defaults apply while the insets are these.
        static let defaultInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)

        public init(style: Style) {
            self.style = style
        }

        /// The configuration for a button's state (the handler adjusts it; nothing changes here).
        public func updated(for button: UIButton) -> Configuration { self }

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
