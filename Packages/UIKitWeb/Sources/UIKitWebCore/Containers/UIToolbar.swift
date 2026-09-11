// UIToolbar (Docs/elements/UIKit/Bars.md): the iOS 26 toolbar, a 48 pt row of glass platters
// 16 in from the sides (a title's width plus 24, 48 for an image, a `done` item filled with the
// tint), 12 apart, a fixed space adding its width and the flexible spaces sharing what is left;
// without a flexible space the items sit centred. Measured on the iPhone SE simulator
// (uikit/toolbar/basic).

/// A control that displays one or more buttons along the bottom edge of your interface.
@MainActor
open class UIToolbar: UIView {
    static let height: CGFloat = 48
    static let sideInset: CGFloat = 16
    static let spacing: CGFloat = 12

    open var items: [UIBarButtonItem]? { didSet { rebuild() } }
    /// A navigation controller's toolbar floats over the bottom of the screen (uikit/nav/toolbar):
    /// 76 tall with the platters in its top 48, 28 in from the sides, the items grouped by the
    /// flexible spaces (a leading group, a trailing one, a centred one between).
    var isFloating = false { didSet { setNeedsLayout() } }
    static let floatingInset: CGFloat = 28
    static let floatingHeight: CGFloat = 76
    open var barStyle = 0
    open var isTranslucent = true
    open var barTintColor: UIColor?
    open var standardAppearance = UIToolbarAppearance()
    open var scrollEdgeAppearance: UIToolbarAppearance?
    open var compactAppearance: UIToolbarAppearance?
    weak var delegate: AnyObject?

    private var buttons: [BarPlatterButton] = []

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: frame.height > 0 ? frame.height : Self.height)))
    }

    open func setItems(_ items: [UIBarButtonItem]?, animated: Bool) { self.items = items }

    /// A toolbar is as wide as proposed and 48 tall (`sizeToFit` on a zero frame keeps 0 wide).
    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: size.width < CGFloat.greatestFiniteMagnitude ? size.width : bounds.width, height: isFloating ? Self.floatingHeight : Self.height)
    }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: isFloating ? Self.floatingHeight : Self.height) }

    private func rebuild() {
        for button in buttons { button.removeFromSuperview() }
        buttons = []
        for item in items ?? [] {
            item.onChange = { [weak self] in self?.rebuild() }
            guard !item.isSpace else { continue }
            let button = BarPlatterButton(item: item, platterHeight: Self.height)
            button.tintColor = tintColor
            addSubview(button)
            buttons.append(button)
        }
        setNeedsLayout()
    }

    override open func layoutSubviews() {
        super.layoutSubviews()
        if isFloating { layoutFloating(); return }
        let items = items ?? []
        // Not `insetBy`: a bar narrower than the insets (a zero frame sized to fit) would give
        // the null rect; the content is then negative-width and the items centre on it.
        let content = CGRect(x: Self.sideInset, y: 0, width: bounds.width - 2 * Self.sideInset, height: bounds.height)
        var fixed: CGFloat = 0
        var flexible = 0
        var visible = 0
        for item in items {
            switch item.systemItem {
            case .flexibleSpace?: flexible += 1
            case .fixedSpace?: fixed += item.width
            default: visible += 1
            }
        }
        var index = 0
        for item in items where !item.isSpace {
            fixed += buttons[index].platterWidth
            index += 1
        }
        let gaps = CGFloat(max(0, visible - 1)) * Self.spacing
        let remaining = content.width - fixed - gaps
        let flex = flexible > 0 ? remaining / CGFloat(flexible) : 0
        var x = content.minX + (flexible > 0 ? 0 : remaining / 2)
        let scale = UIScreen.main.scale
        var previousWasPlatter = false
        index = 0
        for item in items {
            switch item.systemItem {
            case .flexibleSpace?:
                x += flex
            case .fixedSpace?:
                x += item.width
            default:
                if previousWasPlatter { x += Self.spacing }
                let button = buttons[index]
                index += 1
                let width = button.platterWidth
                button.frame = CGRect(x: (x * scale).rounded() / scale, y: 0, width: width, height: Self.height)
                x += width
                previousWasPlatter = true
                continue
            }
            // A space between two platters carries the 12 pt spacing too.
            if previousWasPlatter { x += Self.spacing; previousWasPlatter = false }
        }
    }
}

extension UIToolbar {
    /// The floating layout: the flexible spaces split the items into groups; one group leads,
    /// two lead and trail, three put the middle one centred, more spread evenly.
    private func layoutFloating() {
        let items = items ?? []
        let content = CGRect(x: Self.floatingInset, y: 0, width: bounds.width - 2 * Self.floatingInset, height: Self.height)
        var groups: [[(item: UIBarButtonItem, button: BarPlatterButton?)]] = [[]]
        var index = 0
        for item in items {
            if item.systemItem == .flexibleSpace { groups.append([]); continue }
            let button: BarPlatterButton? = item.isSpace ? nil : buttons[index]
            if button != nil { index += 1 }
            groups[groups.count - 1].append((item, button))
        }
        groups = groups.filter { !$0.isEmpty }
        let scale = UIScreen.main.scale
        func width(of group: [(item: UIBarButtonItem, button: BarPlatterButton?)]) -> CGFloat {
            var total: CGFloat = 0
            var previousWasPlatter = false
            for entry in group {
                if let button = entry.button {
                    if previousWasPlatter { total += Self.spacing }
                    total += button.platterWidth
                    previousWasPlatter = true
                } else {
                    if previousWasPlatter { total += Self.spacing; previousWasPlatter = false }
                    total += entry.item.width
                }
            }
            return total
        }
        func place(_ group: [(item: UIBarButtonItem, button: BarPlatterButton?)], at start: CGFloat) {
            var x = start
            var previousWasPlatter = false
            for entry in group {
                if let button = entry.button {
                    if previousWasPlatter { x += Self.spacing }
                    button.frame = CGRect(x: (x * scale).rounded() / scale, y: 0, width: button.platterWidth, height: Self.height)
                    x += button.platterWidth
                    previousWasPlatter = true
                } else {
                    if previousWasPlatter { x += Self.spacing; previousWasPlatter = false }
                    x += entry.item.width
                }
            }
        }
        let widths = groups.map(width(of:))
        switch groups.count {
        case 0: return
        case 1: place(groups[0], at: content.minX)
        case 2:
            place(groups[0], at: content.minX)
            place(groups[1], at: content.maxX - widths[1])
        case 3:
            place(groups[0], at: content.minX)
            place(groups[1], at: content.midX - widths[1] / 2)
            place(groups[2], at: content.maxX - widths[2])
        default:
            let gap = (content.width - widths.reduce(0, +)) / CGFloat(groups.count - 1)
            var x = content.minX
            for (group, width) in zip(groups, widths) { place(group, at: x); x += width + gap }
        }
    }
}

/// The appearance of a toolbar (accepted; the iOS 26 bar draws no background of its own).
@MainActor
public final class UIToolbarAppearance {
    public var backgroundColor: UIColor?
    public var shadowColor: UIColor?
    public init() {}
    public func configureWithOpaqueBackground() {}
    public func configureWithTransparentBackground() {}
    public func configureWithDefaultBackground() {}
}
