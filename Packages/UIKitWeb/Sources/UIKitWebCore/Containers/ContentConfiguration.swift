// Content configurations (Docs/elements/UIKit/TableView.md): a cell's `contentConfiguration`
// makes a content view that fills the cell's content view and sizes the row; the list content
// configuration draws a text, a secondary text and an image like the cell styles, and
// SwiftUIWebUIKit's `UIHostingConfiguration` hosts SwiftUI in a cell.

/// The state a configuration is updated for.
public protocol UIConfigurationState {}

/// A view's configuration state.
public struct UIViewConfigurationState: UIConfigurationState, Sendable {
    public var traitCollection: UITraitCollection
    public var isSelected = false
    public var isHighlighted = false
    public var isDisabled = false
    public var isFocused = false
    public init(traitCollection: UITraitCollection) { self.traitCollection = traitCollection }
}

/// A cell's configuration state.
public struct UICellConfigurationState: UIConfigurationState, Sendable {
    public var traitCollection: UITraitCollection
    public var isSelected = false
    public var isHighlighted = false
    public var isDisabled = false
    public var isFocused = false
    public var isEditing = false
    public var isExpanded = false
    public init(traitCollection: UITraitCollection) { self.traitCollection = traitCollection }
}

/// The requirements for an object that provides the configuration for a content view.
@MainActor
public protocol UIContentConfiguration {
    func makeContentView() -> UIView & UIContentView
    func updated(for state: any UIConfigurationState) -> Self
}

extension UIContentConfiguration {
    public func updated(for state: any UIConfigurationState) -> Self { self }
}

/// The requirements for a content view that you create using a configuration.
@MainActor
public protocol UIContentView: AnyObject {
    var configuration: any UIContentConfiguration { get set }
    func supports(_ configuration: any UIContentConfiguration) -> Bool
}

extension UIContentView {
    public func supports(_ configuration: any UIContentConfiguration) -> Bool { true }
}

/// A cell's background (accepted: the colour applies; the rest is stored).
public struct UIBackgroundConfiguration: Sendable {
    public var backgroundColor: UIColor?
    public var cornerRadius: CGFloat = 0
    public var backgroundInsets = UIEdgeInsets.zero
    public var strokeColor: UIColor?
    public var strokeWidth: CGFloat = 0
    public init() {}
    public static func clear() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listPlainCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listGroupedCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
    public static func listSidebarCell() -> UIBackgroundConfiguration { UIBackgroundConfiguration() }
}

/// A content configuration for a list-based content view: a text, a secondary text and an
/// image laid out like the default, subtitle and value cell styles (approximate: no golden).
public struct UIListContentConfiguration: UIContentConfiguration, Sendable {
    public struct TextProperties: Sendable {
        public var font: UIFont = .systemFont(ofSize: 17)
        public var color: UIColor = .label
        public var numberOfLines = 0
        public var alignment: NSTextAlignment = .natural
    }
    public enum Layout: Sendable { case cell, subtitle, value }

    public var text: String?
    public var secondaryText: String?
    public var image: UIImage?
    public var textProperties = TextProperties()
    public var secondaryTextProperties = TextProperties(font: .systemFont(ofSize: 15), color: .secondaryLabel)
    public var directionalLayoutMargins = UIEdgeInsets(top: 11, left: 20, bottom: 11, right: 20)
    public var imageToTextPadding: CGFloat = 16
    public var textToSecondaryTextVerticalPadding: CGFloat = 2
    let layout: Layout
    /// A list cell's metrics (uikit/collection/list): body text in a 24.5 pt label 16 in, a
    /// subheadline secondary text in 21 below it 4 apart; rows 56 tall for one line, 79.5 for two.
    var listMetrics = false {
        didSet {
            guard listMetrics else { return }
            textProperties.font = .preferredFont(forTextStyle: .body)
            secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
            secondaryTextProperties.color = .secondaryLabel
            directionalLayoutMargins = UIEdgeInsets(top: 15, left: 16, bottom: 15, right: 16)
            textToSecondaryTextVerticalPadding = 4
        }
    }

    init(layout: Layout) {
        self.layout = layout
        if layout == .value { secondaryTextProperties = TextProperties(font: .systemFont(ofSize: 17), color: .secondaryLabel) }
    }

    public static func cell() -> UIListContentConfiguration { UIListContentConfiguration(layout: .cell) }
    public static func subtitleCell() -> UIListContentConfiguration { UIListContentConfiguration(layout: .subtitle) }
    public static func valueCell() -> UIListContentConfiguration { UIListContentConfiguration(layout: .value) }
    public static func plainHeader() -> UIListContentConfiguration { groupedHeader() }
    /// A grouped list header (uikit/collection/listheaders): headline text 10 down in 44.5.
    public static func groupedHeader() -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration(layout: .cell)
        configuration.textProperties.font = .preferredFont(forTextStyle: .headline)
        configuration.directionalLayoutMargins = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
        configuration.listRole = .header
        return configuration
    }
    public static func plainFooter() -> UIListContentConfiguration { groupedFooter() }
    /// A grouped list footer: footnote text in the secondary colour 8 down in 35.
    public static func groupedFooter() -> UIListContentConfiguration {
        var configuration = UIListContentConfiguration(layout: .cell)
        configuration.textProperties.font = .preferredFont(forTextStyle: .footnote)
        configuration.textProperties.color = .secondaryLabel
        configuration.directionalLayoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 6, right: 16)
        configuration.listRole = .footer
        return configuration
    }
    enum ListRole: Sendable { case cell, header, footer }
    var listRole: ListRole = .cell

    public func makeContentView() -> UIView & UIContentView { UIListContentView(configuration: self) }
}

/// The view a list content configuration makes.
@MainActor
public final class UIListContentView: UIView, UIContentView {
    public let textLabel = UILabel()
    public let secondaryTextLabel = UILabel()
    public let imageView = UIImageView()
    private var list: UIListContentConfiguration

    public var configuration: any UIContentConfiguration {
        get { list }
        set { if let list = newValue as? UIListContentConfiguration { self.list = list; apply() } }
    }

    public init(configuration: UIListContentConfiguration) {
        list = configuration
        super.init(frame: .zero)
        addSubview(imageView)
        addSubview(textLabel)
        addSubview(secondaryTextLabel)
        apply()
    }

    private func apply() {
        textLabel.text = list.text
        textLabel.font = list.textProperties.font
        textLabel.textColor = list.textProperties.color
        textLabel.numberOfLines = list.textProperties.numberOfLines
        secondaryTextLabel.text = list.secondaryText
        secondaryTextLabel.font = list.secondaryTextProperties.font
        secondaryTextLabel.textColor = list.secondaryTextProperties.color
        secondaryTextLabel.numberOfLines = list.secondaryTextProperties.numberOfLines
        imageView.image = list.image
        setNeedsLayout()
    }

    /// The content's height for a width: the margins around the text block (one line, or the
    /// text over the secondary text for the subtitle layout), at least 44; on the list's metrics
    /// a one-line row is 56 and a two-line one 79.5 (uikit/collection/list).
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        if list.listMetrics {
            let hasSecondary = secondaryTextLabel.text?.isEmpty == false && list.layout == .subtitle
            return CGSize(width: size.width, height: hasSecondary ? 79.5 : 56)
        }
        if list.listRole != .cell {
            // Headers and footers: the margins around the text's label height (24.5 for a
            // headline, 21 for a footnote line), no minimum.
            let margins = list.directionalLayoutMargins
            let width = max(0, size.width - margins.left - margins.right)
            return CGSize(width: size.width, height: roleTextHeight(width: width) + margins.top + margins.bottom)
        }
        let margins = list.directionalLayoutMargins
        let imageWidth = imageView.image.map { $0.size.width + list.imageToTextPadding } ?? 0
        let width = max(0, size.width - margins.left - margins.right - imageWidth)
        var height = textLabel.text?.isEmpty == false ? textLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height : 0
        if list.layout == .subtitle, secondaryTextLabel.text?.isEmpty == false {
            height += (height > 0 ? list.textToSecondaryTextVerticalPadding : 0) + secondaryTextLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        } else if list.layout != .subtitle {
            height = max(height, secondaryTextLabel.text?.isEmpty == false ? secondaryTextLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height : 0)
        }
        if let image = imageView.image { height = max(height, image.size.height) }
        return CGSize(width: size.width, height: max(44, height + margins.top + margins.bottom))
    }

    /// A header's or footer's text height for a width: the label's fit, at least 21 for a footer
    /// (UIKit lays a one-line footnote footer out 21 tall although the label fits in 19;
    /// uikit/collection/listheaders: 8 + 21 + 6 = 35).
    private func roleTextHeight(width: CGFloat) -> CGFloat {
        guard textLabel.text?.isEmpty == false else { return 0 }
        let fit = textLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return list.listRole == .footer ? max(21, fit) : fit
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        let margins = list.directionalLayoutMargins
        var x = margins.left
        if let image = imageView.image {
            imageView.frame = CGRect(x: x, y: ((bounds.height - image.size.height) / 2).rounded(), width: image.size.width, height: image.size.height)
            x += image.size.width + list.imageToTextPadding
        } else {
            imageView.frame = .zero
        }
        let width = max(0, bounds.width - x - margins.right)
        let textHeight = list.listRole == .cell ? (textLabel.text?.isEmpty == false ? textLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height : 0) : roleTextHeight(width: width)
        let secondaryHeight = secondaryTextLabel.text?.isEmpty == false ? secondaryTextLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height : 0
        switch list.layout {
        case .subtitle:
            let block = textHeight + (textHeight > 0 && secondaryHeight > 0 ? list.textToSecondaryTextVerticalPadding : 0) + secondaryHeight
            // A one-line list row puts its label 16 down in 56; two lines start 15 down in 79.5.
            let top = list.listMetrics ? (secondaryHeight > 0 ? 15 : 16) : ((bounds.height - block) / 2).rounded()
            textLabel.frame = CGRect(x: x, y: top, width: width, height: textHeight)
            secondaryTextLabel.frame = CGRect(x: x, y: top + textHeight + (textHeight > 0 ? list.textToSecondaryTextVerticalPadding : 0), width: width, height: secondaryHeight)
        case .value:
            let secondaryWidth = secondaryTextLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).width
            textLabel.frame = CGRect(x: x, y: ((bounds.height - textHeight) / 2).rounded(), width: max(0, width - secondaryWidth - 8), height: textHeight)
            secondaryTextLabel.frame = CGRect(x: x + width - secondaryWidth, y: ((bounds.height - secondaryHeight) / 2).rounded(), width: secondaryWidth, height: secondaryHeight)
            secondaryTextLabel.textAlignment = .right
        case .cell:
            let y = list.listRole == .cell ? ((bounds.height - textHeight) / 2).rounded() : margins.top
            textLabel.frame = CGRect(x: x, y: y, width: width, height: textHeight)
            secondaryTextLabel.frame = .zero
        }
    }
}

/// The content view a cell's configuration made, kept with the configuration that made it.
@MainActor
final class ConfiguredContent {
    let view: UIView & UIContentView
    init(view: UIView & UIContentView) { self.view = view }
}
