// UIAlertController and modal presentation (Docs/elements/UIKit/Presentation.md): alerts and
// action sheets as the iOS 26 centred glass card, presented view controllers as a page sheet
// card over a dimmed screen. Geometry from UIKit on the iPhone SE simulator.

/// An action that can be taken when the user taps a button in an alert.
@MainActor
public final class UIAlertAction {
    public enum Style: Int, Sendable { case `default` = 0, cancel, destructive }
    public let title: String?
    public let style: Style
    public var isEnabled = true
    let handler: ((UIAlertAction) -> Void)?

    public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) {
        self.title = title
        self.style = style
        self.handler = handler
    }
}

/// An object that displays an alert message.
@MainActor
open class UIAlertController: UIViewController {
    public enum Style: Int, Sendable { case actionSheet = 0, alert }

    public let preferredStyle: Style
    open var message: String?
    public private(set) var actions: [UIAlertAction] = []
    open var preferredAction: UIAlertAction?
    public private(set) var textFields: [UITextField]?
    open var severity = 0

    /// The card: 300 wide, 10 in from a 320 pt window, 34 pt corners.
    static let cardWidth: CGFloat = 300
    static let cornerRadius: CGFloat = 34
    static let actionHeight: CGFloat = 48
    static let actionGap: CGFloat = 8
    static let actionInset: CGFloat = 14

    public init(title: String?, message: String?, preferredStyle: Style) {
        self.preferredStyle = preferredStyle
        self.message = message
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = .custom
    }

    open func addAction(_ action: UIAlertAction) {
        actions.append(action)
        viewIfLoaded?.setNeedsLayout()
    }

    /// A text field in the card: 13 pt in a white 7 pt-cornered box 15 in, 34 tall
    /// (uikit/alert/textfield); the handler configures it before it is added.
    open func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
        let field = UITextField()
        field.borderStyle = .none
        field.font = .systemFont(ofSize: 13)
        configurationHandler?(field)
        textFields = (textFields ?? []) + [field]
        viewIfLoaded?.setNeedsLayout()
    }

    static let fieldRowHeight: CGFloat = 34
    static let fieldsBottomGap: CGFloat = 12

    /// The text fields' block under the header: 34 per field and 12 below (46, 80).
    var fieldsHeight: CGFloat {
        let count = textFields?.count ?? 0
        return count == 0 ? 0 : Self.fieldRowHeight * CGFloat(count) + Self.fieldsBottomGap
    }

    open override func loadView() {
        let view = AlertCardView(controller: self)
        self.view = view
    }

    /// The card's size for a width: the header (title and message lines) over the actions.
    func cardSize(width: CGFloat) -> CGSize {
        let card = view as? AlertCardView
        let header = card?.headerHeight ?? 0
        let actionsHeight = actionsAreSideBySide
            ? Self.actionHeight + 2 * Self.actionInset
            : (actions.isEmpty ? 0 : Self.actionInset * 2 + Self.actionHeight * CGFloat(actions.count) + Self.actionGap * CGFloat(actions.count - 1))
        return CGSize(width: width, height: header + fieldsHeight + actionsHeight)
    }

    /// Two actions of an alert share one row; an action sheet's and three or more stack.
    var actionsAreSideBySide: Bool { preferredStyle == .alert && actions.count == 2 }

    /// The actions in the order shown: the cancel action last (and, side by side, first on the
    /// left as the filled button).
    var orderedActions: [UIAlertAction] {
        let cancel = actions.filter { $0.style == .cancel }
        let others = actions.filter { $0.style != .cancel }
        return actionsAreSideBySide ? cancel + others : others + cancel
    }

    func perform(_ action: UIAlertAction) {
        dismiss(animated: true) { action.handler?(action) }
    }
}

/// The alert card: a glass capsule-cornered panel with the title (17 pt semibold, 28 in, 21.5
/// down), the message (15 pt, 23 tall lines) and the action buttons (48 tall capsules 14 in,
/// 8 apart; the cancel action filled with the tint, the others with the tertiary fill).
@MainActor
final class AlertCardView: UIView {
    unowned let controller: UIAlertController
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private var buttons: [AlertActionButton] = []

    init(controller: UIAlertController) {
        self.controller = controller
        super.init(frame: .zero)
        titleLabel.font = controller.preferredStyle == .actionSheet ? .systemFont(ofSize: 15) : .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 0
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        addSubview(titleLabel)
        addSubview(messageLabel)
    }

    /// The header: 21.5 above a 24.5 pt title line, 4.5 to 23 pt message lines, 10.5 below
    /// (84 for one line each); an action sheet's title alone is 15 pt, 24 down in 64.
    var headerHeight: CGFloat {
        let width = UIAlertController.cardWidth - 56
        titleLabel.text = controller.title
        messageLabel.text = controller.message
        let hasTitle = !(controller.title ?? "").isEmpty
        let hasMessage = !(controller.message ?? "").isEmpty
        if controller.preferredStyle == .actionSheet {
            guard hasTitle || hasMessage else { return 0 }
            var height: CGFloat = 24
            if hasTitle { height += max(21, messageStyleHeight(titleLabel, width: width)) }
            if hasMessage { height += (hasTitle ? 4 : 0) + max(21, messageStyleHeight(messageLabel, width: width)) }
            return height + 19
        }
        guard hasTitle || hasMessage else { return 0 }
        var height: CGFloat = 21.5
        if hasTitle { height += max(24.5, lines(titleLabel, width: width) * 24.5) }
        if hasMessage { height += (hasTitle ? 4.5 : 0) + max(23, lines(messageLabel, width: width) * 23) }
        // Text fields under a title alone sit 18 below it (uikit/alert/textfields: 64), 10.5 otherwise.
        return height + (hasTitle && !hasMessage && !(controller.textFields ?? []).isEmpty ? 18 : 10.5)
    }

    /// The text fields' boxes (in the card): 270 wide 15 in, 34 tall from the header, each
    /// row 34 lower less half a point after the first (uikit/alert/textfields), a secure
    /// field's box 32 tall.
    var fieldBoxes: [CGRect] {
        let top = headerHeight
        return (controller.textFields ?? []).enumerated().map { index, field in
            let y = top + UIAlertController.fieldRowHeight * CGFloat(index) - (index > 0 ? 0.5 : 0)
            return CGRect(x: 15, y: y, width: bounds.width - 30, height: field.isSecureTextEntry ? 32 : 34)
        }
    }

    private func lines(_ label: UILabel, width: CGFloat) -> CGFloat {
        let fitted = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return max(1, (fitted.height / (label.font.lineHeight + label.font.leading)).rounded())
    }

    private func messageStyleHeight(_ label: UILabel, width: CGFloat) -> CGFloat { lines(label, width: width) * 21 }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - 56
        let sheet = controller.preferredStyle == .actionSheet
        titleLabel.font = sheet ? .systemFont(ofSize: 15) : .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = sheet ? .secondaryLabel : .label
        messageLabel.textColor = sheet ? .secondaryLabel : .label
        var y: CGFloat = sheet ? 24 : 21.5
        if !(controller.title ?? "").isEmpty {
            let height = sheet ? max(21, messageStyleHeight(titleLabel, width: width)) : max(24.5, lines(titleLabel, width: width) * 24.5)
            titleLabel.frame = CGRect(x: 28, y: y, width: width, height: height)
            titleLabel.isHidden = false
            y += height + (sheet ? 4 : 4.5)
        } else {
            titleLabel.isHidden = true
        }
        if !(controller.message ?? "").isEmpty {
            let height = sheet ? max(21, messageStyleHeight(messageLabel, width: width)) : max(23, lines(messageLabel, width: width) * 23)
            messageLabel.frame = CGRect(x: 28, y: y, width: width, height: height)
            messageLabel.isHidden = false
        } else {
            messageLabel.isHidden = true
        }
        // The text fields in their boxes: 7 in, 7 down, the text line tall (20.5; 19 secure).
        for (field, box) in zip(controller.textFields ?? [], fieldBoxes) {
            if field.superview !== self { addSubview(field) }
            let height: CGFloat = field.isSecureTextEntry ? 19 : 20.5
            field.frame = CGRect(x: box.minX + 7.5, y: box.minY + 7, width: box.width - 15, height: height)
        }
        // The action buttons under the header and the fields.
        let ordered = controller.orderedActions
        if buttons.count != ordered.count || zip(buttons, ordered).contains(where: { $0.action !== $1 }) {
            for button in buttons { button.removeFromSuperview() }
            buttons = ordered.map { action in
                let button = AlertActionButton(action: action)
                button.addAction(UIAction { [weak self] _ in self?.controller.perform(action) }, for: .primaryActionTriggered)
                addSubview(button)
                return button
            }
        }
        let top = headerHeight + controller.fieldsHeight + UIAlertController.actionInset
        let inner = bounds.width - 2 * UIAlertController.actionInset
        if controller.actionsAreSideBySide {
            let each = (inner - UIAlertController.actionGap) / 2
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: UIAlertController.actionInset + (each + UIAlertController.actionGap) * CGFloat(index), y: top, width: each, height: UIAlertController.actionHeight)
            }
        } else {
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: UIAlertController.actionInset, y: top + (UIAlertController.actionHeight + UIAlertController.actionGap) * CGFloat(index),
                                      width: inner, height: UIAlertController.actionHeight)
            }
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        // The glass: white at 67 % over the dimmed screen ((238, 238, 238) over the 20 % dim on
        // white, uikit/alert/basic).
        let fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46, a: 0.9) : RGBA(r: 255, g: 255, b: 255, a: 0.67)
        list.append(.fillPath(Path(roundedRect: rect, cornerRadius: UIAlertController.cornerRadius, style: .continuous), fill))
        // Each text field's box: a white 7 pt-cornered ring 0.5 wide around the system background.
        let ring: RGBA = style == .dark ? RGBA(r: 255, g: 255, b: 255, a: 0.15) : RGBA(r: 255, g: 255, b: 255, a: 1)
        let inside = UIColor.systemBackground.rgba(for: style)
        for box in fieldBoxes {
            let absolute = context.absoluteRect(box)
            list.append(.fillRRect(absolute, cornerRadius: 7, ring))
            list.append(.fillRRect(absolute.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 7, inside))
        }
    }
}

/// One action button: a 48 pt capsule (the cancel action in the tint with a white semibold
/// title, the others in the tertiary fill with a 17 pt title, red for a destructive one).
@MainActor
final class AlertActionButton: UIControl {
    let action: UIAlertAction
    private let label = UILabel()

    init(action: UIAlertAction) {
        self.action = action
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = action.title
        isEnabled = action.isEnabled
        label.text = action.title
        label.font = .systemFont(ofSize: 17, weight: action.style == .cancel ? .semibold : .regular)
        label.textAlignment = .center
        addSubview(label)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.textColor = action.style == .cancel ? .white : (action.style == .destructive ? .systemRed : .label)
        let width = label.intrinsicContentSize.width
        label.frame = CGRect(x: ((bounds.width - width) / 2 * 2).rounded() / 2, y: 11, width: width, height: 26.5)
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let fill = action.style == .cancel ? tintColor.rgba(for: style) : UIColor.tertiarySystemFill.rgba(for: style)
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, fill))
    }
}

/// What a presentation puts in the window: a dimming view over the presenter and the presented
/// controller's view as the card its style calls for.
@MainActor
final class PresentationContainerView: UIView {
    /// Weak: the presenter owns the presented controller, and a container whose controller has
    /// gone (a presenter released while presenting) leaves the window at the next layout.
    private(set) weak var controller: UIViewController?
    let dimming = UIView()

    init(controller: UIViewController, frame: CGRect) {
        self.controller = controller
        super.init(frame: frame)
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.frame = bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(dimming)
    }

    /// A tap on the dimming outside a sheet dismisses it (alerts stay).
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        guard let touch = touches.first, let controller, let content = controller.viewIfLoaded else { return }
        let location = touch.location(in: self)
        if !content.frame.contains(location), !(controller is UIAlertController), !controller.isModalInPresentation {
            controller.dismiss(animated: true)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let controller else { removeFromSuperview(); return }
        guard let content = controller.viewIfLoaded else { return }
        let size = bounds.size
        if let alert = controller as? UIAlertController {
            // The alert card: 300 wide (10 in from 320), centred.
            dimming.backgroundColor = UIColor(white: 0, alpha: 0.2)
            let width = min(UIAlertController.cardWidth, size.width - 20)
            let card = alert.cardSize(width: width)
            content.frame = CGRect(x: ((size.width - width) / 2).rounded(), y: ((size.height - card.height) / 2).rounded(), width: width, height: card.height)
            content.layer.cornerRadius = UIAlertController.cornerRadius
            content.layer.cornerCurve = .continuous
            content.clipsToBounds = true
            return
        }
        switch controller.modalPresentationStyle {
        case .fullScreen, .overFullScreen, .currentContext, .overCurrentContext, .custom, .none:
            dimming.backgroundColor = .clear
            content.frame = bounds
        default:
            // The page sheet: a card 29.86875 down to the bottom (measured in a 500 pt window with
            // no status bar; uikit/sheet/page), 38 pt top corners, over a 20 % dim.
            dimming.backgroundColor = UIColor(white: 0, alpha: 0.2)
            let top: CGFloat = 29.86875
            content.frame = CGRect(x: 0, y: top, width: size.width, height: size.height - 30)
            content.layer.cornerRadius = 38
            content.layer.cornerCurve = .continuous
            content.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            content.clipsToBounds = true
        }
    }
}
