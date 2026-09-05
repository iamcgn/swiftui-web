/// Owns one mounted view tree, its scheduler and (from step 9) the layout and painting
/// pipeline. Hosts (canvas, headless) create one runtime per window.
@MainActor
public final class Runtime {
    package let scheduler = UpdateScheduler()
    package private(set) var root: RootNode!

    /// Measures and breaks text. Hosts install their engine before the first layout.
    public var textEngine: any TextEngine = ZeroTextEngine() {
        didSet { textLayouts.removeAll() }
    }

    /// Finished text layouts by their inputs, kept across frames: a scroll or an unrelated state
    /// change lays the whole tree out again, and line breaking every text on a page each frame
    /// dominated frame times (1.2 s on the landing page). Bounded by size, cleared when the
    /// engine changes.
    private var textLayouts: [TextLayoutKey: TextLayout] = [:]
    private struct TextLayoutKey: Hashable {
        let runs: [StyledRun]
        let options: TextLayoutOptions
        let width: CGFloat?
    }

    /// `textEngine.layout` through the cross-frame cache.
    package func layoutText(_ runs: [StyledRun], options: TextLayoutOptions, width: CGFloat?) -> TextLayout {
        let key = TextLayoutKey(runs: runs, options: options, width: width)
        if let cached = textLayouts[key] { return cached }
        if textLayouts.count >= 8192 { textLayouts.removeAll(keepingCapacity: true) }
        let layout = textEngine.layout(runs, options: options, width: width)
        textLayouts[key] = layout
        return layout
    }

    /// A single string in one font through the cache.
    package func layoutText(_ string: String, font: ResolvedFont, width: CGFloat?) -> TextLayout {
        layoutText([StyledRun(string, font: font)], options: .default, width: width)
    }

    /// Environment the root view is mounted in.
    package var rootEnvironment: EnvironmentValues
    /// The last `navigationTitle` applied in the tree, for hosts (window or document title).
    public internal(set) var navigationTitle: String?

    /// The system appearance, set by hosts; the root environment follows it unless the tree
    /// prefers one (`preferredColorScheme`).
    public var hostColorScheme: ColorScheme = .light {
        didSet { if hostColorScheme != oldValue { requestLayout() } }
    }
    /// The `preferredColorScheme` in the tree, if any.
    package var preferredColorScheme: ColorScheme? {
        didSet { if preferredColorScheme != oldValue { requestLayout() } }
    }
    /// The scheme the window shows: the preferred one, else the host's. Hosts paint their
    /// background with it (`paintsWindowBackground`).
    public var effectiveColorScheme: ColorScheme { rootEnvironment.colorScheme }
    /// Whether `render` starts with the window background (hosts: yes; fixtures and tests: no,
    /// their goldens are transparent).
    public var paintsWindowBackground = false

    /// Whether the runtime draws window chrome a browser page lacks: the toolbar
    /// (`Runtime/ToolbarNodes.swift`). Hosts with a real title bar leave it off or keep the title
    /// out of the bar (`chromeShowsTitle`).
    public var paintsWindowChrome = false
    public var chromeShowsTitle = true
    package var toolbarSources: [ToolbarSource] = []
    package var toolbarVisibility: [ToolbarVisibilitySource] = []
    package var toolbar: ToolbarChromeNode?
    package var searchSources: [SearchSource] = []
    package var _imageLoader: (any _ImageLoading)?
    package var asyncImageNodes: [WeakAsyncImageNode] = []

    // Animation (Runtime/AnimationNodes.swift)
    /// Seconds of animation time, advanced by hosts through `advanceAnimations(elapsed:)`.
    package var animationClock: Double = 0
    /// The transaction animation recorded when state changed; consumed by the next layout.
    package var pendingAnimation: Animation?
    /// The animation in effect while nodes update (transitions, opacity and colour changes).
    package var updateAnimation: Animation?
    /// The animation in effect while nodes are placed (frame changes).
    package var layoutAnimation: Animation?
    package var isLayingOut = false
    package var activeAnimationScopes = 0
    package var animatingNodes: [WeakNode] = []

    /// Sheets, popovers, alerts and menus over the window, bottom to top (Runtime/PresentationNodes.swift).
    package var presentations: [PresentationNode] = []
    /// The app's pasteboard (Runtime/PasteboardNodes.swift) and the host's clipboard writer for text.
    package var pasteboard: [_TransferItem] = []
    public var clipboardWriter: ((String) -> Void)?
    /// Window scenes and the secondary windows opened from them (Runtime/WindowNodes.swift).
    package var windowDescriptors: [_WindowDescriptor] = []
    package var openWindows: [OpenWindow] = []
    package var nextWindowIdentity = 1
    /// Drag and drop (Runtime/DragDropNodes.swift): the drag in progress and the source a press may lift.
    package var dragSession: DragSession?
    package var pendingDrag: (source: ViewNode & _DragSource, start: CGPoint)?
    /// Frames recorded by `matchedGeometryEffect` sources (Runtime/MatchedGeometryNodes.swift).
    package var matchedGeometry: [MatchedGeometryKey: MatchedGeometryRecord] = [:]
    /// Timeline views re-rendering every frame (Runtime/TimelineNodes.swift).
    package var frameSubscribers: [WeakFrameSubscriber] = []
    /// Focus states told when the focused text field changes (Runtime/FocusNodes.swift).
    package var focusBoxes: [WeakFocusBox] = []

    private let assetStore = _AssetStore()

    /// The app's asset catalogs (images and colours by name). Hosts install theirs before the
    /// first layout; replacing it later re-evaluates the mounted tree.
    public var assetCatalog: AssetCatalog {
        get { assetStore.catalog }
        set {
            assetStore.catalog = newValue
            root.child?.invalidate()
        }
    }

    public init(environment: EnvironmentValues = EnvironmentValues()) {
        var environment = environment
        environment[AssetStoreKey.self] = assetStore
        self.rootEnvironment = environment
        hostColorScheme = environment.colorScheme
        self.root = RootNode(runtime: self, environment: environment)
        installPasteboard()
    }

    /// Moves the root environment to the effective scheme when it changed, re-applying the
    /// root view so every node resolves its colours again.
    private func applyColorScheme() {
        let effective = preferredColorScheme ?? hostColorScheme
        guard effective != rootEnvironment.colorScheme else { return }
        rootEnvironment.colorScheme = effective
        root.environment = rootEnvironment
        root.reapply?(rootEnvironment)
        sizesInvalidated = true
        layoutGeneration += 1
    }

    /// Asks the host for another frame without a state change (an image finished loading).
    public func setNeedsDisplay() {
        requestLayout()
    }

    /// Mounts `view` as the root, replacing any previous root view.
    @discardableResult
    public func mount<V: View>(_ view: V) -> TypedNode<V> {
        // A root replaced or updated outside the scheduler changes sizes like any update would.
        sizesInvalidated = true
        return root.mount(view)
    }

    /// Applies pending invalidations (top-down by depth). Hosts call this once per frame.
    package func flush() {
        scheduler.flush()
    }

    /// Incremented at the start of every layout pass; size caches are keyed by it.
    package private(set) var layoutGeneration: UInt64 = 0

    /// Counts the layout passes that walked the tree (not the ones that only moved scrolled
    /// content); the semantics tree is cached against it (`semanticsTree()`).
    package private(set) var fullLayoutCount: UInt64 = 0
    package var semanticsCache: [SemanticsEntry] = []
    package var semanticsCacheLayout: UInt64 = .max
    /// Whether the cached semantics tree still describes the nodes: no full layout since it was
    /// walked, and no state update or invalidation waiting for the next one (a typed character
    /// or a slider press changes a binding before any layout runs).
    package var semanticsCacheIsValid: Bool {
        semanticsCacheLayout == fullLayoutCount && !scheduler.hasPendingWork && !sizesInvalidated
    }

    /// The size most recently laid out into.
    package private(set) var layoutSize: CGSize = .zero

    /// Frames recorded by `_probe` modifiers during the most recent layout pass.
    public internal(set) var probeFrames: [String: CGRect] = [:]

    /// `onPreferenceChange` nodes, evaluated after each layout pass.
    package var preferenceObservers: [WeakObserver] = []

    /// The interactive node a pointer is currently pressing, and the last pointer position.
    package var pressedNode: (ViewNode & _Interactive)?

    /// The text field with keyboard focus (its semantics identifier), for the focus ring.
    public internal(set) var focusedTextFieldIdentifier: Int?
    /// The element with keyboard focus (any interactive or focusable view; a focused text field
    /// sets both), and whether the focus ring shows (Runtime/KeyboardNodes.swift).
    public internal(set) var focusedIdentifier: Int?
    public internal(set) var focusVisible = false
    package var pointerPosition: CGPoint = .zero
    /// The host's time (seconds) of the last pointer event, for gesture timing.
    package var lastPointerTime: Double = 0

    /// Hover state (Runtime/HoverNodes.swift): the nodes the pointer is over, the memoised
    /// tracking nodes, a pending or shown tooltip and the pointer style hosts apply.
    package var hovered: [ViewNode & _HoverTracking] = []
    package var hoverNodes: [ViewNode & _HoverTracking] = []
    package var hoverNodesGeneration: UInt64 = .max
    package var tooltip: TooltipState?
    /// The pointer style of the deepest hovered `pointerStyle` view, for the host's cursor.
    public private(set) var pointerStyle: PointerStyle?
    package func setPointerStyle(_ style: PointerStyle?) { pointerStyle = style }

    package func forgetHover(_ node: ViewNode) {
        hovered.removeAll { $0 === node }
    }

    /// A touch pan of scroll views in progress.
    package var pan: PanState?

    /// Scroll views with momentum or fading indicators (`advanceScrollAnimations`).
    package var animatingScrollNodes: [ViewNode & _Scrollable] = []

    /// Set when geometry changed without a state update (scrolling, `scrollTo`): the next frame
    /// must lay out again. Cleared by `layout(in:)`.
    public private(set) var layoutRequested = false

    /// Whether the host should produce another frame.
    public var needsFrame: Bool { scheduler.hasPendingWork || layoutRequested || tooltipPending }

    /// Whether the next layout may find different sizes: state updates, image loads and resizes
    /// say so; a scroll only moves content, so the memoised sizes stay valid across its frames.
    private var sizesInvalidated = true

    /// Scroll views whose offset changed since the last layout: when nothing else changed, the
    /// next frame moves their content instead of laying the tree out.
    private var scrolledNodes: [ViewNode & _Scrollable] = []

    package func noteScrolled(_ node: ViewNode & _Scrollable) {
        if !scrolledNodes.contains(where: { $0 === node }) { scrolledNodes.append(node) }
    }

    package func requestLayout(invalidatingSizes: Bool = true) {
        if invalidatingSizes { sizesInvalidated = true }
        guard !layoutRequested else { return }
        layoutRequested = true
        if !scheduler.hasPendingWork { scheduler.onNeedsFlush?() }
    }

    /// Applies pending updates, then lays the tree out in a window of `size`. As in SwiftUI,
    /// the root view is proposed the full size and centred.
    public func layout(in size: CGSize) {
        updateAnimation = pendingAnimation
        if scheduler.hasPendingWork || size != layoutSize || pendingAnimation != nil || isAnimating { sizesInvalidated = true }
        // A frame that only scrolled moves the scrolled content and keeps every frame else.
        if !sizesInvalidated, presentations.isEmpty, scrolledNodes.allSatisfy(\.canMoveContentOnly) {
            for node in scrolledNodes { node.moveContent() }
            scrolledNodes.removeAll()
            layoutRequested = false
            updateAnimation = nil
            return
        }
        scrolledNodes.removeAll()
        fullLayoutCount += 1
        flush()
        applyColorScheme()
        layoutRequested = false
        // The generation keys every node's size memo: a frame that only scrolled keeps it.
        if sizesInvalidated { layoutGeneration += 1 }
        sizesInvalidated = false
        layoutAnimation = pendingAnimation
        pendingAnimation = nil
        isLayingOut = true
        layoutSize = size
        probeFrames.removeAll(keepingCapacity: true)
        root.frame = CGRect(origin: .zero, size: size)
        layoutToolbar(in: size)
        let top = toolbar?.frame.height ?? 0
        let content = CGSize(width: size.width, height: max(0, size.height - top))
        for node in root.layoutChildren {
            node.place(at: CGPoint(x: content.width / 2, y: top + content.height / 2), anchor: .center,
                       proposal: ProposedViewSize(content), by: root)
        }
        layoutPresentations(in: size)
        isLayingOut = false
        layoutAnimation = nil
        updateAnimation = nil
        deliverPreferences()
    }

    /// Runs every live `onPreferenceChange` action whose value changed in this pass.
    package func deliverPreferences() {
        preferenceObservers.removeAll { $0.node == nil || $0.node?.isMounted == false }
        for observer in preferenceObservers {
            observer.node?.evaluatePreference()
        }
    }
}

/// The parentless node at the top of the tree. Holds the mounted root view's node.
@MainActor
package final class RootNode: ViewNode {
    package private(set) var child: ViewNode?
    /// Re-applies the mounted view under a new root environment (a colour scheme change).
    package private(set) var reapply: ((EnvironmentValues) -> Void)?

    package init(runtime: Runtime, environment: EnvironmentValues) {
        super.init(parent: nil, runtime: runtime, environment: environment)
    }

    fileprivate func mount<V: View>(_ view: V) -> TypedNode<V> {
        if let existing = child as? TypedNode<V> {
            existing.update(view: view, environment: environment)
            reapply = { [weak existing] environment in existing?.update(view: view, environment: environment, force: true) }
            return existing
        }
        child?.unmount()
        let node = V._makeNode(_NodeContext(view: view, parent: self, environment: environment))
        child = node
        reapply = { [weak node] environment in node?.update(view: view, environment: environment, force: true) }
        return node
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
    override package var nodeDescription: String { "Root" }
}

/// Collects invalidated nodes and updates them in depth order so that a parent's update, which
/// already refreshes its subtree, makes the children's own pending updates unnecessary.
@MainActor
package final class UpdateScheduler {
    private var dirty: [ObjectIdentifier: ViewNode] = [:]

    /// Actions to run after the next batch of updates (`onChange`, `initial` actions).
    private var actions: [@MainActor () -> Void] = []

    /// Called the first time work becomes pending after an idle period. Hosts use it to request
    /// an animation frame; headless callers flush explicitly.
    package var onNeedsFlush: (@MainActor () -> Void)?

    /// Number of `flush` calls that did work, for tests.
    package private(set) var flushCount = 0

    package var hasPendingWork: Bool { !dirty.isEmpty || !actions.isEmpty }

    package init() {}

    package func schedule(_ node: ViewNode) {
        let wasIdle = !hasPendingWork
        dirty[ObjectIdentifier(node)] = node
        if wasIdle { onNeedsFlush?() }
    }

    /// Runs `action` once the pending updates have been applied, in the same flush.
    package func enqueue(_ action: @escaping @MainActor () -> Void) {
        let wasIdle = !hasPendingWork
        actions.append(action)
        if wasIdle { onNeedsFlush?() }
    }

    package func flush() {
        guard hasPendingWork else { return }
        flushCount += 1
        var passes = 0
        while hasPendingWork {
            passes += 1
            precondition(passes < 1000, "UpdateScheduler: updates keep invalidating nodes; giving up")
            let batch = dirty.values.sorted { $0.depth < $1.depth }
            dirty.removeAll(keepingCapacity: true)
            for node in batch {
                node.updateIfNeeded()
            }
            let pending = actions
            actions.removeAll()
            for action in pending { action() }
        }
    }
}
