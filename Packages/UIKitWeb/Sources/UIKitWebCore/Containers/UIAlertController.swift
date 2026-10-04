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
    /// An action sheet anchored to a source (its popover presentation controller's source view
    /// or bar button item) is a 240 pt popover above it: the actions 15.5 in and 14 from the
    /// bottom, the title 24 down in a 71 pt header, no cancel action (uikit/alert/anchored).
    static let anchoredWidth: CGFloat = 240
    static let anchoredActionInset: CGFloat = 15.5
    static let anchoredBottomInset: CGFloat = 14

    /// Whether the action sheet floats over its source as a popover.
    package var isAnchored: Bool {
        guard preferredStyle == .actionSheet, let popover = popoverPresentationController else { return false }
        return popover.sourceView != nil || popover.barButtonItem != nil
    }

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
        let shown = orderedActions.count
        let actionsHeight: CGFloat
        if actionsAreSideBySide {
            actionsHeight = Self.actionHeight + 2 * Self.actionInset
        } else if isAnchored {
            // The header's 26 under the title already separates the actions.
            actionsHeight = shown == 0 ? 0 : Self.anchoredBottomInset + Self.actionHeight * CGFloat(shown) + Self.actionGap * CGFloat(shown - 1)
        } else {
            actionsHeight = shown == 0 ? 0 : Self.actionInset * 2 + Self.actionHeight * CGFloat(shown) + Self.actionGap * CGFloat(shown - 1)
        }
        return CGSize(width: width, height: header + fieldsHeight + actionsHeight)
    }

    /// Two actions of an alert share one row; an action sheet's and three or more stack.
    var actionsAreSideBySide: Bool { preferredStyle == .alert && actions.count == 2 }

    /// The actions in the order shown: the cancel action last (and, side by side, first on the
    /// left as the filled button); an anchored sheet shows no cancel action (a tap outside
    /// dismisses it).
    package var orderedActions: [UIAlertAction] {
        let cancel = actions.filter { $0.style == .cancel }
        let others = actions.filter { $0.style != .cancel }
        if isAnchored { return others }
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
        let width = (controller.isAnchored ? UIAlertController.anchoredWidth : UIAlertController.cardWidth) - 56
        titleLabel.text = controller.title
        messageLabel.text = controller.message
        let hasTitle = !(controller.title ?? "").isEmpty
        let hasMessage = !(controller.message ?? "").isEmpty
        if controller.preferredStyle == .actionSheet {
            guard hasTitle || hasMessage else { return 0 }
            var height: CGFloat = 24
            if hasTitle { height += max(21, messageStyleHeight(titleLabel, width: width)) }
            if hasMessage { height += (hasTitle ? 4 : 0) + max(21, messageStyleHeight(messageLabel, width: width)) }
            // An anchored sheet's actions start 26 under the title (a 71 pt header), 19 otherwise.
            return height + (controller.isAnchored ? 26 : 19)
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
        let sideInset = controller.isAnchored ? UIAlertController.anchoredActionInset : UIAlertController.actionInset
        let top = headerHeight + controller.fieldsHeight + (controller.isAnchored ? 0 : sideInset)
        let inner = bounds.width - 2 * sideInset
        if controller.actionsAreSideBySide {
            let each = (inner - UIAlertController.actionGap) / 2
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: sideInset + (each + UIAlertController.actionGap) * CGFloat(index), y: top, width: each, height: UIAlertController.actionHeight)
            }
        } else {
            for (index, button) in buttons.enumerated() {
                button.frame = CGRect(x: sideInset, y: top + (UIAlertController.actionHeight + UIAlertController.actionGap) * CGFloat(index),
                                      width: inner, height: UIAlertController.actionHeight)
            }
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        // The glass: white at 67 % over the dimmed screen ((238, 238, 238) over the 20 % dim on
        // white, uikit/alert/basic).
        var fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46, a: 0.9) : RGBA(r: 255, g: 255, b: 255, a: 0.67)
        // Anchored, the card floats over the undimmed screen: (244, 244, 244) on white.
        if controller.isAnchored { fill = style == .dark ? RGBA(r: 44, g: 44, b: 46, a: 1) : RGBA(r: 244, g: 244, b: 244, a: 1) }
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
        let anchoredAlert = (controller as? UIAlertController)?.isAnchored == true
        if !content.frame.contains(location), !(controller is UIAlertController) || anchoredAlert, !controller.isModalInPresentation {
            // The presentation controller's delegate may veto the dismissal and hears of it.
            let adaptive = controller.presentationController?.adaptiveDelegate
            if let presentation = controller.presentationController, let adaptive, !adaptive.presentationControllerShouldDismiss(presentation) {
                adaptive.presentationControllerDidAttemptToDismiss(presentation)
                return
            }
            if let presentation = controller.presentationController { adaptive?.presentationControllerWillDismiss(presentation) }
            controller.dismiss(animated: true) { [weak controller] in
                guard let controller, let presentation = controller.presentationController else { return }
                presentation.adaptiveDelegate?.presentationControllerDidDismiss(presentation)
                (presentation as? UIPopoverPresentationController)?.delegate?.popoverPresentationControllerDidDismissPopover(presentation as! UIPopoverPresentationController)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let controller else { removeFromSuperview(); return }
        guard let content = controller.viewIfLoaded else { return }
        let size = bounds.size
        if let alert = controller as? UIAlertController, alert.isAnchored {
            // An anchored action sheet: a 240 pt card above its source with the arrow below it
            // (the arrow outside the card's frame; uikit/alert/anchored).
            layoutPopover(content, size: size, panelSize: alert.cardSize(width: UIAlertController.anchoredWidth), arrowInsideFrame: false)
            return
        }
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
        content.layer.popoverArrow = nil
        switch controller.modalPresentationStyle {
        case .fullScreen, .overFullScreen, .currentContext, .overCurrentContext, .custom, .none:
            dimming.backgroundColor = .clear
            content.frame = bounds
        case .popover where controller.popoverPresentationController?.staysPopover == true:
            var panelSize = controller.preferredContentSize
            if panelSize.width <= 0 || panelSize.height <= 0 { panelSize = CGSize(width: 320, height: 480) }
            layoutPopover(content, size: size, panelSize: panelSize, arrowInsideFrame: true)
        default:
            dimming.backgroundColor = UIColor(white: 0, alpha: 0.2)
            let sheet = controller.sheetPresentationController
            if sheet?.currentDetent?.identifier == .medium || sheet?.currentDetent?.resolver != nil {
                // The medium detent (uikit/sheet/medium, a 500 pt window): a card 0.592 of the
                // window tall ending a third of a point above the bottom, scaled by 0.971318
                // about its centre (4.59 in from the sides and the bottom), every corner 39; a
                // custom detent takes the height its resolver gives.
                var height = (size.height * Self.mediumDetentHeightFraction).rounded()
                if let resolver = sheet?.currentDetent?.resolver, let custom = resolver(size.height - Self.sheetTop) { height = custom }
                let radius = sheet?.preferredCornerRadius ?? 39
                content.transform = .identity
                content.frame = CGRect(x: 0, y: size.height - height - Self.mediumDetentBottomGap, width: size.width, height: height)
                content.transform = CGAffineTransform(scaleX: Self.mediumDetentScale, y: Self.mediumDetentScale)
                content.layer.cornerRadius = radius
                content.layer.cornerCurve = .continuous
                content.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                content.clipsToBounds = true
            } else {
                // The page sheet: a card 29.86875 down to the bottom (measured in a 500 pt window with
                // no status bar; uikit/sheet/page), 38 pt top corners, over a 20 % dim.
                content.transform = .identity
                content.frame = CGRect(x: 0, y: Self.sheetTop, width: size.width, height: size.height - 30)
                content.layer.cornerRadius = sheet?.preferredCornerRadius ?? 38
                content.layer.cornerCurve = .continuous
                content.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                content.clipsToBounds = true
            }
            layoutGrabber(over: content, visible: sheet?.prefersGrabberVisible == true)
        }
    }

    static let sheetTop: CGFloat = 29.86875
    // Fitted to uikit/sheet/medium's frames (a 500 pt window) to a hundredth of a point: the
    // card is 296 tall (0.592 of the window) and scaled 0.9713175 about its centre.
    static let mediumDetentHeightFraction: CGFloat = 0.592
    static let mediumDetentBottomGap: CGFloat = 0.3343
    static let mediumDetentScale: CGFloat = 0.9713175

    /// The grabber: 34 × 5, 5.5 below the card's top, black at 25 % (uikit/sheet/medium).
    private var grabber: GrabberView?

    private func layoutGrabber(over content: UIView, visible: Bool) {
        guard visible else { grabber?.removeFromSuperview(); grabber = nil; return }
        let view = grabber ?? GrabberView(frame: .zero)
        if view.superview !== self { addSubview(view) }
        grabber = view
        view.frame = CGRect(x: content.frame.midX - 17, y: content.frame.minY + 5.5, width: 34, height: 5)
        bringSubviewToFront(view)
    }

    /// A popover (or an anchored action sheet): a card of `panelSize` centred on its source,
    /// 13 above it with a 24 × 13 arrow pointing at the source's centre (below it when there is
    /// no room above), 34 pt corners, no dim, a soft shadow (uikit/popover/basic). A presented
    /// controller's view spans the arrow too (133 tall for a 120 pt content size); the alert
    /// card keeps the arrow outside its frame.
    private func layoutPopover(_ content: UIView, size: CGSize, panelSize: CGSize, arrowInsideFrame: Bool) {
        dimming.backgroundColor = .clear
        guard let popover = controller?.popoverPresentationController else { content.frame = bounds; return }
        var panelSize = panelSize
        panelSize.width = min(panelSize.width, size.width - 2 * popover.popoverLayoutMargins.left)
        panelSize.height = min(panelSize.height, size.height - 2 * popover.popoverLayoutMargins.top)
        let source = popover.sourceFrame(in: self) ?? CGRect(x: size.width / 2, y: size.height / 2, width: 0, height: 0)
        let arrow = Self.popoverArrowSize
        let fitsAbove = source.minY - arrow.height - panelSize.height >= popover.popoverLayoutMargins.top
        let pointsDown = popover.permittedArrowDirections.contains(.down) && (fitsAbove || !popover.permittedArrowDirections.contains(.up))
        popover.arrowDirection = pointsDown ? .down : .up
        var x = (source.midX - panelSize.width / 2).rounded()
        x = min(max(x, popover.popoverLayoutMargins.left), size.width - popover.popoverLayoutMargins.right - panelSize.width)
        let cardY = pointsDown ? source.minY - arrow.height - panelSize.height : source.maxY + arrow.height
        let arrowFrame = CGRect(x: source.midX - arrow.width / 2, y: pointsDown ? cardY + panelSize.height : cardY - arrow.height, width: arrow.width, height: arrow.height)
        if arrowInsideFrame {
            content.frame = CGRect(x: x, y: pointsDown ? cardY : cardY - arrow.height, width: panelSize.width, height: panelSize.height + arrow.height)
            content.layer.popoverArrow = CGRect(x: arrowFrame.minX - content.frame.minX, y: arrowFrame.minY - content.frame.minY, width: arrow.width, height: arrow.height)
            content.layer.popoverArrowPointsDown = pointsDown
            content.layer.popoverCardHeight = panelSize.height
            arrowView.isHidden = true
        } else {
            content.frame = CGRect(x: x, y: cardY, width: panelSize.width, height: panelSize.height)
            arrowView.isHidden = false
            if arrowView.superview !== self { addSubview(arrowView) }
            arrowView.pointsDown = pointsDown
            arrowView.frame = arrowFrame
        }
        content.layer.cornerRadius = Self.popoverCornerRadius
        content.layer.cornerCurve = .continuous
        content.clipsToBounds = true
        // The soft shadow around a popover (the screen darkens to (236) beside the card and
        // fades out over some 60 pt; approximated by the layer's shadow).
        content.layer.shadowColor = RGBA(red: 0, green: 0, blue: 0, alpha: 1).cgColor
        content.layer.shadowOpacity = 0.16
        content.layer.shadowRadius = 30
        content.layer.shadowOffset = CGSize(width: 0, height: 10)
    }

    static let popoverArrowSize = CGSize(width: 24, height: 13)
    static let popoverCornerRadius: CGFloat = 34
    private lazy var arrowView = PopoverArrowView(frame: .zero)
}

/// The sheet's grabber.
@MainActor
final class GrabberView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, RGBA(red: 0, green: 0, blue: 0, alpha: 0.25)))
    }
}

/// A popover's arrow (the panel's colour).
@MainActor
final class PopoverArrowView: UIView {
    var pointsDown = true { didSet { setNeedsDisplay() } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        var path = Path()
        if pointsDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        }
        path.closeSubpath()
        // The alert card's arrow takes the anchored card's colour.
        list.append(.fillPath(path, style == .dark ? RGBA(r: 44, g: 44, b: 46, a: 1) : RGBA(r: 244, g: 244, b: 244, a: 1)))
    }
}
