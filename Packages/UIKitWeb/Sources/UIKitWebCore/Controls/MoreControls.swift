// The remaining controls (Docs/elements/UIKit/Controls.md): UISlider, UISegmentedControl,
// UIStepper, UIProgressView, UIActivityIndicatorView, UIPageControl. Geometry from UIKit on the
// iPhone SE simulator (iOS 26, `uikit/controls/more`); the looks are the iOS 26 glass controls
// drawn flat.

/// A control for selecting a single value from a continuous range of values.
@MainActor
open class UISlider: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    open var value: Float = 0 { didSet { value = min(max(value, minimumValue), maximumValue); setNeedsDisplay() } }
    open var minimumValue: Float = 0
    open var maximumValue: Float = 1
    open var isContinuous = true
    open var minimumTrackTintColor: UIColor?
    open var maximumTrackTintColor: UIColor?
    open var thumbTintColor: UIColor?
    /// Images at the ends (uikit/controls/rest): each at its edge, vertically centred, the
    /// track 11 pt in from it.
    open var minimumValueImage: UIImage? { didSet { setNeedsDisplay() } }
    open var maximumValueImage: UIImage? { didSet { setNeedsDisplay() } }
    static let imageTrackGap: CGFloat = 11

    static let height: CGFloat = 34
    static let knobSize = CGSize(width: 38, height: 25)
    static let trackHeight: CGFloat = 6

    public override init(frame: CGRect) {
        // A slider keeps the height it is given (uikit/accessibility/basic: 30 stays 30); an
        // empty frame takes the intrinsic 34.
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: frame.height > 0 ? frame.height : Self.height)))
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        // A slider keeps its height in a taller container (ios/representable/measure-controls: 34 in 44).
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    open func setValue(_ value: Float, animated: Bool) { self.value = value }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width > 0 && size.width < .greatestFiniteMagnitude ? size.width : bounds.width, height: Self.height) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    /// The value as a fraction of the range.
    var fraction: CGFloat {
        let range = maximumValue - minimumValue
        return range > 0 ? CGFloat((value - minimumValue) / range) : 0
    }

    /// The knob's frame: a 38 × 25 lens 4 down, travelling over the track's width less its own.
    open func thumbRect(forBounds bounds: CGRect, trackRect: CGRect, value: Float) -> CGRect {
        let track = self.trackRect(forBounds: bounds)
        let x = (track.minX - bounds.minX + (track.width - Self.knobSize.width) * fraction).rounded()
        return CGRect(x: bounds.minX + x, y: bounds.minY + 4, width: Self.knobSize.width, height: Self.knobSize.height)
    }

    open func minimumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard let image = minimumValueImage else { return .zero }
        return CGRect(x: bounds.minX, y: bounds.minY + (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height)
    }

    open func maximumValueImageRect(forBounds bounds: CGRect) -> CGRect {
        guard let image = maximumValueImage else { return .zero }
        return CGRect(x: bounds.maxX - image.size.width, y: bounds.minY + (bounds.height - image.size.height) / 2, width: image.size.width, height: image.size.height)
    }

    open func trackRect(forBounds bounds: CGRect) -> CGRect {
        let leading = minimumValueImage.map { $0.size.width + Self.imageTrackGap } ?? 0
        let trailing = maximumValueImage.map { $0.size.width + Self.imageTrackGap } ?? 0
        return CGRect(x: bounds.minX + leading, y: bounds.minY + 14, width: max(0, bounds.width - leading - trailing), height: Self.trackHeight)
    }

    private func setValue(atX x: CGFloat) {
        let track = trackRect(forBounds: bounds)
        let travel = track.width - Self.knobSize.width
        let fraction = min(1, max(0, (x - track.minX - Self.knobSize.width / 2) / max(1, travel)))
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
        let trackBounds = trackRect(forBounds: bounds)
        let filled = context.absoluteRect(CGRect(x: trackBounds.minX, y: 14, width: trackBounds.width * fraction, height: Self.trackHeight))
        list.append(.fillRRect(filled, cornerRadius: filled.height / 2, (minimumTrackTintColor ?? tintColor).rgba(for: style).multiplyingAlpha(by: dim)))
        // The end images, tinted like a template image (symbols are), dimmed with the control.
        for (image, rect) in [(minimumValueImage, minimumValueImageRect(forBounds: bounds)), (maximumValueImage, maximumValueImageRect(forBounds: bounds))] {
            guard let image, !rect.isEmpty else { continue }
            UIImageView.paint(image, in: context.absoluteRect(rect), tint: tintColor.rgba(for: style).multiplyingAlpha(by: dim), scale: context.scale, style: style, into: &list)
        }
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

    override open func accessibilityIncrement() { value += (maximumValue - minimumValue) / 10; sendActions(for: .valueChanged) }
    override open func accessibilityDecrement() { value -= (maximumValue - minimumValue) / 10; sendActions(for: .valueChanged) }
    override func accessibilitySetValue(_ value: Double) { self.value = minimumValue + Float(value / 100) * (maximumValue - minimumValue); sendActions(for: .valueChanged) }
}

/// A horizontal control that consists of multiple segments, each segment functioning as a
/// discrete button.
@MainActor
open class UISegmentedControl: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public static let noSegment = -1

    private var titles: [String?] = []
    private var images: [UIImage?] = []
    /// `setWidth(_:forSegmentAt:)`: a fixed width per segment (0 for the automatic one).
    private var fixedWidths: [CGFloat] = []
    private var enabledSegments: [Bool] = []
    open var selectedSegmentIndex: Int = UISegmentedControl.noSegment { didSet { setNeedsLayout(); setNeedsDisplay() } }
    open var isMomentary = false
    /// Segments take their content's width (plus 19, at least 32) instead of sharing the widest
    /// (uikit/controls/rest: "A", "Second", "C" are 32, 65, 32).
    open var apportionsSegmentWidthsByContent = false { didSet { setNeedsLayout(); invalidateIntrinsicContentSize() } }
    open var selectedSegmentTintColor: UIColor?
    private var labels: [UILabel] = []
    private var imageViews: [UIImageView] = []

    static let height: CGFloat = 32
    /// The titles' size and whether the selected one is medium: 13 with a medium selection for
    /// a control of its own, 15 regular throughout in a search bar's scope bar (uikit/search/scope).
    var titleSize: CGFloat = 13 { didSet { setNeedsLayout() } }
    var emphasisesSelection = true { didSet { setNeedsLayout() } }

    public init(items: [Any]?) {
        super.init(frame: .zero)
        isAccessibilityElement = false
        // A segmented control hugs its height (uikit/autolayout/hugging: 250 / 750 / 750 / 750).
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        for item in items ?? [] {
            if let title = item as? String { titles.append(title); images.append(nil) }
            else if let image = item as? UIImage { titles.append(nil); images.append(image) }
            fixedWidths.append(0)
            enabledSegments.append(true)
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
        let at = min(segment, titles.count)
        titles.insert(title, at: at)
        images.insert(nil, at: at)
        fixedWidths.insert(0, at: at)
        enabledSegments.insert(true, at: at)
        rebuild()
    }

    open func insertSegment(with image: UIImage?, at segment: Int, animated: Bool) {
        let at = min(segment, titles.count)
        titles.insert(nil, at: at)
        images.insert(image, at: at)
        fixedWidths.insert(0, at: at)
        enabledSegments.insert(true, at: at)
        rebuild()
    }

    open func removeSegment(at segment: Int, animated: Bool) {
        guard titles.indices.contains(segment) else { return }
        titles.remove(at: segment)
        images.remove(at: segment)
        fixedWidths.remove(at: segment)
        enabledSegments.remove(at: segment)
        rebuild()
    }

    open func removeAllSegments() { titles = []; images = []; fixedWidths = []; enabledSegments = []; rebuild() }
    open func setTitle(_ title: String?, forSegmentAt segment: Int) { guard titles.indices.contains(segment) else { return }; titles[segment] = title; images[segment] = nil; rebuild() }
    open func titleForSegment(at segment: Int) -> String? { titles.indices.contains(segment) ? titles[segment] : nil }
    open func setImage(_ image: UIImage?, forSegmentAt segment: Int) { guard images.indices.contains(segment) else { return }; images[segment] = image; titles[segment] = nil; rebuild() }
    open func imageForSegment(at segment: Int) -> UIImage? { images.indices.contains(segment) ? images[segment] : nil }
    open func setEnabled(_ enabled: Bool, forSegmentAt segment: Int) { guard enabledSegments.indices.contains(segment) else { return }; enabledSegments[segment] = enabled; setNeedsLayout() }
    open func isEnabledForSegment(at segment: Int) -> Bool { enabledSegments.indices.contains(segment) ? enabledSegments[segment] : false }
    /// A fixed width for a segment (0 restores the automatic one): the others keep theirs.
    open func setWidth(_ width: CGFloat, forSegmentAt segment: Int) {
        guard fixedWidths.indices.contains(segment) else { return }
        fixedWidths[segment] = max(0, width)
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }
    open func widthForSegment(at segment: Int) -> CGFloat { fixedWidths.indices.contains(segment) ? fixedWidths[segment] : 0 }

    private func rebuild() {
        for label in labels { label.removeFromSuperview() }
        for view in imageViews { view.removeFromSuperview() }
        labels = []
        imageViews = []
        for (index, title) in titles.enumerated() {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: titleSize)
            label.textAlignment = .center
            addSubview(label)
            labels.append(label)
            let imageView = UIImageView(image: images[index])
            imageView.contentMode = .scaleAspectFit
            addSubview(imageView)
            imageViews.append(imageView)
        }
        setNeedsLayout()
    }

    /// Every segment is as wide as the widest title rounded up plus 19 (uikit/controls/more:
    /// 55 for "Three" at 35.5; uikit/autolayout/hugging: 44 for "One" at 25) and at least 32
    /// (ios/representable/measure-controls: 64 for "A" and "B"); the control is 32 tall. An
    /// image segment is 40 wide (uikit/controls/rest).
    static let minimumSegmentWidth: CGFloat = 32
    static let imageSegmentWidth: CGFloat = 40
    /// A segment's own content width: its title plus 19 (at least 32), or 40 for an image.
    private func naturalWidth(_ index: Int) -> CGFloat {
        if images[index] != nil { return Self.imageSegmentWidth }
        return max(Self.minimumSegmentWidth, labels[index].intrinsicContentSize.width.rounded(.up) + 19)
    }
    var segmentWidth: CGFloat {
        let widest = titles.indices.map { naturalWidth($0) }.max() ?? 0
        return max(Self.minimumSegmentWidth, widest)
    }

    /// The segments' widths at the control's size: fixed widths as set, the rest sharing the
    /// widest natural width (or their own when apportioned); a frame wider or narrower than
    /// their sum scales the automatic ones.
    func segmentWidths(for totalWidth: CGFloat) -> [CGFloat] {
        guard !titles.isEmpty else { return [] }
        var widths = titles.indices.map { index -> CGFloat in
            if fixedWidths[index] > 0 { return fixedWidths[index] }
            return apportionsSegmentWidthsByContent ? naturalWidth(index) : segmentWidth
        }
        let automatic = titles.indices.filter { fixedWidths[$0] == 0 }
        let fixedTotal = titles.indices.filter { fixedWidths[$0] > 0 }.reduce(0) { $0 + widths[$1] }
        let automaticTotal = automatic.reduce(0) { $0 + widths[$1] }
        if totalWidth > 0, !automatic.isEmpty, automaticTotal > 0, abs(totalWidth - fixedTotal - automaticTotal) > 0.01 {
            let scale = max(0, totalWidth - fixedTotal) / automaticTotal
            for index in automatic { widths[index] *= scale }
        }
        return widths
    }

    /// Where each segment starts.
    private func segmentFrames() -> [CGRect] {
        var x: CGFloat = 0
        return segmentWidths(for: bounds.width).map { width in
            defer { x += width }
            return CGRect(x: x, y: 0, width: width, height: bounds.height)
        }
    }

    /// The intrinsic size is the 31 pt alignment rect inside the 32 pt frame: Auto Layout and
    /// SwiftUI's representables lay the control out on it (uikit/autolayout/hugging,
    /// ios/representable/measure-controls).
    override open var alignmentRectInsets: UIEdgeInsets { UIEdgeInsets(top: 0.5, left: 0, bottom: 0.5, right: 0) }

    /// The natural width: the segments' widths at rest.
    private var naturalTotalWidth: CGFloat { max(Self.minimumSegmentWidth, segmentWidths(for: 0).reduce(0, +)) }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: naturalTotalWidth, height: Self.height) }

    override open var intrinsicContentSize: CGSize { CGSize(width: naturalTotalWidth, height: Self.height - 1) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        let frames = segmentFrames()
        for (index, label) in labels.enumerated() where index < frames.count {
            let segment = frames[index]
            label.font = .systemFont(ofSize: titleSize, weight: emphasisesSelection && index == selectedSegmentIndex ? .medium : .regular)
            label.isHidden = titles[index] == nil
            let textSize = label.intrinsicContentSize
            // The label is centred in the segment: 13 pt titles 16 tall at 8, 15 pt ones 18 tall at 7.
            label.frame = CGRect(x: (segment.minX + (segment.width - textSize.width) / 2).rounded(), y: ((Self.height - textSize.height) / 2).rounded(), width: textSize.width, height: textSize.height)
            label.alpha = enabledSegments[index] ? 1 : 0.5
            // An image segment centres its image at its size (symbols at their point size).
            let imageView = imageViews[index]
            imageView.isHidden = images[index] == nil
            let imageSize = images[index]?.size ?? .zero
            imageView.frame = CGRect(x: segment.minX + ((segment.width - imageSize.width) / 2), y: (Self.height - imageSize.height) / 2, width: imageSize.width, height: imageSize.height)
            imageView.tintColor = tintColor
            imageView.alpha = enabledSegments[index] ? 1 : 0.5
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        guard wasTracking, isEnabled, let touch = touches.first, !titles.isEmpty else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        let frames = segmentFrames()
        let index = frames.firstIndex { $0.contains(CGPoint(x: location.x, y: Self.height / 2)) } ?? (location.x < 0 ? 0 : titles.count - 1)
        guard enabledSegments[index] else { return }
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
            let segment = segmentFrames()[selectedSegmentIndex]
            let lens = context.absoluteRect(CGRect(x: segment.minX + 2, y: 2, width: segment.width - 4, height: bounds.height - 4))
            list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.1), radius: 4, offset: CGSize(width: 0, height: 2)))
            list.append(.fillRRect(lens, cornerRadius: lens.height / 2, (selectedSegmentTintColor ?? UIColor(light: .white, dark: RGBA(r: 99, g: 99, b: 102))).rgba(for: style)))
            list.append(.endGroup)
        }
    }
}

/// A control for incrementing or decrementing a value.
@MainActor
open class UIStepper: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

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
        // A stepper hugs on both axes (uikit/autolayout/hugging: 750 everywhere).
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.size }
    override open var intrinsicContentSize: CGSize { Self.size }

    /// The side pressed (negative steps down) and the repeat while it is held: UIKit steps on
    /// the press, then — `autorepeat` — again after half a second and every tenth of a second,
    /// faster after a while (unmeasured: the delay and rate approximate UIKit's).
    private var pressedDirection: Double?
    private var repeatTimer: UIKitScene.Timer?
    private var repeats = 0
    static let repeatDelay = 0.5
    static let repeatInterval = 0.1

    private func step(_ direction: Double) {
        let before = value
        value += direction * stepValue
        if value != before, isContinuous || !isTracking { sendActions(for: .valueChanged) }
    }

    private func scheduleRepeat(after delay: Double) {
        repeatTimer?.cancel()
        repeatTimer = UIKitScene.shared.schedule(after: delay) { [weak self] in
            guard let self, let direction = self.pressedDirection else { return }
            self.repeats += 1
            self.step(direction)
            // Ten repeats in, the rate doubles (UIKit accelerates held steppers).
            self.scheduleRepeat(after: self.repeats >= 10 ? Self.repeatInterval / 2 : Self.repeatInterval)
        }
    }

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isEnabled, let touch = touches.first else { return }
        let direction: Double = touch.location(in: self).x < bounds.midX ? -1 : 1
        pressedDirection = direction
        repeats = 0
        step(direction)
        if autorepeat { scheduleRepeat(after: Self.repeatDelay) }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        endPress()
    }

    override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        endPress()
    }

    private func endPress() {
        repeatTimer?.cancel()
        repeatTimer = nil
        pressedDirection = nil
        if !isContinuous { sendActions(for: .valueChanged) }
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

    override open func accessibilityIncrement() { value += stepValue; sendActions(for: .valueChanged) }
    override open func accessibilityDecrement() { value -= stepValue; sendActions(for: .valueChanged) }
}

/// A view that depicts the progress of a task over time.
@MainActor
open class UIProgressView: UIView {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

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
        setContentHuggingPriority(.defaultHigh, for: .vertical)
        isAccessibilityElement = true
    }

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: Self.height)))
        isAccessibilityElement = true
        // A progress view keeps its 4 pt in a taller container (ios/representable/measure-controls).
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    /// A frame set later keeps the 4 pt too (uikit/autolayout/hugging: 8 asked, 4 kept).
    override open var frame: CGRect {
        get { super.frame }
        set { super.frame = CGRect(origin: newValue.origin, size: CGSize(width: newValue.width, height: Self.height)) }
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
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

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
        hugContent()
        updateHidden()
    }

    public override init(frame: CGRect) {
        style = .medium
        super.init(frame: CGRect(origin: frame.origin, size: Self.size(for: .medium)))
        isUserInteractionEnabled = false
        hugContent()
        updateHidden()
    }

    /// An indicator hugs on both axes (uikit/autolayout/hugging: 750 everywhere).
    private func hugContent() {
        setContentHuggingPriority(.defaultHigh, for: .horizontal)
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    /// Seconds since `startAnimating`, advanced by the scene's frame loop: the spokes' pattern
    /// steps one spoke every 1/8 s, a revolution per second (approximate: UIKit's rate is not
    /// measured; the still at phase 0 is what the goldens hold).
    private var clock: Double = 0
    static let stepsPerSecond = 8.0
    var phase: Int { Int(clock * Self.stepsPerSecond) % 8 }

    open func startAnimating() {
        guard !isAnimating else { return }
        isAnimating = true
        clock = 0
        updateHidden()
        UIKitScene.shared.spinners.append(WeakActivityIndicator(view: self))
        UIKitScene.shared.setNeedsFrame()
        setNeedsDisplay()
    }

    open func stopAnimating() {
        isAnimating = false
        updateHidden()
        UIKitScene.shared.spinners.removeAll { $0.view === self || $0.view == nil }
        setNeedsDisplay()
    }

    private func updateHidden() { isHidden = hidesWhenStopped && !isAnimating }

    /// Advances the clock; repaints when the pattern steps.
    func advance(elapsed: Double) {
        let before = phase
        clock += elapsed
        if phase != before { setNeedsDisplay() }
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { Self.size(for: style) }
    override open var intrinsicContentSize: CGSize { Self.size(for: style) }

    /// Eight spokes fading around the ring; the pattern turns with `phase` while animating.
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
            let step = (spoke - phase + 8) % 8
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: width, lineCap: .round), ink.multiplyingAlpha(by: 0.3 + 0.7 * Double(step) / 7)))
        }
    }
}

/// A spinning indicator the scene advances (`UIKitScene.spinners`).
/// A view the scene's frame loop advances while it animates (activity indicators, animated
/// image views).
@MainActor
protocol ClockAnimating: AnyObject {
    var isAnimating: Bool { get }
    func advance(elapsed: Double)
}

extension UIActivityIndicatorView: ClockAnimating {}

struct WeakActivityIndicator {
    weak var view: (any ClockAnimating)?
}

/// A control that displays a horizontal series of dots, each of which corresponds to a page in
/// the app's document or other data-model entity.
@MainActor
open class UIPageControl: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

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
        // A page control hugs its height (uikit/autolayout/hugging: 250 / 750 / 750 / 750).
        setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    /// 14 pt margins around dots 10 wide on an 18 pt pitch (92 × 26 for four pages).
    open func size(forNumberOfPages pageCount: Int) -> CGSize {
        CGSize(width: 28 + Self.pitch * CGFloat(max(1, pageCount)) - (Self.pitch - Self.dot), height: Self.height)
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { self.size(forNumberOfPages: numberOfPages) }
    override open var intrinsicContentSize: CGSize { sizeThatFits(.zero) }

    /// A drag along the control scrubs the pages (`allowsContinuousInteraction`): past 10 pt of
    /// travel the page follows the finger's position across the dots.
    private var dragStart: CGPoint?
    private var scrubbing = false

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        dragStart = touches.first?.location(in: self)
        scrubbing = false
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard allowsContinuousInteraction, isEnabled, numberOfPages > 0, let touch = touches.first, let start = dragStart else { return }
        let location = touch.location(in: self)
        if !scrubbing, abs(location.x - start.x) < 10 { return }
        scrubbing = true
        let page = min(numberOfPages - 1, max(0, Int((location.x / max(1, bounds.width)) * CGFloat(numberOfPages))))
        if page != currentPage { currentPage = page; sendActions(for: .valueChanged) }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasTracking = isTracking
        super.touchesEnded(touches, with: event)
        defer { dragStart = nil; scrubbing = false }
        guard wasTracking, isEnabled, !scrubbing, let touch = touches.first, numberOfPages > 0 else { return }
        let location = touch.location(in: self)
        guard point(inside: location, with: event) else { return }
        // A tap on the leading half goes back a page, on the trailing half forward (UIKit's tap).
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

    override open func accessibilityIncrement() { currentPage = min(numberOfPages - 1, currentPage + 1); sendActions(for: .valueChanged) }
    override open func accessibilityDecrement() { currentPage = max(0, currentPage - 1); sendActions(for: .valueChanged) }
}
