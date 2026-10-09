// UIRefreshControl (Docs/elements/UIKit/UIScrollView.md): the pull-to-refresh control a scroll
// view or table holds above its content. Measured on the iPhone SE simulator (iOS 26,
// uikit/scroll/refresh): 60 tall (84.5 with a title: a 12 pt label 17.5 tall 60.75 down, 10 in),
// its spinner eight 3.5 × 10 rounded spokes of the label colour 5 to 15 from a centre 30 down,
// grown by 1.2 and turning while refreshing, hidden at rest. The control sits 60 above the
// content while refreshing (the scroll view's inset grows by its height, so the content can rest
// below it) and at the content's top, hidden, otherwise.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A standard control that can initiate the refreshing of a scroll view's contents.
@MainActor
open class UIRefreshControl: UIControl, ClockAnimating {
    static let height: CGFloat = 60
    static let spinnerCentre: CGFloat = 30
    static let titleTop: CGFloat = 60.75
    static let titleHeight: CGFloat = 17.5
    static let titleBottom: CGFloat = 6.25
    /// The pull that starts a refresh: the control's height (approximate: unmeasured).
    static let threshold: CGFloat = 60

    open private(set) var isRefreshing = false
    /// The title under the spinner (12 pt; the string's own attributes are not applied).
    open var attributedTitle: NSAttributedString? { didSet { invalidateIntrinsicContentSize(); scrollView?.setNeedsLayout(); setNeedsDisplay() } }
    weak var scrollView: UIScrollView?
    /// How far a pull in progress has revealed the control (0 … 1), driving the spokes' growth.
    var pullFraction: CGFloat = 0 { didSet { if pullFraction != oldValue { setNeedsDisplay() } } }
    private var clock: Double = 0

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: Self.height)))
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Refresh"
        isHidden = true
    }

    public convenience init() { self.init(frame: .zero) }

    /// The control's height: 60, plus the title's line and its 6.25 pt bottom.
    var preferredHeight: CGFloat { attributedTitle == nil ? Self.height : Self.titleTop + Self.titleHeight + Self.titleBottom }
    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: preferredHeight) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: preferredHeight) }

    /// Shows the control refreshing (the scroll view makes room above its content); no event is sent.
    open func beginRefreshing() {
        guard !isRefreshing else { return }
        isRefreshing = true
        pullFraction = 1
        clock = 0
        isHidden = false
        UIKitScene.shared.spinners.append(WeakActivityIndicator(view: self))
        UIKitScene.shared.setNeedsFrame()
        scrollView?.refreshStateDidChange()
        setNeedsDisplay()
    }

    open func endRefreshing() {
        guard isRefreshing else { return }
        isRefreshing = false
        pullFraction = 0
        UIKitScene.shared.spinners.removeAll { $0.view === self || $0.view == nil }
        scrollView?.refreshStateDidChange()
        setNeedsDisplay()
    }

    /// A pull released past the threshold: refreshing starts and `valueChanged` fires.
    func triggerFromPull() {
        beginRefreshing()
        sendActions(for: [.valueChanged, .primaryActionTriggered])
    }

    var isAnimating: Bool { isRefreshing }

    /// The spokes turn a step every 1/8 s while refreshing (approximate: UIKit's rate is unmeasured).
    func advance(elapsed: Double) {
        let before = phase
        clock += elapsed
        if phase != before { setNeedsDisplay() }
    }
    private var phase: Int { Int(clock * 8) % 8 }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard isRefreshing || pullFraction > 0 else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let ink = (tintColor ?? UIColor.label).rgba(for: style)
        let centre = CGPoint(x: rect.midX, y: rect.minY + Self.spinnerCentre)
        // Refreshing, the spokes are a fifth bigger (4.2 × 12, 6 to 18 from the centre).
        let scale: CGFloat = isRefreshing ? 1.2 : 0.6 + 0.6 * pullFraction
        let inner = 5 * scale, outer = 15 * scale, width = 3.5 * scale
        let shown = isRefreshing ? 8 : max(1, Int((pullFraction * 8).rounded(.up)))
        for spoke in 0..<shown {
            let angle = Double(spoke) / 8 * 2 * Double.pi - Double.pi / 2
            var path = Path()
            path.move(to: CGPoint(x: centre.x + (inner + width / 2) * _cos(angle), y: centre.y + (inner + width / 2) * _sin(angle)))
            path.addLine(to: CGPoint(x: centre.x + (outer - width / 2) * _cos(angle), y: centre.y + (outer - width / 2) * _sin(angle)))
            let step = (spoke - phase + 8) % 8
            let alpha = isRefreshing ? 0.3 + 0.7 * Double(step) / 7 : 1
            list.append(.strokePath(path, style: StrokeStyle(lineWidth: width, lineCap: .round), ink.multiplyingAlpha(by: alpha)))
        }
        if let title = attributedTitle?.string, !title.isEmpty {
            let font = UIFont.systemFont(ofSize: 12)
            let layout = UIKitScene.shared.textEngine.layout([StyledRun(title, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
            guard let line = layout.lines.first else { return }
            let x = rect.midX - layout.size.width / 2
            let baseline = rect.minY + Self.titleTop + ((Self.titleHeight - font.lineHeight) / 2 * 2).rounded() / 2 + font.ascender
            for fragment in line.fragments {
                list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: x + fragment.x, y: baseline), UIColor.label.rgba(for: style)))
            }
        }
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .button
        if node.label.isEmpty { node.label = attributedTitle?.string ?? "Refresh" }
    }
}
