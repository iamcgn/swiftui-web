// UIStackView (Docs/elements/UIKit/UIStackView.md): arranged subviews along an axis. UIKit's
// stack view is Auto Layout underneath; this one computes the same frames directly from the
// arranged views' intrinsic sizes, hugging and compression priorities.

/// A streamlined interface for laying out a collection of views in either a column or a row.
@MainActor
open class UIStackView: UIView {
    public enum Distribution: Int, Sendable { case fill = 0, fillEqually, fillProportionally, equalSpacing, equalCentering }
    public enum Alignment: Int, Sendable {
        case fill = 0, leading = 1, firstBaseline = 2, center = 3, trailing = 4, lastBaseline = 5
        public static let top = Alignment.leading
        public static let bottom = Alignment.trailing
    }

    public static let spacingUseDefault: CGFloat = .greatestFiniteMagnitude
    public static let spacingUseSystem: CGFloat = -.greatestFiniteMagnitude

    open var axis: NSLayoutConstraint.Axis = .horizontal { didSet { invalidateIntrinsicContentSize(); setNeedsLayout() } }
    open var distribution: Distribution = .fill { didSet { setNeedsLayout() } }
    open var alignment: Alignment = .fill { didSet { setNeedsLayout() } }
    open var spacing: CGFloat = 0 { didSet { invalidateIntrinsicContentSize(); setNeedsLayout() } }
    open var isBaselineRelativeArrangement = false
    open var isLayoutMarginsRelativeArrangement = false { didSet { invalidateIntrinsicContentSize(); setNeedsLayout() } }
    public private(set) var arrangedSubviews: [UIView] = []
    private var customSpacing: [ObjectIdentifier: CGFloat] = [:]

    public init(arrangedSubviews views: [UIView]) {
        super.init(frame: .zero)
        for view in views { addArrangedSubview(view) }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
    }

    public convenience init() { self.init(frame: .zero) }

    open func addArrangedSubview(_ view: UIView) {
        insertArrangedSubview(view, at: arrangedSubviews.count)
    }

    open func insertArrangedSubview(_ view: UIView, at index: Int) {
        arrangedSubviews.removeAll { $0 === view }
        arrangedSubviews.insert(view, at: min(index, arrangedSubviews.count))
        if view.superview !== self { addSubview(view) }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    open func removeArrangedSubview(_ view: UIView) {
        arrangedSubviews.removeAll { $0 === view }
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    override open func willRemoveSubview(_ subview: UIView) {
        removeArrangedSubview(subview)
    }

    open func setCustomSpacing(_ spacing: CGFloat, after arrangedSubview: UIView) {
        customSpacing[ObjectIdentifier(arrangedSubview)] = spacing
        setNeedsLayout()
    }

    open func customSpacing(after arrangedSubview: UIView) -> CGFloat {
        customSpacing[ObjectIdentifier(arrangedSubview)] ?? spacing
    }

    override func hiddenChildDidChange() {
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    // MARK: Measuring

    private var visible: [UIView] { arrangedSubviews.filter { !$0.isHidden } }
    private var horizontal: Bool { axis == .horizontal }
    private var margins: UIEdgeInsets { isLayoutMarginsRelativeArrangement ? layoutMargins : .zero }

    /// A view's natural size along and across the axis.
    private func natural(_ view: UIView, across: CGFloat?) -> CGSize {
        // A view with constraints of its own (a fixed width and height) is as big as they say
        // (uikit/autolayout/stacks: a 40 pt box in a centred row).
        if !view.translatesAutoresizingMaskIntoConstraints, LayoutEngine.hasConstraints(view),
           let constrained = view.constrainedSizeFitting(UIView.layoutFittingCompressedSize, horizontal: .fittingSizeLevel, vertical: .fittingSizeLevel), constrained.width > 0 || constrained.height > 0 {
            let intrinsic = view._layoutIntrinsicSize
            return CGSize(width: constrained.width > 0 ? constrained.width : max(0, intrinsic.width), height: constrained.height > 0 ? constrained.height : max(0, intrinsic.height))
        }
        let intrinsic = view._layoutIntrinsicSize
        let fitting = CGSize(width: horizontal ? CGFloat.greatestFiniteMagnitude : (across ?? CGFloat.greatestFiniteMagnitude),
                             height: horizontal ? (across ?? CGFloat.greatestFiniteMagnitude) : CGFloat.greatestFiniteMagnitude)
        let fitted = view.sizeThatFits(fitting)
        return CGSize(width: intrinsic.width >= 0 ? intrinsic.width : fitted.width, height: intrinsic.height >= 0 ? intrinsic.height : fitted.height)
    }

    private func along(_ size: CGSize) -> CGFloat { horizontal ? size.width : size.height }
    private func across(_ size: CGSize) -> CGFloat { horizontal ? size.height : size.width }

    private func totalSpacing(_ views: [UIView]) -> CGFloat {
        views.dropLast().reduce(0) { $0 + customSpacing(after: $1) }
    }

    /// Baseline alignments (horizontal stacks): each view's first or last baseline from its top,
    /// and the height the aligned views need (the deepest ascent plus the deepest descent).
    private var alignsBaselines: Bool { horizontal && (alignment == .firstBaseline || alignment == .lastBaseline) }

    private func baseline(of view: UIView, size: CGSize) -> CGFloat {
        let baselines = view.textBaselines(in: size)
        return alignment == .firstBaseline ? baselines.first : baselines.last
    }

    private func baselineExtent(_ views: [UIView], sizes: [CGSize]) -> (ascent: CGFloat, descent: CGFloat) {
        var ascent: CGFloat = 0, descent: CGFloat = 0
        for (view, size) in zip(views, sizes) {
            let line = baseline(of: view, size: size)
            ascent = max(ascent, line)
            descent = max(descent, size.height - line)
        }
        return (ascent, descent)
    }

    /// A stack reports no intrinsic content size, as UIKit's does (uikit/autolayout/hugging);
    /// its content's size, `_contentSize`, is what Auto Layout, a stack around it and
    /// `systemLayoutSizeFitting` size it by (UIKit's stack holds that in its own constraints).
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }

    override var _layoutIntrinsicSize: CGSize { _contentSize }

    public var _contentSize: CGSize {
        let views = visible
        guard !views.isEmpty else { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        let sizes = views.map { natural($0, across: nil) }
        let mainTotal: CGFloat
        switch distribution {
        case .fillEqually: mainTotal = (sizes.map(along).max() ?? 0) * CGFloat(views.count) + totalSpacing(views)
        default: mainTotal = sizes.map(along).reduce(0, +) + totalSpacing(views)
        }
        var crossMax = sizes.map(across).max() ?? 0
        if alignsBaselines {
            let extent = baselineExtent(views, sizes: sizes)
            crossMax = extent.ascent + extent.descent
        }
        let m = margins
        let width = (horizontal ? mainTotal : crossMax) + m.left + m.right
        let height = (horizontal ? crossMax : mainTotal) + m.top + m.bottom
        return CGSize(width: width, height: height)
    }

    /// A stack's fitting size is its arranged content's (ios/representable/hostingsizing: a
    /// representable sized by `systemLayoutSizeFitting` of a stack holding a hosting view and a
    /// constrained view is 70 tall); a required target keeps its length.
    override open func systemLayoutSizeFitting(_ targetSize: CGSize, withHorizontalFittingPriority horizontal: UILayoutPriority, verticalFittingPriority vertical: UILayoutPriority) -> CGSize {
        let intrinsic = _contentSize
        if intrinsic.width < 0 { return super.systemLayoutSizeFitting(targetSize, withHorizontalFittingPriority: horizontal, verticalFittingPriority: vertical) }
        return CGSize(width: horizontal == .required ? targetSize.width : intrinsic.width,
                      height: vertical == .required ? targetSize.height : intrinsic.height)
    }

    // MARK: Layout

    override open func layoutSubviews() {
        super.layoutSubviews()
        let views = visible
        guard !views.isEmpty else { return }
        let content = bounds.inset(by: margins)
        let available = along(content.size)
        let crossAvailable = across(content.size)
        let spacingTotal = totalSpacing(views)
        var mains: [CGFloat]
        var gaps = views.dropLast().map { customSpacing(after: $0) } + [0]
        let naturals = views.map { natural($0, across: alignment == .fill ? crossAvailable : nil) }
        switch distribution {
        case .fillEqually:
            let each = max(0, (available - spacingTotal) / CGFloat(views.count))
            mains = Array(repeating: each, count: views.count)
        case .fillProportionally:
            // UIKit's proportional constraints share the stack's whole length (spacing included)
            // by the views' natural sizes against their sum plus the spacing, each rounded to
            // the pixel; the last visible view, whose constraint has the lowest priority, takes
            // what is left (uikit/stack/distribution: 11.5, 61.5 and 123 in 288 with 8 between
            // give 15.5, 83.5 and 173).
            let sum = naturals.map(along).reduce(0, +) + spacingTotal
            mains = naturals.map { sum > 0 ? roundToPixel(along($0) * available / sum) : available / CGFloat(views.count) }
            if let last = mains.indices.last { mains[last] = max(0, available - spacingTotal - mains.dropLast().reduce(0, +)) }
        case .fill:
            mains = naturals.map(along)
            let extra = available - spacingTotal - mains.reduce(0, +)
            if extra > 0 {
                // The view with the lowest hugging priority stretches (the first among equals).
                let priorities = views.map { $0.contentHuggingPriority(for: axis) }
                if let index = priorities.indices.min(by: { priorities[$0] < priorities[$1] }) { mains[index] += extra }
            } else if extra < 0 {
                compress(&mains, by: -extra, views: views)
            }
        case .equalSpacing, .equalCentering:
            mains = naturals.map(along)
            let free = available - mains.reduce(0, +)
            let gap = views.count > 1 ? max(spacing, free / CGFloat(views.count - 1)) : 0
            gaps = Array(repeating: gap, count: views.count)
            // Too little room keeps the spacing and shrinks the least resistant view.
            let overflow = mains.reduce(0, +) + gap * CGFloat(max(0, views.count - 1)) - available
            if overflow > 0 { compress(&mains, by: overflow, views: views) }
        }
        var cursor = horizontal ? content.minX : content.minY
        let extent = alignsBaselines ? baselineExtent(views, sizes: naturals) : (ascent: 0, descent: 0)
        for (index, view) in views.enumerated() {
            let main = mains[index]
            let naturalCross = across(naturals[index])
            let cross: CGFloat
            let offset: CGFloat
            switch alignment {
            case .fill: cross = crossAvailable; offset = 0
            case .leading: cross = min(naturalCross, crossAvailable); offset = 0
            case .trailing: cross = min(naturalCross, crossAvailable); offset = crossAvailable - cross
            case .firstBaseline where horizontal, .lastBaseline where horizontal:
                // The baselines meet: each view sits so its baseline is at the deepest ascent
                // (first) or the row's bottom less the deepest descent (last).
                cross = naturalCross
                let line = baseline(of: view, size: naturals[index])
                offset = alignment == .firstBaseline ? extent.ascent - line : (crossAvailable - extent.descent) - line
            default: cross = min(naturalCross, crossAvailable); offset = (crossAvailable - cross) / 2
            }
            // Auto Layout rounds the placement to the pixel grid in the stack's own coordinates
            // (a 30.75 centring offset becomes 31; Docs/elements/UIKit/UIStackView.md).
            let scale = UIScreen.main.scale
            let crossOrigin = (horizontal ? content.minY : content.minX) + (offset * scale).rounded() / scale
            view.frame = horizontal
                ? CGRect(x: cursor, y: crossOrigin, width: main, height: cross)
                : CGRect(x: crossOrigin, y: cursor, width: cross, height: main)
            cursor += main + gaps[index]
        }
        placeHidden(in: content)
    }

    /// Shrinks the view with the lowest compression resistance (the first among equals) by
    /// `amount`, as UIKit's stack does when its content overflows.
    private func compress(_ mains: inout [CGFloat], by amount: CGFloat, views: [UIView]) {
        let priorities = views.map { $0.contentCompressionResistancePriority(for: axis) }
        if let index = priorities.indices.min(by: { priorities[$0] < priorities[$1] }) { mains[index] = max(0, mains[index] - amount) }
    }

    /// A hidden arranged view takes no room; UIKit leaves it zero-length at the midpoint of the
    /// gap between its visible neighbours (the content's end after the last one), full across.
    private func placeHidden(in content: CGRect) {
        let views = arrangedSubviews
        for (index, view) in views.enumerated() where view.isHidden {
            let before = views[..<index].last { !$0.isHidden }
            let after = views[(index + 1)...].first { !$0.isHidden }
            let start = before.map { horizontal ? $0.frame.maxX : $0.frame.maxY } ?? (horizontal ? content.minX : content.minY)
            let end = after.map { horizontal ? $0.frame.minX : $0.frame.minY } ?? (horizontal ? content.maxX : content.maxY)
            let position = (start + end) / 2
            view.frame = horizontal
                ? CGRect(x: position, y: content.minY, width: 0, height: content.height)
                : CGRect(x: content.minX, y: position, width: content.width, height: 0)
        }
    }

    private func roundToPixel(_ value: CGFloat) -> CGFloat {
        let scale = UIScreen.main.scale
        return (value * scale).rounded() / scale
    }
}
