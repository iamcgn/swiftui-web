// `UIHostingController` (decision 0014, Phase 3): a SwiftUI view inside UIKit, the reverse of a
// representable. The hosting view runs its own `Runtime`, paints its display list at the view's
// origin, turns UIKit touches into the runtime's pointer, exposes the runtime's semantics tree
// through UIKitWeb's hosting SPI and advances the runtime's clock with the scene's
// (Docs/elements/Representable.md).
import SwiftUIWebCore
import UIKitWebCore

/// Options for how a hosting controller tracks its content's size.
public struct UIHostingControllerSizingOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let preferredContentSize = UIHostingControllerSizingOptions(rawValue: 1)
    public static let intrinsicContentSize = UIHostingControllerSizingOptions(rawValue: 2)
}

/// A UIKit view controller that manages a SwiftUI view hierarchy.
@MainActor
open class UIHostingController<Content: View>: UIViewController {
    /// The root view of the SwiftUI view hierarchy managed by this view controller.
    public var rootView: Content {
        didSet { hostingView?.rootView = rootView }
    }
    /// The safe area regions the content respects: with `.container` the hosting view's safe
    /// area (a navigation or tab bar's) is the content's (ios/representable/hostingsafearea);
    /// without it the content fills the view (hostingsafearea-none).
    public var safeAreaRegions: SafeAreaRegions = .all {
        didSet { hostingView?.safeAreaRegions = safeAreaRegions }
    }
    /// `preferredContentSize` keeps the controller's preferred size at the content's ideal size;
    /// `intrinsicContentSize` invalidates the view's intrinsic size when the content changes.
    public var sizingOptions: UIHostingControllerSizingOptions = [] {
        didSet {
            hostingView?.sizingOptions = sizingOptions
            if sizingOptions.contains(.preferredContentSize), let view = hostingView { preferredContentSize = view.sizeThatFits(UIView.layoutFittingExpandedSize) }
        }
    }
    private var hostingView: _UIHostingView<Content>?
    /// The bar items made from the content's `toolbar`, each keeping the runtime that answers
    /// its tap.
    private var bridgedItems: [BridgedBarItem] = []
    private var bridgedTitle: String?

    public init(rootView: Content) {
        self.rootView = rootView
        super.init(nibName: nil, bundle: nil)
    }

    open override func loadView() {
        let view = _UIHostingView(rootView: rootView)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.safeAreaRegions = safeAreaRegions
        view.sizingOptions = sizingOptions
        view.onContentChange = { [weak self] in self?.contentDidChange() }
        view.onChromeChange = { [weak self] title, items in self?.syncNavigationItem(title: title, items: items) }
        hostingView = view
        self.view = view
        contentDidChange()
    }

    private func contentDidChange() {
        if sizingOptions.contains(.preferredContentSize), let view = hostingView {
            let size = view.sizeThatFits(UIView.layoutFittingExpandedSize)
            if preferredContentSize != size { preferredContentSize = size }
        }
    }

    /// The content's `navigationTitle` and `toolbar` drive the navigation item, as SwiftUI
    /// bridges them for a hosting controller in a navigation controller
    /// (ios/representable/hostingnav): a titled item per button, leading placements on the
    /// left, the rest on the right; a tap runs the button's action.
    private func syncNavigationItem(title: String?, items: [_ToolbarItemData]) {
        if let title, title != bridgedTitle {
            bridgedTitle = title
            navigationItem.title = title
        }
        let labels = items.map(BridgedBarItem.label)
        guard labels != bridgedItems.map(\.label) || items.count != bridgedItems.count else { return }
        bridgedItems = items.map { BridgedBarItem(item: $0) }
        let leading = bridgedItems.filter(\.isLeading).map(\.barItem)
        let trailing = bridgedItems.filter { !$0.isLeading }.map(\.barItem)
        navigationItem.leftBarButtonItems = leading.isEmpty ? nil : leading
        navigationItem.rightBarButtonItems = trailing.isEmpty ? nil : trailing.reversed()
    }

    /// The size the content wants for a proposal (nothing proposed: the ideal size).
    public func sizeThatFits(in size: CGSize) -> CGSize {
        loadViewIfNeeded()
        return hostingView?.sizeThatFits(size) ?? .zero
    }
}

/// A SwiftUI toolbar item as a bar button item: its label and role come from the item's
/// semantics in a runtime of its own, which also answers the tap.
@MainActor
final class BridgedBarItem {
    let runtime = Runtime()
    let barItem: UIBarButtonItem
    let label: String
    let isLeading: Bool

    static func label(of item: _ToolbarItemData) -> String {
        let runtime = Runtime()
        runtime.mount(item.view)
        runtime.layout(in: CGSize(width: 320, height: 44))
        return runtime.semanticsTree().first { !$0.label.isEmpty }?.label ?? ""
    }

    init(item: _ToolbarItemData) {
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        runtime.rootEnvironment = environment
        runtime.mount(item.view)
        runtime.layout(in: CGSize(width: 320, height: 44))
        let element = runtime.semanticsTree().first { !$0.label.isEmpty }
        label = element?.label ?? ""
        switch item.placement.group {
        case .leading: isLeading = true
        default: isLeading = false
        }
        let identifier = element?.identifier
        let runtime = self.runtime
        barItem = UIBarButtonItem(title: label, primaryAction: UIAction { _ in
            if let identifier { runtime.activate(semanticsIdentifier: identifier) }
        })
    }
}

/// The view a hosting controller manages: a SwiftUI runtime in a UIKit view.
@MainActor
final class _UIHostingView<Content: View>: UIView {
    let runtime: Runtime
    /// Setting the root inside `withAnimation` animates the change, as a state change would.
    var rootView: Content {
        didSet {
            if let transaction = Transaction._current, !transaction.disablesAnimations, let animation = transaction.animation {
                runtime.pendingAnimation = animation
            }
            runtime.mount(rootView)
            setNeedsLayout()
        }
    }
    private var laidOutSize = CGSize.zero
    var sizingOptions: UIHostingControllerSizingOptions = []
    /// The content asked for a frame (a state change): the controller keeps its sizes current.
    var onContentChange: (@MainActor () -> Void)?
    /// The content's navigation title and toolbar items after a layout, when either changed.
    var onChromeChange: (@MainActor (String?, [_ToolbarItemData]) -> Void)?
    private var syncedChrome: (title: String?, count: Int, labels: [String])?
    /// The regions of the view's safe area the content respects (the controller's setting).
    var safeAreaRegions: SafeAreaRegions = .all {
        didSet { if safeAreaRegions != oldValue { setNeedsLayout() } }
    }

    init(rootView: Content) {
        self.rootView = rootView
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        runtime = Runtime(environment: environment)
        runtime.paintsWindowBackground = false
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        runtime.mount(rootView)
        runtime.onNeedsFrame = { [weak self] in self?.contentNeedsFrame() }
        _registerAsHostingView()
    }

    private func contentNeedsFrame() {
        setNeedsLayout()
        setNeedsDisplay()
        if sizingOptions.contains(.intrinsicContentSize) { invalidateIntrinsicContentSize() }
        onContentChange?()
    }

    /// Hands the controller the title and toolbar items the content declares, when they changed.
    private func syncChrome() {
        guard let onChromeChange else { return }
        let items = runtime._toolbarItems
        let labels = items.map(BridgedBarItem.label)
        let title = runtime.navigationTitle
        if let synced = syncedChrome, synced.title == title, synced.count == items.count, synced.labels == labels { return }
        syncedChrome = (title, items.count, labels)
        onChromeChange(title, items)
    }

    /// The runtime measures with the scene's engine and reads its catalog and appearance.
    private func prepare() {
        let scene = UIKitScene.shared
        if let current = runtime.textEngine as AnyObject?, let engine = scene.textEngine as AnyObject?, current === engine {
            // Installed.
        } else {
            runtime.textEngine = scene.textEngine
        }
        if runtime.assetCatalog != scene.assetCatalog { runtime.assetCatalog = scene.assetCatalog }
        let scheme: ColorScheme = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        if runtime.hostColorScheme != scheme { runtime.hostColorScheme = scheme }
        // The view's safe area (a container's bars) is the content's, unless ignored.
        let insets = safeAreaRegions.contains(.container) ? safeAreaInsets : .zero
        runtime.safeAreaInsets = EdgeInsets(top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        prepare()
        runtime.layout(in: bounds.size)
        laidOutSize = bounds.size
        syncChrome()
    }

    /// The content's size for a proposal: a dimension at or beyond the fitting sizes is left
    /// unspecified, so `sizeThatFits(in:)` and the intrinsic size give the ideal size.
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        prepare()
        runtime.flushForMeasurement()
        guard let node = runtime.root.layoutChildren.first else { return .zero }
        func proposed(_ value: CGFloat) -> CGFloat? { value <= 0 || value >= UIView.layoutFittingExpandedSize.width ? nil : value }
        return node.sizeThatFits(ProposedViewSize(width: proposed(size.width), height: proposed(size.height)))
    }

    override var intrinsicContentSize: CGSize { sizeThatFits(UIView.layoutFittingExpandedSize) }

    // MARK: Hosting SPI

    override func _hostedPaint(into list: inout DisplayList, context: PaintContext) {
        prepare()
        if laidOutSize != bounds.size || runtime.needsFrame {
            runtime.layout(in: bounds.size)
            laidOutSize = bounds.size
        }
        let content = runtime.render(scale: context.scale)
        list.append(.save)
        list.append(.concat(CGAffineTransform(translationX: context.origin.x, y: context.origin.y)))
        for command in content.commands { list.append(command) }
        list.append(.restore)
    }

    override func _hostedSemantics() -> [SemanticsNode]? { runtime.semanticsTree() }
    override func _hostedHandles(semanticsIdentifier: Int) -> Bool { runtime.semanticsTree().contains { $0.identifier == semanticsIdentifier } }
    override func _hostedActivate(semanticsIdentifier: Int) { runtime.activate(semanticsIdentifier: semanticsIdentifier) }
    override func _hostedAdjust(semanticsIdentifier: Int, increment: Bool) { runtime.adjust(semanticsIdentifier: semanticsIdentifier, increment: increment) }
    override func _hostedSetValue(semanticsIdentifier: Int, value: Double) { runtime.setValue(semanticsIdentifier: semanticsIdentifier, value: value) }
    override func _hostedFocus(semanticsIdentifier: Int?, keyboard: Bool) { runtime.focus(semanticsIdentifier: semanticsIdentifier, keyboard: keyboard) }
    override func _hostedBlur(semanticsIdentifier: Int) { runtime.blur(semanticsIdentifier: semanticsIdentifier) }
    override func _hostedTextField(_ semanticsIdentifier: Int, didChange text: String) { runtime.textField(semanticsIdentifier, didChange: text) }
    override func _hostedTextFieldDidSubmit(_ semanticsIdentifier: Int) { runtime.textFieldDidSubmit(semanticsIdentifier) }
    override func _hostedTextField(_ semanticsIdentifier: Int, focused: Bool) { runtime.textField(semanticsIdentifier, focused: focused) }
    override var _hostedFocusedTextFieldIdentifier: Int? { runtime.focusedTextFieldIdentifier }
    override func _hostedAdvanceFrame(elapsed: Double) -> Bool {
        let animating = runtime.advanceFrame(elapsed: elapsed)
        if animating || runtime.needsFrame { setNeedsDisplay() }
        return animating
    }
    override func _hostedScrollWheel(by delta: CGSize, at point: CGPoint) -> Bool {
        runtime.scroll(by: delta, at: point) != delta
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        runtime.pointerDown(at: touch.location(in: self), type: touch.type == .direct ? .touch : .mouse, time: touch.timestamp)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        runtime.pointerMoved(to: touch.location(in: self), time: touch.timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        runtime.pointerUp(at: touch.location(in: self), time: touch.timestamp)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        runtime.pointerUp(at: CGPoint(x: -1, y: -1), time: touches.first?.timestamp ?? 0)
    }
}
