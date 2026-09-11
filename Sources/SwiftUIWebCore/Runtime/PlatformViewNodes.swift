// Hosting another framework's view tree as one leaf of the SwiftUI tree (decision 0014,
// Phase 2): `UIViewRepresentable` and `UIViewControllerRepresentable` in SwiftUIWebUIKit build a
// `_PlatformViewHostNode` over a `_PlatformViewTree`. The node owns the SwiftUI side (its slot
// in the layout, its frame, the memoised size, painting position, the press routed to it, its
// place in the semantics walk); the tree owns what is inside. Points cross the seam in the
// tree's own space, with the origin at the node's top left.

/// What a hosted tree provides to its node.
@MainActor
package protocol _PlatformViewTree: AnyObject {
    /// A view inside changed something the host must lay out again for (an intrinsic size, a
    /// frame, a colour). Set by the node.
    var onNeedsFrame: (@MainActor () -> Void)? { get set }
    /// The text field inside with keyboard focus changed (nil: none). Set by the node.
    var onFocusedTextFieldChange: (@MainActor (Int?) -> Void)? { get set }

    /// Gives the tree the runtime's services before it measures or paints (the text engine that
    /// answers the host's strings, the app's asset catalog).
    func prepare(textEngine: any TextEngine, assetCatalog: AssetCatalog)
    /// Lays the tree out in `size`.
    func layout(size: CGSize, colorScheme: ColorScheme)
    /// The first and last text baselines of the content laid out in `size`, from its top.
    func baselines(in size: CGSize) -> (first: CGFloat, last: CGFloat)
    /// Paints the tree; `context.origin` is the tree's origin in absolute coordinates.
    func paint(into list: inout DisplayList, context: PaintContext)
    /// Advances the tree's clocks by `elapsed` seconds; true means it needs another frame.
    func advanceFrame(elapsed: Double) -> Bool

    func pointerDown(at point: CGPoint, type: PointerType, time: Double)
    func pointerMoved(to point: CGPoint, time: Double)
    func pointerUp(at point: CGPoint, time: Double)
    /// The host's own scrolling took the press.
    func pointerCancelled(at point: CGPoint, time: Double)
    /// The axes a press at `point` may drag along without becoming a pan of the host's scroll
    /// views (a scroll view inside the tree).
    func dragAxes(at point: CGPoint) -> Axis.Set
    /// A wheel scroll at `point`; returns whether the tree consumed it.
    func scrollWheel(by delta: CGSize, at point: CGPoint) -> Bool

    /// The tree's accessibility elements, frames in the tree's coordinates.
    func semantics() -> [SemanticsNode]
    func contains(semanticsIdentifier: Int) -> Bool
    func activate(semanticsIdentifier: Int)
    func adjust(semanticsIdentifier: Int, increment: Bool)
    func setValue(semanticsIdentifier: Int, value: Double)
    func focus(semanticsIdentifier: Int)
    func blur(semanticsIdentifier: Int)
    /// The text field inside with keyboard focus.
    var focusedTextFieldIdentifier: Int? { get }
    /// Keyboard focus moved out of the tree.
    func resignFocus()
    func textField(_ semanticsIdentifier: Int, didChange text: String)
    func textFieldDidSubmit(_ semanticsIdentifier: Int)
    func textField(_ semanticsIdentifier: Int, focused: Bool)

    /// The node was unmounted: the tree comes down.
    func dismantle()
}

/// Type-erased access to a host node for the runtime's routing.
@MainActor
package protocol _PlatformViewHosting: AnyObject {
    var tree: any _PlatformViewTree { get }
}

/// The leaf that stands for a hosted tree in the SwiftUI layout.
@MainActor
package final class _PlatformViewHostNode<V: View>: LeafNode<V>, _Interactive, _PlatformViewHosting, _FocusBoxObserving {
    package let tree: any _PlatformViewTree
    /// The size the tree wants for a proposal (the representable's own `sizeThatFits`, else the
    /// framework's rule for the hosted view).
    private let sizing: @MainActor (ProposedViewSize, V, EnvironmentValues) -> CGSize
    /// Pushes the view value into the hosted content (`updateUIView`).
    private let updateContent: @MainActor (V, EnvironmentValues) -> Void
    private let identifier: Int
    private var lastPressPoint = CGPoint.zero
    /// The environment generation the content was last updated for.
    private var updatedGeneration: UInt64?

    package init(_ context: _NodeContext<V>, tree: any _PlatformViewTree,
                 sizing: @escaping @MainActor (ProposedViewSize, V, EnvironmentValues) -> CGSize,
                 update: @escaping @MainActor (V, EnvironmentValues) -> Void) {
        self.tree = tree
        self.sizing = sizing
        self.updateContent = update
        identifier = _nextGestureIdentifier()
        super.init(context)
        runtime.registerPlatformHost(self)
        runtime.registerFocusBox(self)
        tree.onNeedsFrame = { [weak self] in self?.treeNeedsFrame() }
        tree.onFocusedTextFieldChange = { [weak self] identifier in self?.treeFocusedTextFieldDidChange(to: identifier) }
        prepareTree()
        pushContent()
    }

    private func prepareTree() {
        tree.prepare(textEngine: runtime.textEngine, assetCatalog: runtime.assetCatalog)
    }

    /// Runs the representable's update with observation tracking, as a body evaluation: the
    /// `@Observable` properties it reads invalidate the node when they change.
    private func pushContent() {
        _trackingObservation(for: self) { updateContent(view, environment) }
        updatedGeneration = environment.generation
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate || _valuesDiffer(self.view, view) || updatedGeneration != environment.generation
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { pushContent() }
    }

    override package func unmount() {
        tree.dismantle()
        runtime.forgetPlatformHost(self)
        super.unmount()
    }

    override package var nodeDescription: String { "PlatformView(\(_shortTypeName(V.self)))" }

    // MARK: Layout and painting

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        prepareTree()
        return sizing(proposal, view, environment)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        tree.layout(size: frame.size, colorScheme: environment.colorScheme)
    }

    /// The hosted content's baselines are the representable's alignment guides.
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        let size = sizeThatFits(proposal)
        let baselines = tree.baselines(in: size)
        return ViewDimensions(size: size, explicit: [
            VerticalAlignment.firstTextBaseline.key: baselines.first,
            VerticalAlignment.lastTextBaseline.key: baselines.last,
        ])
    }

    override package func paintSelf(into list: inout DisplayList, context: PaintContext) {
        tree.paint(into: &list, context: context)
    }

    /// A change inside the tree: the sizes may differ, so the next frame lays out again.
    private func treeNeedsFrame() {
        guard isMounted, !runtime.isLayingOut else { return }
        runtime.requestLayout()
    }

    // MARK: Interaction

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) {
        lastPressPoint = point
        tree.pointerDown(at: point, type: runtime.lastPointerType, time: runtime.lastPointerTime)
    }
    package func pressMoved(to point: CGPoint) { tree.pointerMoved(to: point, time: runtime.lastPointerTime) }
    package func pressEnded(inside: Bool) {}
    package func pressEnded(inside: Bool, at point: CGPoint) { tree.pointerUp(at: point, time: runtime.lastPointerTime) }
    package func pressCancelled(at point: CGPoint) { tree.pointerCancelled(at: point, time: runtime.lastPointerTime) }
    package var dragAxes: Axis.Set { tree.dragAxes(at: lastPressPoint) }

    /// The whole tree as one element (the semantics walk lists the tree's own elements instead).
    package var semantics: SemanticsNode {
        SemanticsNode(role: .group, label: "", frame: frameInRoot, identifier: identifier)
    }

    /// The tree's elements in window coordinates, with the frames they have inside the tree.
    package var semanticsEntries: [SemanticsEntry] {
        let origin = frameInRoot.origin
        return tree.semantics().map { element in
            var moved = element
            moved.frame = element.frame.offsetBy(dx: origin.x, dy: origin.y)
            if var input = moved.textInput {
                input.textRect = input.textRect.offsetBy(dx: origin.x, dy: origin.y)
                moved.textInput = input
            }
            return SemanticsEntry(node: self, element: moved, relativeFrame: element.frame)
        }
    }

    // MARK: Focus

    private func treeFocusedTextFieldDidChange(to identifier: Int?) {
        guard isMounted else { return }
        if let identifier {
            runtime.focusTextField(identifier)
        } else if let focused = runtime.focusedTextFieldIdentifier, tree.contains(semanticsIdentifier: focused) {
            runtime.focusTextField(nil)
        }
    }

    package func focusDidChange(to identifier: Int?) {
        if let identifier, tree.contains(semanticsIdentifier: identifier) { return }
        tree.resignFocus()
    }
}

extension Runtime {
    package func registerPlatformHost(_ node: any _PlatformViewHosting) {
        platformHosts.removeAll { $0.node == nil }
        platformHosts.append(WeakPlatformHost(node: node))
    }

    package func forgetPlatformHost(_ node: any _PlatformViewHosting) {
        platformHosts.removeAll { $0.node == nil || $0.node === node }
    }

    /// The hosted tree whose elements include `identifier`, if any.
    package func platformTree(handling identifier: Int) -> (any _PlatformViewTree)? {
        for entry in platformHosts {
            if let node = entry.node, node.tree.contains(semanticsIdentifier: identifier) { return node.tree }
        }
        return nil
    }

    /// Advances every hosted tree's clocks; true means one needs another frame.
    package func advancePlatformHosts(elapsed: Double) -> Bool {
        var animating = false
        for entry in platformHosts {
            if entry.node?.tree.advanceFrame(elapsed: elapsed) == true { animating = true }
        }
        return animating
    }
}

package struct WeakPlatformHost {
    package weak var node: (any _PlatformViewHosting)?
}
