// The remaining controls (Docs/elements/UIKit/Controls.md): UISlider, UISegmentedControl,
// UIStepper, UIProgressView, UIActivityIndicatorView, UIPageControl. Geometry from UIKit on the
// iPhone SE simulator (iOS 26, `uikit/controls/more`); the looks are the iOS 26 glass controls
// drawn flat.

/// A control for selecting a single value from a continuous range of values.
@MainActor
open class UISlider: UIControl {
    open var value: Float = 0 { didSet { value = min(max(value, minimumValue), maximumValue); setNeedsDisplay() } }
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
    open var isContinuous = true
    open var minimumTrackTintColor: UIColor?
    open var maximumTrackTintColor: UIColor?
    open var thumbTintColor: UIColor?
    open var minimumValueImage: UIImage?
    open var maximumValueImage: UIImage?

    static let height: CGFloat = 34
    static let knobSize = CGSize(width: 38, height: 25)
    static let trackHeight: CGFloat = 6

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: Self.height)))
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    open func setValue(_ value: Float, animated: Bool) { self.value = value }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width > 0 && size.width < .greatestFiniteMagnitude ? size.width : bounds.width, height: Self.height) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    /// The value as a fraction of the range.
    var fraction: CGFloat {
        let range = maximumValue - minimumValue
        return range > 0 ? CGFloat((value - minimumValue) / range) : 0
    }

    /// The knob's frame: a 38 × 25 lens 4 down, travelling over the width less its own.
    open func thumbRect(forBounds bounds: CGRect, trackRect: CGRect, value: Float) -> CGRect {
        let x = ((bounds.width - Self.knobSize.width) * fraction).rounded()
        return CGRect(x: bounds.minX + x, y: bounds.minY + 4, width: Self.knobSize.width, height: Self.knobSize.height)
    }

    open func trackRect(forBounds bounds: CGRect) -> CGRect { CGRect(x: bounds.minX, y: bounds.minY + 14, width: bounds.width, height: Self.trackHeight) }

    private func setValue(atX x: CGFloat) {
        let travel = bounds.width - Self.knobSize.width
        let fraction = min(1, max(0, (x - Self.knobSize.width / 2) / max(1, travel)))
        let newValue = minimumValue + Float(fraction) * (maximumValue - minimumValue)
        if newValue != value {
            value = newValue
            if isContinuous { sendActions(for: .valueChanged) }
        }
    }

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if isEnabled, let touch = touches.first { setValue(atX: touch.location(in: self).x) }
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if isEnabled, let touch = touches.first { setValue(atX: touch.location(in: self).x) }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if isEnabled, !isContinuous { sendActions(for: .valueChanged) }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let dim = isEnabled ? 1.0 : 0.5
        let track = context.absoluteRect(trackRect(forBounds: bounds))
        // The empty track is black at 10 % (uikit/controls/more).
        let maximum = (maximumTrackTintColor ?? UIColor(light: RGBA(r: 0, g: 0, b: 0, a: 25.0 / 255), dark: RGBA(r: 255, g: 255, b: 255, a: 25.0 / 255))).rgba(for: style)
        list.append(.fillRRect(track, cornerRadius: track.height / 2, maximum.multiplyingAlpha(by: dim)))
        let filledWidth = (bounds.width * fraction)
        let filled = context.absoluteRect(CGRect(x: 0, y: 14, width: filledWidth, height: Self.trackHeight))
        list.append(.fillRRect(filled, cornerRadius: filled.height / 2, (minimumTrackTintColor ?? tintColor).rgba(for: style).multiplyingAlpha(by: dim)))
        let knob = context.absoluteRect(thumbRect(forBounds: bounds, trackRect: track, value: value))
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.12 * dim), radius: 4, offset: CGSize(width: 0, height: 2)))
        list.append(.fillRRect(knob, cornerRadius: knob.height / 2, (thumbTintColor ?? .white).rgba(for: style)))
        list.append(.endGroup)
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .slider
        node.value = "\(Int((fraction * 100).rounded())) %"
        node.isAdjustable = true
    }

    override func accessibilityIncrement() { value += (maximumValue - minimumValue) / 10; sendActions(for: .valueChanged) }
    override func accessibilityDecrement() { value -= (maximumValue - minimumValue) / 10; sendActions(for: .valueChanged) }
    override func accessibilitySetValue(_ value: Double) { self.value = minimumValue + Float(value / 100) * (maximumValue - minimumValue); sendActions(for: .valueChanged) }
}

/// A horizontal control that consists of multiple segments, each segment functioning as a
/// discrete button.
@MainActor
open class UISegmentedControl: UIControl {
    public static let noSegment = -1

    private var titles: [String?] = []
    private var images: [UIImage?] = []
    open var selectedSegmentIndex: Int = UISegmentedControl.noSegment { didSet { setNeedsLayout(); setNeedsDisplay() } }
    open var isMomentary = false
    open var apportionsSegmentWidthsByContent = false
    open var selectedSegmentTintColor: UIColor?
    private var labels: [UILabel] = []

    static let height: CGFloat = 32
    static let padding: CGFloat = 10
    /// The titles' size and whether the selected one is medium: 13 with a medium selection for
    /// a control of its own, 15 regular throughout in a search bar's scope bar (uikit/search/scope).
    var titleSize: CGFloat = 13 { didSet { setNeedsLayout() } }
    var emphasisesSelection = true { didSet { setNeedsLayout() } }

    public init(items: [Any]?) {
        super.init(frame: .zero)
        isAccessibilityElement = false
        for item in items ?? [] {
            if let title = item as? String { titles.append(title); images.append(nil) }
            else if let image = item as? UIImage { titles.append(nil); images.append(image) }
        }
        rebuild()
        frame.size = sizeThatFits(.zero)
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
    }

    open var numberOfSegments: Int { titles.count }

    open func insertSegment(withTitle title: String?, at segment: Int, animated: Bool) {
        titles.insert(title, at: min(segment, titles.count))
        images.insert(nil, at: min(segment, images.count))
        rebuild()
    }

    open func insertSegment(with image: UIImage?, at segment: Int, animated: Bool) {
        titles.insert(nil, at: min(segment, titles.count))
        images.insert(image, at: min(segment, images.count))
        rebuild()
    }

    open func removeSegment(at segment: Int, animated: Bool) {
        guard titles.indices.contains(segment) else { return }
        titles.remove(at: segment)
        images.remove(at: segment)
        rebuild()
    }

    open func removeAllSegments() { titles = []; images = []; rebuild() }
    open func setTitle(_ title: String?, forSegmentAt segment: Int) { guard titles.indices.contains(segment) else { return }; titles[segment] = title; rebuild() }
    open func titleForSegment(at segment: Int) -> String? { titles.indices.contains(segment) ? titles[segment] : nil }
    open func setImage(_ image: UIImage?, forSegmentAt segment: Int) { guard images.indices.contains(segment) else { return }; images[segment] = image; rebuild() }
    open func setEnabled(_ enabled: Bool, forSegmentAt segment: Int) {}
    open func setWidth(_ width: CGFloat, forSegmentAt segment: Int) {}

    private func rebuild() {
        for label in labels { label.removeFromSuperview() }
        labels = titles.map { title in
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: titleSize)
            label.textAlignment = .center
            addSubview(label)
            return label
        }
        setNeedsLayout()
    }

    /// Every segment is as wide as the widest title plus 20 (uikit/controls/more: 55 for
    /// "Three" at 35.5); the control is 32 tall.
    var segmentWidth: CGFloat {
        let widest = labels.map { $0.intrinsicContentSize.width }.max() ?? 0
        return (widest + 2 * Self.padding).rounded(.down)
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize {
        CGSize(width: segmentWidth * CGFloat(max(1, titles.count)), height: Self.height)
    }

    override open var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width / CGFloat(max(1, titles.count))
        for (index, label) in labels.enumerated() {
            label.font = .systemFont(ofSize: titleSize, weight: emphasisesSelection && index == selectedSegmentIndex ? .medium : .regular)
            let textSize = label.intrinsicContentSize
            // The label is centred in the segment: 13 pt titles 16 tall at 8, 15 pt ones 18 tall at 7.
            label.frame = CGRect(x: (width * CGFloat(index) + (width - textSize.width) / 2).rounded(), y: ((Self.height - textSize.height) / 2).rounded(), width: textSize.width, height: textSize.height)
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        guard wasTracking, isEnabled, let touch = touches.first, !titles.isEmpty else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        let index = min(titles.count - 1, max(0, Int(location.x / (bounds.width / CGFloat(titles.count)))))
        if index != selectedSegmentIndex || isMomentary {
            selectedSegmentIndex = isMomentary ? UISegmentedControl.noSegment : index
            sendActions(for: .valueChanged)
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let ground: RGBA = style == .dark ? RGBA(r: 118, g: 118, b: 128, a: 0.24) : RGBA(r: 118, g: 118, b: 128, a: 0.12)
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, ground))
        if titles.indices.contains(selectedSegmentIndex) {
            let width = bounds.width / CGFloat(titles.count)
            let lens = context.absoluteRect(CGRect(x: width * CGFloat(selectedSegmentIndex) + 2, y: 2, width: width - 4, height: bounds.height - 4))
            list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.1), radius: 4, offset: CGSize(width: 0, height: 2)))
            list.append(.fillRRect(lens, cornerRadius: lens.height / 2, (selectedSegmentTintColor ?? UIColor(light: .white, dark: RGBA(r: 99, g: 99, b: 102))).rgba(for: style)))
            list.append(.endGroup)
        }
    }
}

/// A control for incrementing or decrementing a value.
@MainActor
open class UIStepper: UIControl {
    open var value: Double = 0 {
        didSet {
            if wraps {
                if value > maximumValue { value = minimumValue } else if value < minimumValue { value = maximumValue }
            } else {
                value = min(max(value, minimumValue), maximumValue)
            }
            setNeedsDisplay()
        }
    }
    open var minimumValue: Double = 0
    open var maximumValue: Double = 100
    open var stepValue: Double = 1
    open var isContinuous = true
    open var autorepeat = true
    open var wraps = false

    static let size = CGSize(width: 94, height: 32)

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: Self.size))
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.size }
    override open var intrinsicContentSize: CGSize { Self.size }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        guard wasTracking, isEnabled, let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        let before = value
        value += location.x < bounds.midX ? -stepValue : stepValue
        if value != before { sendActions(for: .valueChanged) }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let dim = isEnabled ? 1.0 : 0.5
        // The capsule is (58, 58, 70) at 8.6 %, the divider (59, 59, 67) at 36 % (uikit/controls/more).
        let ground: RGBA = style == .dark ? RGBA(r: 118, g: 118, b: 128, a: 0.24) : RGBA(r: 58, g: 58, b: 70, a: 22.0 / 255)
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, ground.multiplyingAlpha(by: dim)))
        let divider = context.absoluteRect(CGRect(x: bounds.midX - 0.5, y: 8, width: 1, height: bounds.height - 16))
        list.append(.fillRect(divider, RGBA(r: 59, g: 59, b: 67, a: 91.0 / 255 * dim)))
        let ink = UIColor.label.rgba(for: style).multiplyingAlpha(by: dim)
        let canDecrement = wraps || value > minimumValue, canIncrement = wraps || value < maximumValue
        let stroke = StrokeStyle(lineWidth: 2, lineCap: .round)
        let left = CGPoint(x: rect.minX + bounds.width / 4, y: rect.midY)
        var minus = Path()
        minus.move(to: CGPoint(x: left.x - 6, y: left.y))
        minus.addLine(to: CGPoint(x: left.x + 6, y: left.y))
        list.append(.strokePath(minus, style: stroke, ink.multiplyingAlpha(by: canDecrement ? 1 : 0.3)))
        let right = CGPoint(x: rect.minX + bounds.width * 3 / 4, y: rect.midY)
        var plus = Path()
        plus.move(to: CGPoint(x: right.x - 6, y: right.y))
        plus.addLine(to: CGPoint(x: right.x + 6, y: right.y))
        plus.move(to: CGPoint(x: right.x, y: right.y - 6))
        plus.addLine(to: CGPoint(x: right.x, y: right.y + 6))
        list.append(.strokePath(plus, style: stroke, ink.multiplyingAlpha(by: canIncrement ? 1 : 0.3)))
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .stepper
        node.value = "\(value)"
        node.isAdjustable = true
    }

    override func accessibilityIncrement() { value += stepValue; sendActions(for: .valueChanged) }
    override func accessibilityDecrement() { value -= stepValue; sendActions(for: .valueChanged) }
}

/// A view that depicts the progress of a task over time.
@MainActor
open class UIProgressView: UIView {
    public enum Style: Int, Sendable { case `default` = 0, bar }

    open var progress: Float = 0 { didSet { progress = min(1, max(0, progress)); setNeedsDisplay() } }
    open var progressViewStyle: Style = .default
    open var progressTintColor: UIColor?
    open var trackTintColor: UIColor?
    open var observedProgress: AnyObject?

    static let height: CGFloat = 4

    public init(progressViewStyle style: Style) {
        progressViewStyle = style
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Self.height))
        isAccessibilityElement = true
    }

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: Self.height)))
        isAccessibilityElement = true
    }

    open func setProgress(_ progress: Float, animated: Bool) { self.progress = progress }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width > 0 && size.width < .greatestFiniteMagnitude ? size.width : bounds.width, height: Self.height) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let track = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        // The track is (120, 120, 125) at 20 % (uikit/controls/more).
        let trackColor = (trackTintColor ?? UIColor(light: RGBA(r: 120, g: 120, b: 125, a: 0.2), dark: RGBA(r: 120, g: 120, b: 128, a: 0.32))).rgba(for: style)
        list.append(.fillRRect(track, cornerRadius: track.height / 2, trackColor))
        let width = (bounds.width * CGFloat(progress)).rounded()
        guard width > 0 else { return }
        let fill = context.absoluteRect(CGRect(x: 0, y: 0, width: width, height: bounds.height))
        list.append(.fillRRect(fill, cornerRadius: fill.height / 2, (progressTintColor ?? tintColor).rgba(for: style)))
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.value = "\(Int((progress * 100).rounded())) %"
    }
}

/// A view that shows that a task is in progress.
@MainActor
open class UIActivityIndicatorView: UIView {
    public enum Style: Int, Sendable { case medium = 100, large = 101 }

    open var style: Style { didSet { frame.size = Self.size(for: style); setNeedsDisplay() } }
    open var hidesWhenStopped = true { didSet { updateHidden() } }
    open var color: UIColor?
    public private(set) var isAnimating = false

    static func size(for style: Style) -> CGSize { style == .large ? CGSize(width: 37, height: 37) : CGSize(width: 20, height: 20) }

    public init(style: Style) {
        self.style = style
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: style)))
        isUserInteractionEnabled = false
        updateHidden()
    }

    public override init(frame: CGRect) {
        style = .medium
        super.init(frame: CGRect(origin: frame.origin, size: Self.size(for: .medium)))
        isUserInteractionEnabled = false
        updateHidden()
    }

    open func startAnimating() { isAnimating = true; updateHidden(); setNeedsDisplay() }
    open func stopAnimating() { isAnimating = false; updateHidden(); setNeedsDisplay() }
    private func updateHidden() { isHidden = hidesWhenStopped && !isAnimating }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.size(for: style) }
    override open var intrinsicContentSize: CGSize { Self.size(for: style) }

    /// Eight spokes fading around the ring (a still of the animation).
    override func drawContent(into list: inout DisplayList, context: PaintContext, style userStyle: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let ink = (color ?? UIColor(light: RGBA(r: 61, g: 61, b: 67, a: 0.8), dark: RGBA(r: 152, g: 152, b: 157))).rgba(for: userStyle)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = rect.width / 2, inner = outer * 0.5, width = max(1.5, rect.width / 10)
        for spoke in 0..<8 {
            let angle = Double(spoke) / 8 * 2 * Double.pi - Double.pi / 2
            var path = Path()
            path.move(to: CGPoint(x: centre.x + inner * _cos(angle), y: centre.y + inner * _sin(angle)))
            path.addLine(to: CGPoint(x: centre.x + (outer - width / 2) * _cos(angle), y: centre.y + (outer - width / 2) * _sin(angle)))
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: width, lineCap: .round), ink.multiplyingAlpha(by: 0.3 + 0.7 * Double(spoke) / 7)))
        }
    }
}

/// A control that displays a horizontal series of dots, each of which corresponds to a page in
/// the app's document or other data-model entity.
@MainActor
open class UIPageControl: UIControl {
    open var numberOfPages = 0 { didSet { frame.size = sizeThatFits(.zero); setNeedsDisplay() } }
    open var currentPage = 0 { didSet { setNeedsDisplay() } }
    open var hidesForSinglePage = false
    open var pageIndicatorTintColor: UIColor?
    open var currentPageIndicatorTintColor: UIColor?
    open var backgroundStyle = 0
    open var allowsContinuousInteraction = true

    static let dot: CGFloat = 10
    static let pitch: CGFloat = 18
    static let height: CGFloat = 26

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    /// 14 pt margins around dots 10 wide on an 18 pt pitch (92 × 26 for four pages).
    open func size(forNumberOfPages pageCount: Int) -> CGSize {
        CGSize(width: 28 + Self.pitch * CGFloat(max(1, pageCount)) - (Self.pitch - Self.dot), height: Self.height)
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { self.size(forNumberOfPages: numberOfPages) }
    override open var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        guard wasTracking, isEnabled, let touch = touches.first, numberOfPages > 0 else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        let target = location.x < bounds.midX ? currentPage - 1 : currentPage + 1
        let clamped = min(numberOfPages - 1, max(0, target))
        if clamped != currentPage { currentPage = clamped; sendActions(for: .valueChanged) }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard numberOfPages > 0, !(hidesForSinglePage && numberOfPages == 1) else { return }
        // iOS 26 dots are white (the current one opaque, the others at 45 %) over a material
        // backdrop the simulator's capture leaves transparent (uikit/controls/more).
        let inactive = (pageIndicatorTintColor ?? UIColor(white: 1, alpha: 115.0 / 255)).rgba(for: style)
        let active = (currentPageIndicatorTintColor ?? UIColor.white).rgba(for: style)
        for page in 0..<numberOfPages {
            let dot = context.absoluteRect(CGRect(x: 14 + Self.pitch * CGFloat(page), y: 8, width: Self.dot, height: Self.dot))
            list.append(.fillRRect(dot, cornerRadius: Self.dot / 2, page == currentPage ? active : inactive))
        }
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.value = "page \(currentPage + 1) of \(numberOfPages)"
        node.isAdjustable = true
    }

    override func accessibilityIncrement() { currentPage = min(numberOfPages - 1, currentPage + 1); sendActions(for: .valueChanged) }
    override func accessibilityDecrement() { currentPage = max(0, currentPage - 1); sendActions(for: .valueChanged) }
}
