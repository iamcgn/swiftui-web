// Auto Layout's API (Docs/elements/UIKit/AutoLayout.md): constraints between the attributes of
// views and layout guides, the anchor objects that create them, activation on the items'
// closest common ancestor, and the view-side bookkeeping (`constraints`, `updateConstraints`,
// layout guides). The engine that solves them is `LayoutEngine.swift` (decision 0014, Phase 3).

/// A relationship between two user interface objects that must be satisfied by the
/// constraint-based layout system.
@MainActor
public final class NSLayoutConstraint {
    public enum Axis: Int, Sendable {
        case horizontal = 0, vertical = 1
    }

    public enum Attribute: Int, Sendable {
        case left = 1, right, top, bottom, leading, trailing, width, height, centerX, centerY, lastBaseline, firstBaseline
        case leftMargin, rightMargin, topMargin, bottomMargin, leadingMargin, trailingMargin, centerXWithinMargins, centerYWithinMargins
        case notAnAttribute = 0
    }

    public enum Relation: Int, Sendable {
        case lessThanOrEqual = -1, equal = 0, greaterThanOrEqual = 1
    }

    public struct FormatOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let alignAllLeading = FormatOptions(rawValue: 1 << 5)
        public static let alignAllTrailing = FormatOptions(rawValue: 1 << 6)
        public static let alignAllCenterX = FormatOptions(rawValue: 1 << 9)
        public static let alignAllCenterY = FormatOptions(rawValue: 1 << 10)
        public static let directionLeadingToTrailing = FormatOptions([])
    }

    public private(set) weak var firstItem: AnyObject?
    public let firstAttribute: Attribute
    public let relation: Relation
    public private(set) weak var secondItem: AnyObject?
    public let secondAttribute: Attribute
    public let multiplier: CGFloat
    /// The constant; changing it re-solves the layout (an animation block animates the move).
    public var constant: CGFloat {
        didSet { if constant != oldValue { holder?.setNeedsLayout() } }
    }
    public var priority: UILayoutPriority = .required {
        didSet { if priority != oldValue { holder?.setNeedsLayout() } }
    }
    public var identifier: String?
    public var shouldBeArchived = false

    /// The view whose `constraints` hold this one while it is active.
    weak var holder: UIView?

    public init(item view1: Any, attribute attr1: Attribute, relatedBy relation: Relation, toItem view2: Any?, attribute attr2: Attribute,
                multiplier: CGFloat, constant: CGFloat) {
        firstItem = view1 as AnyObject
        firstAttribute = attr1
        self.relation = relation
        secondItem = view2 as AnyObject?
        secondAttribute = attr2
        self.multiplier = multiplier
        self.constant = constant
    }

    /// Whether the constraint takes part in layout: activating it adds it to the closest common
    /// ancestor of its items, deactivating removes it.
    public var isActive: Bool {
        get { holder != nil }
        set {
            if newValue {
                guard holder == nil, let target = Self.commonAncestor(of: firstItem, secondItem) else { return }
                target.addConstraint(self)
            } else {
                holder?.removeConstraint(self)
            }
        }
    }

    public static func activate(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { constraint.isActive = true }
    }

    public static func deactivate(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { constraint.isActive = false }
    }

    /// The view an item's geometry belongs to (a guide's owner, a view itself).
    static func view(of item: AnyObject?) -> UIView? {
        if let view = item as? UIView { return view }
        if let guide = item as? UILayoutGuide { return guide.owningView }
        return nil
    }

    /// The closest view that is (or contains) both items.
    static func commonAncestor(of first: AnyObject?, _ second: AnyObject?) -> UIView? {
        guard let a = view(of: first) else { return nil }
        guard let b = second.flatMap({ view(of: $0) }) else { return a }
        var chain: [UIView] = []
        var current: UIView? = a
        while let view = current { chain.append(view); current = view.superview }
        current = b
        while let view = current {
            if chain.contains(where: { $0 === view }) { return view }
            current = view.superview
        }
        return nil
    }

    /// Visual format constraints are not parsed: the call returns nothing (sources compile).
    public static func constraints(withVisualFormat format: String, options: FormatOptions = [], metrics: [String: Any]?, views: [String: Any]) -> [NSLayoutConstraint] {
        []
    }
}

// MARK: - Anchors

/// A factory class for creating layout constraint objects using a fluent API.
@MainActor
open class NSLayoutAnchor<AnchorType: AnyObject> {
    let item: AnyObject
    let attribute: NSLayoutConstraint.Attribute

    init(item: AnyObject, attribute: NSLayoutConstraint.Attribute) {
        self.item = item
        self.attribute = attribute
    }

    func make(_ relation: NSLayoutConstraint.Relation, to anchor: NSLayoutAnchor<AnchorType>?, multiplier: CGFloat = 1, constant: CGFloat = 0) -> NSLayoutConstraint {
        NSLayoutConstraint(item: item, attribute: attribute, relatedBy: relation, toItem: anchor?.item, attribute: anchor?.attribute ?? .notAnAttribute,
                           multiplier: multiplier, constant: constant)
    }

    public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.equal, to: anchor) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.greaterThanOrEqual, to: anchor) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>) -> NSLayoutConstraint { make(.lessThanOrEqual, to: anchor) }
    public func constraint(equalTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.equal, to: anchor, constant: c) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, to: anchor, constant: c) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutAnchor<AnchorType>, constant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, to: anchor, constant: c) }
}

/// The system spacing between sibling views (`constraint(equalToSystemSpacingAfter:multiplier:)`).
let systemSpacing: CGFloat = 8

/// A factory class for creating horizontal layout constraint objects using a fluent API.
@MainActor
public final class NSLayoutXAxisAnchor: NSLayoutAnchor<NSLayoutXAxisAnchor> {
    public func constraint(equalToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.equal, to: anchor, constant: systemSpacing * multiplier)
    }
    public func constraint(greaterThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, to: anchor, constant: systemSpacing * multiplier)
    }
    public func constraint(lessThanOrEqualToSystemSpacingAfter anchor: NSLayoutXAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, to: anchor, constant: systemSpacing * multiplier)
    }
}

/// A factory class for creating vertical layout constraint objects using a fluent API.
@MainActor
public final class NSLayoutYAxisAnchor: NSLayoutAnchor<NSLayoutYAxisAnchor> {
    public func constraint(equalToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.equal, to: anchor, constant: systemSpacing * multiplier)
    }
    public func constraint(greaterThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.greaterThanOrEqual, to: anchor, constant: systemSpacing * multiplier)
    }
    public func constraint(lessThanOrEqualToSystemSpacingBelow anchor: NSLayoutYAxisAnchor, multiplier: CGFloat) -> NSLayoutConstraint {
        make(.lessThanOrEqual, to: anchor, constant: systemSpacing * multiplier)
    }
}

/// A factory class for creating size-based layout constraint objects using a fluent API.
@MainActor
public final class NSLayoutDimension: NSLayoutAnchor<NSLayoutDimension> {
    public func constraint(equalToConstant c: CGFloat) -> NSLayoutConstraint { make(.equal, to: nil, constant: c) }
    public func constraint(greaterThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, to: nil, constant: c) }
    public func constraint(lessThanOrEqualToConstant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, to: nil, constant: c) }
    public func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.equal, to: anchor, multiplier: m) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, to: anchor, multiplier: m) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, to: anchor, multiplier: m) }
    public func constraint(equalTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { make(.equal, to: anchor, multiplier: m, constant: c) }
    public func constraint(greaterThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { make(.greaterThanOrEqual, to: anchor, multiplier: m, constant: c) }
    public func constraint(lessThanOrEqualTo anchor: NSLayoutDimension, multiplier m: CGFloat, constant c: CGFloat) -> NSLayoutConstraint { make(.lessThanOrEqual, to: anchor, multiplier: m, constant: c) }
}

// MARK: - Layout guides

/// A rectangular area that can interact with Auto Layout.
@MainActor
open class UILayoutGuide {
    public private(set) weak var owningView: UIView?
    public var identifier = ""
    /// The frame the last layout pass solved, in the owning view's coordinates.
    public internal(set) var layoutFrame = CGRect.zero

    /// A system guide's insets from the owning view's bounds, when it is one (the safe area or
    /// layout margins guide); nil for a guide the app made.
    var systemInsets: (@MainActor (UIView) -> UIEdgeInsets)?

    public init() {}

    func attach(to view: UIView) { owningView = view }

    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .left) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .right) }
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
}

// MARK: - The view side

extension UIView {
    public var leadingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .leading) }
    public var trailingAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .trailing) }
    public var leftAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .left) }
    public var rightAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .right) }
    public var topAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .top) }
    public var bottomAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .bottom) }
    public var widthAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .width) }
    public var heightAnchor: NSLayoutDimension { NSLayoutDimension(item: self, attribute: .height) }
    public var centerXAnchor: NSLayoutXAxisAnchor { NSLayoutXAxisAnchor(item: self, attribute: .centerX) }
    public var centerYAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .centerY) }
    public var firstBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .firstBaseline) }
    public var lastBaselineAnchor: NSLayoutYAxisAnchor { NSLayoutYAxisAnchor(item: self, attribute: .lastBaseline) }

    /// The constraints held by this view (the closest common ancestor of their items).
    public var constraints: [NSLayoutConstraint] { layoutState.constraints }

    public func addConstraint(_ constraint: NSLayoutConstraint) {
        guard !layoutState.constraints.contains(where: { $0 === constraint }) else { return }
        constraint.holder?.removeConstraint(constraint)
        layoutState.constraints.append(constraint)
        constraint.holder = self
        setNeedsLayout()
    }

    public func addConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { addConstraint(constraint) }
    }

    public func removeConstraint(_ constraint: NSLayoutConstraint) {
        guard layoutState.constraints.contains(where: { $0 === constraint }) else { return }
        layoutState.constraints.removeAll { $0 === constraint }
        if constraint.holder === self { constraint.holder = nil }
        setNeedsLayout()
    }

    public func removeConstraints(_ constraints: [NSLayoutConstraint]) {
        for constraint in constraints { removeConstraint(constraint) }
    }

    /// The constraints that place this view along `axis`, from its own holder up.
    public func constraintsAffectingLayout(for axis: NSLayoutConstraint.Axis) -> [NSLayoutConstraint] {
        var result: [NSLayoutConstraint] = []
        var view: UIView? = self
        while let v = view {
            result += v.constraints.filter { ($0.firstItem === self || $0.secondItem === self) && $0.firstAttribute.axis == axis }
            view = v.superview
        }
        return result
    }

    public var hasAmbiguousLayout: Bool { false }
    public func exerciseAmbiguityInLayout() {}

    // MARK: The update-constraints pass

    public func setNeedsUpdateConstraints() {
        layoutState.needsUpdateConstraints = true
        setNeedsLayout()
    }

    public func needsUpdateConstraints() -> Bool { layoutState.needsUpdateConstraints }

    /// Runs `updateConstraints` on every view in the subtree that asked for it, deepest first.
    public func updateConstraintsIfNeeded() {
        for subview in subviews { subview.updateConstraintsIfNeeded() }
        if layoutState.needsUpdateConstraints {
            layoutState.needsUpdateConstraints = false
            updateConstraints()
        }
    }

    // MARK: Layout guides

    public var layoutGuides: [UILayoutGuide] { layoutState.guides }

    public func addLayoutGuide(_ guide: UILayoutGuide) {
        guard !layoutState.guides.contains(where: { $0 === guide }) else { return }
        guide.owningView?.removeLayoutGuide(guide)
        layoutState.guides.append(guide)
        guide.attach(to: self)
        setNeedsLayout()
    }

    public func removeLayoutGuide(_ guide: UILayoutGuide) {
        layoutState.guides.removeAll { $0 === guide }
        guide.attach(to: UIView.detached)
        setNeedsLayout()
    }

    /// The layout guide representing the portion of the view that is unobscured by bars and
    /// other content.
    public var safeAreaLayoutGuide: UILayoutGuide {
        systemGuide(&layoutState.safeAreaGuide, insets: { $0.safeAreaInsets })
    }

    /// A layout guide representing the view's margins.
    public var layoutMarginsGuide: UILayoutGuide {
        systemGuide(&layoutState.marginsGuide, insets: { $0.effectiveLayoutMargins })
    }

    /// A layout guide representing an area with a readable width within the view.
    public var readableContentGuide: UILayoutGuide { layoutMarginsGuide }

    private func systemGuide(_ slot: inout UILayoutGuide?, insets: @escaping @MainActor (UIView) -> UIEdgeInsets) -> UILayoutGuide {
        if let guide = slot { return guide }
        let guide = UILayoutGuide()
        guide.systemInsets = insets
        guide.attach(to: self)
        slot = guide
        return guide
    }

    /// The margins layout uses: the view's own, or for a view controller's root view the system
    /// minimum (16 sideways, the safe area vertically: `uikit/autolayout/guides` gives (16, 0)
    /// with no status bar), which margins the app sets are raised to while
    /// `viewRespectsSystemMinimumLayoutMargins` holds.
    var effectiveLayoutMargins: UIEdgeInsets {
        guard let controller = owningViewController, controller.viewRespectsSystemMinimumLayoutMargins else { return layoutMargins }
        let safe = safeAreaInsets
        let system = controller.systemMinimumLayoutMargins
        let minimum = UIEdgeInsets(top: max(system.top, safe.top), left: max(system.leading, safe.left),
                                   bottom: max(system.bottom, safe.bottom), right: max(system.trailing, safe.right))
        guard hasExplicitLayoutMargins else { return minimum }
        let margins = layoutMargins
        return UIEdgeInsets(top: max(margins.top, minimum.top), left: max(margins.left, minimum.left),
                            bottom: max(margins.bottom, minimum.bottom), right: max(margins.right, minimum.right))
    }

    /// A stand-in owner for a guide removed from its view.
    static let detached = UIView()
}

extension NSLayoutConstraint.Attribute {
    var axis: NSLayoutConstraint.Axis {
        switch self {
        case .left, .right, .leading, .trailing, .width, .centerX, .leftMargin, .rightMargin, .leadingMargin, .trailingMargin, .centerXWithinMargins: return .horizontal
        default: return .vertical
        }
    }
}
