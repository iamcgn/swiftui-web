// UIView (Docs/elements/UIKit/UIView.md): the view tree over the layer tree. Geometry goes
// through the layer (frame, bounds, center, transform); subviews are the layer's sublayers in
// order; layout is the needs-layout cycle with autoresizing; input is hit testing plus the
// responder chain.

/// An object that manages the content for a rectangular area on the screen.
@MainActor
open class UIView: UIResponder, UITraitEnvironment {
    /// The layer class this view creates (`CALayer` unless overridden).
    open class var layerClass: AnyClass { CALayer.self }

    /// The view's Core Animation layer.
    public let layer: CALayer

    public init(frame: CGRect) {
        layer = (Self.layerClass as? CALayer.Type)?.init() ?? CALayer()
        super.init()
        layer.view = self
        layer.contentsScale = UIScreen.main.scale
        self.frame = frame
    }

    public convenience override init() {
        self.init(frame: .zero)
    }

    // MARK: Geometry

    open var frame: CGRect {
        get { layer.frame }
        set {
            let oldBounds = bounds
            layer.frame = newValue
            if oldBounds.size != newValue.size { sizeDidChange(from: oldBounds.size) }
        }
    }

    open var bounds: CGRect {
        get { layer.bounds }
        set {
            let old = layer.bounds
            layer.bounds = newValue
            if old.size != newValue.size { sizeDidChange(from: old.size) }
        }
    }

    open var center: CGPoint {
        get { layer.position }
        set { layer.position = newValue }
    }

    open var transform: CGAffineTransform {
        get { layer.affineTransform() }
        set { layer.setAffineTransform(newValue) }
    }

    open var transform3D: CATransform3D {
        get { layer.transform }
        set { layer.transform = newValue }
    }

    /// Autoresizing to the subviews, then a layout pass.
    private func sizeDidChange(from old: CGSize) {
        if autoresizesSubviews {
            for subview in subviews where !subview.autoresizingMask.isEmpty && subview.translatesAutoresizingMaskIntoConstraints {
                subview.applyAutoresizing(from: old, to: bounds.size)
            }
        }
        setNeedsLayout()
    }

    // MARK: Appearance

    open var backgroundColor: UIColor? {
        didSet { layer.backgroundColor = backgroundColor.map { $0.rgba(for: traitCollection.userInterfaceStyle).cgColor } }
    }
    open var alpha: CGFloat {
        get { CGFloat(layer.opacity) }
        set { layer.opacity = Float(newValue) }
    }
    open var isHidden: Bool {
        get { layer.isHidden }
        set { layer.isHidden = newValue; superview?.hiddenChildDidChange() }
    }
    open var isOpaque = true
    open var clipsToBounds: Bool {
        get { layer.masksToBounds }
        set { layer.masksToBounds = newValue }
    }
    open var clearsContextBeforeDrawing = true
    open var contentMode: ContentMode = .scaleToFill { didSet { setNeedsDisplay() } }
    /// The tint: this view's, else the nearest ancestor's, else the system blue.
    open var tintColor: UIColor! {
        get { _tintColor ?? superview?.tintColor ?? .tintColor }
        set { _tintColor = newValue; tintColorDidChange() }
    }
    private var _tintColor: UIColor?
    open func tintColorDidChange() {
        setNeedsDisplay()
        for subview in subviews where subview._tintColor == nil { subview.tintColorDidChange() }
    }
    open var tintAdjustmentMode: TintAdjustmentMode = .automatic
    open var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified { didSet { setNeedsDisplay() } }
    open var tag = 0
    open var accessibilityIdentifier: String?
    open var semanticContentAttribute: UISemanticContentAttribute = .unspecified
    open var preservesSuperviewLayoutMargins = false
    open var insetsLayoutMarginsFromSafeArea = true
    open var layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8) { didSet { hasExplicitLayoutMargins = true; setNeedsLayout() } }
    /// Whether the app set `layoutMargins` (a controller's root view otherwise takes the system
    /// minimum margins: 16 sideways, the safe area vertically; Layout/NSLayoutConstraint.swift).
    var hasExplicitLayoutMargins = false
    open var directionalLayoutMargins: NSDirectionalEdgeInsets {
        get { NSDirectionalEdgeInsets(top: layoutMargins.top, leading: layoutMargins.left, bottom: layoutMargins.bottom, trailing: layoutMargins.right) }
        set { layoutMargins = UIEdgeInsets(top: newValue.top, left: newValue.leading, bottom: newValue.bottom, right: newValue.trailing) }
    }
    /// The safe area: the window's insets shrink through the tree (a browser page has none),
    /// plus what a container controller's bars cover of this view (`containerSafeAreaInsets`).
    open var safeAreaInsets: UIEdgeInsets {
        guard let superview else { return containerSafeAreaInsets }
        let outer = superview.safeAreaInsets
        let f = frame
        let s = superview.bounds
        let own = containerSafeAreaInsets
        return UIEdgeInsets(top: max(own.top, outer.top - f.minY), left: max(own.left, outer.left - f.minX),
                            bottom: max(own.bottom, outer.bottom - (s.maxY - f.maxY)), right: max(own.right, outer.right - (s.maxX - f.maxX)))
    }
    /// The insets a navigation or tab bar controller's bars cover of this (a child's) view.
    var containerSafeAreaInsets = UIEdgeInsets.zero { didSet { if containerSafeAreaInsets != oldValue { setNeedsLayout() } } }
    open func safeAreaInsetsDidChange() {}

    // MARK: Tree

    public private(set) var subviews: [UIView] = []
    public private(set) weak var superview: UIView?

    /// The window this view is in, if any.
    open var window: UIWindow? {
        var view: UIView? = self
        while let v = view {
            if let window = v as? UIWindow { return window }
            view = v.superview
        }
        return nil
    }

    /// The view controller whose view this is, for the responder chain.
    weak var owningViewController: UIViewController?

    override open var next: UIResponder? {
        owningViewController ?? superview
    }

    open func addSubview(_ view: UIView) {
        insertSubview(view, at: subviews.count)
    }

    open func insertSubview(_ view: UIView, at index: Int) {
        guard view !== self else { return }
        let oldWindow = view.window
        let newWindow = window
        if view.superview === self {
            subviews.removeAll { $0 === view }
        } else {
            view.willMove(toSuperview: self)
            view.removeFromSuperviewQuietly()
        }
        if oldWindow !== newWindow { view.willMoveTree(toWindow: newWindow) }
        let previousTraits = view.traitCollection
        let position = min(index, subviews.count)
        subviews.insert(view, at: position)
        view.superview = self
        // A view made under other traits (a cell built before it joins a dark window) resolves
        // its dynamic colours again for the traits it inherits here, as UIKit does on moving.
        if view.traitCollection.userInterfaceStyle != previousTraits.userInterfaceStyle { view.propagateTraitChange(from: previousTraits) }
        if view.layer.superlayer === layer {
            layer.move(view.layer, to: position)
        } else {
            layer.insertSublayer(view.layer, at: UInt32(position))
        }
        didAddSubview(view)
        view.didMoveToSuperview()
        if oldWindow !== newWindow { view.didMoveTree(toWindow: newWindow) }
        view.setNeedsLayout()
        setNeedsLayout()
    }

    open func insertSubview(_ view: UIView, aboveSubview sibling: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === sibling }) else { return addSubview(view) }
        insertSubview(view, at: index + 1)
    }

    open func insertSubview(_ view: UIView, belowSubview sibling: UIView) {
        guard let index = subviews.firstIndex(where: { $0 === sibling }) else { return addSubview(view) }
        insertSubview(view, at: index)
    }

    open func removeFromSuperview() {
        guard let superview else { return }
        let oldWindow = window
        superview.willRemoveSubview(self)
        willMove(toSuperview: nil)
        if oldWindow != nil { willMoveTree(toWindow: nil) }
        removeFromSuperviewQuietly()
        didMoveToSuperview()
        if oldWindow != nil { didMoveTree(toWindow: nil) }
        superview.setNeedsLayout()
    }

    private func removeFromSuperviewQuietly() {
        guard let superview else { return }
        superview.subviews.removeAll { $0 === self }
        layer.removeFromSuperlayer()
        self.superview = nil
    }

    open func bringSubviewToFront(_ view: UIView) {
        guard view.superview === self else { return }
        subviews.removeAll { $0 === view }
        subviews.append(view)
        layer.move(view.layer, to: subviews.count - 1)
    }

    open func sendSubviewToBack(_ view: UIView) {
        guard view.superview === self else { return }
        subviews.removeAll { $0 === view }
        subviews.insert(view, at: 0)
        layer.move(view.layer, to: 0)
    }

    open func exchangeSubview(at index1: Int, withSubviewAt index2: Int) {
        guard subviews.indices.contains(index1), subviews.indices.contains(index2) else { return }
        subviews.swapAt(index1, index2)
        layer.move(subviews[index1].layer, to: index1)
        layer.move(subviews[index2].layer, to: index2)
    }

    open func isDescendant(of view: UIView) -> Bool {
        var current: UIView? = self
        while let v = current {
            if v === view { return true }
            current = v.superview
        }
        return false
    }

    open func viewWithTag(_ tag: Int) -> UIView? {
        if self.tag == tag { return self }
        for subview in subviews {
            if let found = subview.viewWithTag(tag) { return found }
        }
        return nil
    }

    // Tree change hooks
    open func willMove(toSuperview newSuperview: UIView?) {}
    open func didMoveToSuperview() {}
    open func willMove(toWindow newWindow: UIWindow?) {}
    open func didMoveToWindow() {}
    open func didAddSubview(_ subview: UIView) {}
    open func willRemoveSubview(_ subview: UIView) {}
    func hiddenChildDidChange() { setNeedsLayout() }

    private func willMoveTree(toWindow window: UIWindow?) {
        willMove(toWindow: window)
        for subview in subviews { subview.willMoveTree(toWindow: window) }
    }

    private func didMoveTree(toWindow window: UIWindow?) {
        didMoveToWindow()
        if window == nil, isFirstResponder { resignFirstResponder() }
        for subview in subviews { subview.didMoveTree(toWindow: window) }
    }

    // MARK: Traits

    open var traitCollection: UITraitCollection {
        var traits = superview?.traitCollection ?? UIScreen.main.traitCollection
        if overrideUserInterfaceStyle != .unspecified { traits.userInterfaceStyle = overrideUserInterfaceStyle }
        return traits
    }

    open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // Dynamic colours re-resolve: the layer keeps a resolved value.
        if let backgroundColor { layer.backgroundColor = backgroundColor.rgba(for: traitCollection.userInterfaceStyle).cgColor }
    }

    /// The appearance this view paints in: the override, else the inherited one.
    func effectiveStyle(_ inherited: UIUserInterfaceStyle) -> UIUserInterfaceStyle {
        overrideUserInterfaceStyle == .unspecified ? inherited : overrideUserInterfaceStyle
    }

    /// Tells the subtree the traits changed.
    func propagateTraitChange(from previous: UITraitCollection?) {
        traitCollectionDidChange(previous)
        for subview in subviews { subview.propagateTraitChange(from: previous) }
    }

    // MARK: Layout

    open var autoresizingMask: AutoresizingMask = []
    open var autoresizesSubviews = true
    /// Off for a view placed by constraints (Layout/LayoutEngine.swift).
    open var translatesAutoresizingMaskIntoConstraints = true { didSet { superview?.setNeedsLayout() } }
    private(set) var needsLayout = true
    /// Constraints, guides and the update-constraints flag (Layout/NSLayoutConstraint.swift).
    let layoutState = ViewLayoutState()

    open func setNeedsLayout() {
        needsLayout = true
        UIKitScene.shared.setNeedsFrame()
    }

    /// Lays out the subtree now if anything in it needs it. Constraints are solved first for
    /// the whole tree from its root, as UIKit's window engine does, then `layoutSubviews` runs
    /// top-down.
    open func layoutIfNeeded() {
        if superview == nil {
            solveConstraintsIfNeeded()
        } else if needsLayout || subtreeNeedsLayout {
            var root: UIView = self
            while let parent = root.superview { root = parent }
            root.solveConstraintsIfNeeded()
        }
        layoutSubtreeIfNeeded()
    }

    private var subtreeNeedsLayout: Bool { needsLayout || subviews.contains { $0.subtreeNeedsLayout } }

    private func layoutSubtreeIfNeeded() {
        if needsLayout {
            needsLayout = false
            owningViewController?.viewWillLayoutSubviews()
            layoutSubviews()
            owningViewController?.viewDidLayoutSubviews()
        }
        for subview in subviews { subview.layoutSubtreeIfNeeded() }
    }

    /// Positions the subviews. The default does nothing (autoresizing already ran; the
    /// constraint engine placed the constrained subviews before this).
    open func layoutSubviews() {}

    /// Updates the constraints for the view. Override to add or change constraints; call super
    /// last (Layout/NSLayoutConstraint.swift).
    open func updateConstraints() {}

    open func setNeedsDisplay() { layer.setNeedsDisplay() }
    open func setNeedsDisplay(_ rect: CGRect) { setNeedsDisplay() }

    /// The size that fits the view's content within `size`. The default returns the current size.
    open func sizeThatFits(_ size: CGSize) -> CGSize { bounds.size }

    open func sizeToFit() {
        let size = sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        frame = CGRect(origin: frame.origin, size: size)
    }

    /// The natural size of the view's content, `noIntrinsicMetric` on an axis without one.
    open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }

    /// The insets from the view's frame to the rectangle layout aligns (Auto Layout and SwiftUI's
    /// representables position and size this rectangle, not the frame). Zero by default.
    open var alignmentRectInsets: UIEdgeInsets { .zero }

    open func alignmentRect(forFrame frame: CGRect) -> CGRect {
        let insets = alignmentRectInsets
        return CGRect(x: frame.minX + insets.left, y: frame.minY + insets.top,
                      width: frame.width - insets.left - insets.right, height: frame.height - insets.top - insets.bottom)
    }

    open func frame(forAlignmentRect alignmentRect: CGRect) -> CGRect {
        let insets = alignmentRectInsets
        return CGRect(x: alignmentRect.minX - insets.left, y: alignmentRect.minY - insets.top,
                      width: alignmentRect.width + insets.left + insets.right, height: alignmentRect.height + insets.top + insets.bottom)
    }
    open func invalidateIntrinsicContentSize() { superview?.setNeedsLayout() }

    private var hugging: [NSLayoutConstraint.Axis: UILayoutPriority] = [:]
    private var compression: [NSLayoutConstraint.Axis: UILayoutPriority] = [:]
    open func contentHuggingPriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { hugging[axis] ?? .defaultLow }
    open func setContentHuggingPriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { hugging[axis] = priority; superview?.setNeedsLayout() }
    open func contentCompressionResistancePriority(for axis: NSLayoutConstraint.Axis) -> UILayoutPriority { compression[axis] ?? .defaultHigh }
    open func setContentCompressionResistancePriority(_ priority: UILayoutPriority, for axis: NSLayoutConstraint.Axis) { compression[axis] = priority; superview?.setNeedsLayout() }

    /// The smallest size that satisfies the view's constraints: a solve of the subtree with the
    /// target proposed at the fitting priorities; without constraints, the intrinsic size where
    /// it has one, else what fits the target.
    open func systemLayoutSizeFitting(_ targetSize: CGSize) -> CGSize {
        systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: .fittingSizeLevel, verticalFittingPriority: .fittingSizeLevel)
    }

    open func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority, verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        if let constrained = constrainedSizeFitting(targetSize, horizontal: horizontal, vertical: vertical) { return constrained }
        let intrinsic = intrinsicContentSize
        let fitted = sizeThatFits(targetSize)
        let width = horizontal == .required ? targetSize.width : (intrinsic.width >= 0 ? intrinsic.width : fitted.width)
        let height = vertical == .required ? targetSize.height : (intrinsic.height >= 0 ? intrinsic.height : fitted.height)
        return CGSize(width: width, height: height)
    }

    /// Resizes for a superview that grew from `old` to `new` (the flexible parts share the delta
    /// in proportion to their sizes).
    func applyAutoresizing(from old: CGSize, to new: CGSize) {
        var f = frame
        let mask = autoresizingMask
        func resize(_ origin: inout CGFloat, _ length: inout CGFloat, oldTotal: CGFloat, newTotal: CGFloat,
                    flexibleLeading: Bool, flexibleSize: Bool, flexibleTrailing: Bool) {
            let leading = origin, trailing = oldTotal - origin - length
            let flexible = (flexibleLeading ? leading : 0) + (flexibleSize ? length : 0) + (flexibleTrailing ? trailing : 0)
            let delta = newTotal - oldTotal
            guard delta != 0 else { return }
            if flexible <= 0 {
                // Nothing flexible with a size: flexible parts share equally.
                let count = CGFloat([flexibleLeading, flexibleSize, flexibleTrailing].filter { $0 }.count)
                guard count > 0 else { return }
                if flexibleLeading { origin += delta / count }
                if flexibleSize { length += delta / count }
                return
            }
            if flexibleLeading { origin += delta * leading / flexible }
            if flexibleSize { length += delta * length / flexible }
        }
        resize(&f.origin.x, &f.size.width, oldTotal: old.width, newTotal: new.width,
               flexibleLeading: mask.contains(.flexibleLeftMargin), flexibleSize: mask.contains(.flexibleWidth), flexibleTrailing: mask.contains(.flexibleRightMargin))
        resize(&f.origin.y, &f.size.height, oldTotal: old.height, newTotal: new.height,
               flexibleLeading: mask.contains(.flexibleTopMargin), flexibleSize: mask.contains(.flexibleHeight), flexibleTrailing: mask.contains(.flexibleBottomMargin))
        frame = f
    }

    /// The first and last text baselines of this view's content laid out in `size`, from the
    /// top: a plain view's are its top and bottom edges, as its baseline anchors are (labels
    /// override this with their lines').
    func textBaselines(in size: CGSize) -> (first: CGFloat, last: CGFloat) { (0, size.height) }

    // MARK: Drawing

    /// Draws the view's content with the current graphics context (`UIGraphicsGetCurrentContext()`,
    /// `UIBezierPath`, `UIColor.setFill`); the default draws nothing (Drawing/GraphicsContext.swift).
    open func draw(_ rect: CGRect) {}

    /// Paints the view's own content (labels, images) at the layer's coordinates; the built-in
    /// views override this in place of `draw(_:)`. The default runs `draw(_:)`.
    func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        drawCustomContent(into: &list, context: context)
        _hostedPaint(into: &list, context: context)
    }

    // MARK: Coordinate conversion

    open func convert(_ point: CGPoint, to view: UIView?) -> CGPoint { layer.convert(point, to: view?.layer) }
    open func convert(_ point: CGPoint, from view: UIView?) -> CGPoint { layer.convert(point, from: view?.layer) }
    open func convert(_ rect: CGRect, to view: UIView?) -> CGRect { layer.convert(rect, to: view?.layer) }
    open func convert(_ rect: CGRect, from view: UIView?) -> CGRect { layer.convert(rect, from: view?.layer) }

    // MARK: Hit testing and input

    open var isUserInteractionEnabled = true
    open var isMultipleTouchEnabled = false
    open var isExclusiveTouch = false

    /// Whether points outside the bounds cannot hit descendants (scroll views clip).
    var clipsHitTesting: Bool { false }

    /// The deepest descendant that should receive a touch at `point` (in this view's coordinates).
    open func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01 else { return nil }
        let inside = self.point(inside: point, with: event)
        guard inside || !clipsToBounds else { return nil }
        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local, with: event) { return hit }
        }
        return inside ? self : nil
    }

    open func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.contains(point)
    }

    public private(set) var gestureRecognizers: [UIGestureRecognizer]?

    open func addGestureRecognizer(_ recognizer: UIGestureRecognizer) {
        recognizer.view?.removeGestureRecognizer(recognizer)
        gestureRecognizers = (gestureRecognizers ?? []) + [recognizer]
        recognizer.view = self
    }

    open func removeGestureRecognizer(_ recognizer: UIGestureRecognizer) {
        gestureRecognizers?.removeAll { $0 === recognizer }
        if gestureRecognizers?.isEmpty == true { gestureRecognizers = nil }
        recognizer.view = nil
    }

    open func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool { true }

    // MARK: Accessibility

    open var isAccessibilityElement = false
    open var accessibilityLabel: String?
    open var accessibilityValue: String?
    open var accessibilityHint: String?
    open var accessibilityTraits: UIAccessibilityTraits = .none
    open var accessibilityElementsHidden = false
    /// The identifier the scene reports this view under in its semantics tree.
    lazy var semanticsIdentifier: Int = UIKitScene.nextSemanticsIdentifier()

    /// Subclasses add their state to the semantics node (a switch's `isOn`, a text field's
    /// input, a slider's range).
    func decorateSemantics(_ node: inout SemanticsNode) {}

    /// Assistive technology activated this element (a button press).
    func accessibilityActivate() {
        (self as? UIControl)?.sendActions(for: [.touchUpInside, .primaryActionTriggered])
    }

    func accessibilityIncrement() {}
    func accessibilityDecrement() {}
    func accessibilitySetValue(_ value: Double) {}


    // MARK: Hosting SPI (App/HostingViewSPI.swift)

    /// Paints a hosted scene at the view's origin (SwiftUIWeb's `UIHostingController`); the
    /// default paints nothing. `drawContent` calls this after `draw(_:)`.
    open func _hostedPaint(into list: inout DisplayList, context: PaintContext) {}
    /// The hosted scene's accessibility elements, frames in the view's coordinates, or nil for a
    /// view that hosts nothing (its subviews are walked instead).
    open func _hostedSemantics() -> [SemanticsNode]? { nil }
    /// Whether the hosted scene owns the element with this identifier.
    open func _hostedHandles(semanticsIdentifier: Int) -> Bool { false }
    open func _hostedActivate(semanticsIdentifier: Int) {}
    open func _hostedAdjust(semanticsIdentifier: Int, increment: Bool) {}
    open func _hostedSetValue(semanticsIdentifier: Int, value: Double) {}
    open func _hostedFocus(semanticsIdentifier: Int?, keyboard: Bool) {}
    open func _hostedBlur(semanticsIdentifier: Int) {}
    open func _hostedTextField(_ semanticsIdentifier: Int, didChange text: String) {}
    open func _hostedTextFieldDidSubmit(_ semanticsIdentifier: Int) {}
    open func _hostedTextField(_ semanticsIdentifier: Int, focused: Bool) {}
    /// The hosted scene's text field with keyboard focus.
    open var _hostedFocusedTextFieldIdentifier: Int? { nil }
    /// Advances the hosted scene's clocks; true while it needs another frame.
    open func _hostedAdvanceFrame(elapsed: Double) -> Bool { false }
    /// A wheel scroll at `point` (the view's coordinates); true when the hosted scene took it.
    open func _hostedScrollWheel(by delta: CGSize, at point: CGPoint) -> Bool { false }

    // MARK: Nested types

    public struct AutoresizingMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let flexibleLeftMargin = AutoresizingMask(rawValue: 1)
        public static let flexibleWidth = AutoresizingMask(rawValue: 2)
        public static let flexibleRightMargin = AutoresizingMask(rawValue: 4)
        public static let flexibleTopMargin = AutoresizingMask(rawValue: 8)
        public static let flexibleHeight = AutoresizingMask(rawValue: 16)
        public static let flexibleBottomMargin = AutoresizingMask(rawValue: 32)
    }

    public enum ContentMode: Int, Sendable {
        case scaleToFill = 0, scaleAspectFit, scaleAspectFill, redraw, center, top, bottom, left, right
        case topLeft, topRight, bottomLeft, bottomRight
    }

    public enum TintAdjustmentMode: Int, Sendable {
        case automatic = 0, normal, dimmed
    }

    public struct AnimationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let layoutSubviews = AnimationOptions(rawValue: 1 << 0)
        public static let allowUserInteraction = AnimationOptions(rawValue: 1 << 1)
        public static let beginFromCurrentState = AnimationOptions(rawValue: 1 << 2)
        public static let `repeat` = AnimationOptions(rawValue: 1 << 3)
        public static let autoreverse = AnimationOptions(rawValue: 1 << 4)
        public static let curveEaseInOut = AnimationOptions(rawValue: 0 << 16)
        public static let curveEaseIn = AnimationOptions(rawValue: 1 << 16)
        public static let curveEaseOut = AnimationOptions(rawValue: 2 << 16)
        public static let curveLinear = AnimationOptions(rawValue: 3 << 16)
        public static let transitionCrossDissolve = AnimationOptions(rawValue: 5 << 20)
    }

    // MARK: Animation (Layers/LayerAnimation.swift)

    /// Whether animation blocks animate (`setAnimationsEnabled`).
    public private(set) static var areAnimationsEnabled = true
    public class func setAnimationsEnabled(_ enabled: Bool) { areAnimationsEnabled = enabled }

    /// Runs `animations` recording the layer changes it makes as an animation of `duration`
    /// seconds after `delay`, with the curve `options` name (ease in-out by default); the model
    /// takes the new values at once and painting interpolates. `completion` runs when the
    /// animation ends (at once when nothing animated).
    open class func animate(withDuration duration: Double, delay: Double = 0, options: AnimationOptions = [], animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        run(duration: duration, delay: delay, curve: options.curve, animations: animations, completion: completion)
    }

    open class func animate(withDuration duration: Double, animations: @escaping () -> Void) {
        run(duration: duration, delay: 0, curve: .easeInOut, animations: animations, completion: nil)
    }

    open class func animate(withDuration duration: Double, delay: Double, usingSpringWithDamping damping: CGFloat, initialSpringVelocity velocity: CGFloat,
                            options: AnimationOptions = [], animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        run(duration: duration, delay: delay, curve: .spring(damping: Double(damping), velocity: Double(velocity)), animations: animations, completion: completion)
    }

    /// A transition (cross dissolve, flips): the changes apply at once; `completion` runs when
    /// the duration has passed.
    open class func transition(with view: UIView, duration: Double, options: AnimationOptions = [], animations: (() -> Void)?, completion: ((Bool) -> Void)? = nil) {
        animations?()
        if let completion {
            if duration > 0 { UIKitScene.shared.schedule(after: duration) { completion(true) } } else { completion(true) }
        }
    }

    /// Runs `actions` with animation recording off, inside an animation block or not.
    open class func performWithoutAnimation(_ actions: () -> Void) {
        let previous = UIViewAnimationContext.disabled
        UIViewAnimationContext.disabled = true
        actions()
        UIViewAnimationContext.disabled = previous
    }

    private class func run(duration: Double, delay: Double, curve: UIKitWebCore.AnimationCurve, animations: () -> Void, completion: ((Bool) -> Void)?) {
        guard areAnimationsEnabled, !UIViewAnimationContext.disabled, duration + delay > 0 else {
            animations()
            completion?(true)
            return
        }
        let group = UIViewAnimationGroup(duration: duration, delay: delay, curve: curve)
        group.completion = completion
        let outer = UIViewAnimationContext.current
        UIViewAnimationContext.current = group
        animations()
        UIViewAnimationContext.current = outer
        if group.entries.isEmpty {
            // Nothing animated: the completion still waits the duration out, as UIKit's does.
            UIKitScene.shared.schedule(after: duration + delay) { completion?(true) }
            return
        }
        UIKitScene.shared.add(group)
    }
}

extension UIView {
    /// The named timing curves (`UIViewPropertyAnimator(duration:curve:)`).
    public enum AnimationCurve: Int, Sendable { case easeInOut = 0, easeIn, easeOut, linear }
}

extension UIView.AnimationOptions {
    /// The timing curve the options name.
    var curve: UIKitWebCore.AnimationCurve {
        let bits = rawValue & (3 << 16)
        switch bits {
        case UIView.AnimationOptions.curveEaseIn.rawValue: return .easeIn
        case UIView.AnimationOptions.curveEaseOut.rawValue: return .easeOut
        case UIView.AnimationOptions.curveLinear.rawValue: return .linear
        default: return .easeInOut
        }
    }
}

/// The reading direction a view lays out for.
public enum UISemanticContentAttribute: Int, Sendable {
    case unspecified = 0, playback, spatial, forceLeftToRight, forceRightToLeft
}

/// Accessibility traits a view reports.
public struct UIAccessibilityTraits: OptionSet, Sendable {
    public let rawValue: UInt64
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    public static let none = UIAccessibilityTraits([])
    public static let button = UIAccessibilityTraits(rawValue: 1 << 0)
    public static let link = UIAccessibilityTraits(rawValue: 1 << 1)
    public static let image = UIAccessibilityTraits(rawValue: 1 << 2)
    public static let selected = UIAccessibilityTraits(rawValue: 1 << 3)
    public static let playsSound = UIAccessibilityTraits(rawValue: 1 << 4)
    public static let keyboardKey = UIAccessibilityTraits(rawValue: 1 << 5)
    public static let staticText = UIAccessibilityTraits(rawValue: 1 << 6)
    public static let summaryElement = UIAccessibilityTraits(rawValue: 1 << 7)
    public static let notEnabled = UIAccessibilityTraits(rawValue: 1 << 8)
    public static let updatesFrequently = UIAccessibilityTraits(rawValue: 1 << 9)
    public static let searchField = UIAccessibilityTraits(rawValue: 1 << 10)
    public static let startsMediaSession = UIAccessibilityTraits(rawValue: 1 << 11)
    public static let adjustable = UIAccessibilityTraits(rawValue: 1 << 12)
    public static let allowsDirectInteraction = UIAccessibilityTraits(rawValue: 1 << 13)
    public static let causesPageTurn = UIAccessibilityTraits(rawValue: 1 << 14)
    public static let header = UIAccessibilityTraits(rawValue: 1 << 16)
    public static let tabBar = UIAccessibilityTraits(rawValue: 1 << 17)
    public static let toggleButton = UIAccessibilityTraits(rawValue: 1 << 20)
}
