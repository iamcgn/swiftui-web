import Observation

// The runtime's node tree mirrors the view *type* tree (Docs/ARCHITECTURE.md, invariant 1):
// every view value in a body is represented by one node whose class is chosen statically
// through `View._makeNode`. There is no AttributeGraph and no general diffing; identity is
// structural, and only `ForEach` reconciles by key.

/// A node in the runtime tree. Members are `package`; the class is public only because the
/// hidden `View._makeNode` hook must name it.
@MainActor
open class ViewNode {
    /// The runtime this node belongs to.
    package unowned let runtime: Runtime
    /// Animation state while a tween or transition runs (Runtime/AnimationNodes.swift).
    package var presentation: NodePresentation?
    /// Structural children removed under an animation that still paint their removal transition.
    package var exitingChildren: [ViewNode] = []
    package var hasBeenPlaced = false
    /// Set while the node lingers as a ghost through its removal transition.
    package var isExiting = false

    /// The structural parent, `nil` for the root.
    package private(set) weak var parent: ViewNode?

    /// Distance from the root. The scheduler updates dirty nodes top-down by depth.
    package let depth: Int

    /// The environment in which this node's view lives.
    package var environment: EnvironmentValues

    /// Set by `invalidate()`; cleared once the node has been updated.
    package private(set) var needsUpdate = false

    /// False once `unmount()` has run.
    package private(set) var isMounted = true

    /// Identifies the most recent body evaluation, so an `onChange` from a stale observation
    /// session (one armed by an earlier evaluation) does not invalidate the node again.
    package private(set) var observationToken = ObservationToken()

    // MARK: Layout state (meaningful for layout nodes only)

    /// The node's frame in the coordinate space of `layoutParent`'s bounds.
    package var frame: CGRect = .zero

    /// The layout node that placed this node (a container, a modifier, or the root).
    package private(set) weak var layoutParent: ViewNode?

    /// Orientation of the stack that contains this node directly, set by the container before
    /// measuring; `Spacer` and `Divider` read it. Modifier nodes forward it to their content.
    package var stackOrientation: Axis? {
        didSet { if stackOrientation != oldValue { stackOrientationDidChange() } }
    }

    /// Hook for nodes that wrap other layout nodes.
    package func stackOrientationDidChange() {}

    private var sizeCache: [ProposedViewSize: CGSize] = [:]
    private var sizeCacheGeneration: UInt64 = 0

    package init(parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.runtime = runtime
        self.parent = parent
        self.depth = (parent?.depth ?? -1) + 1
        self.environment = environment
    }

    // MARK: Invalidation

    /// Marks the node dirty and asks the scheduler for a flush; the transaction's animation, if
    /// any, is kept for the flush and layout that apply the change.
    package func invalidate() {
        guard isMounted else { return }
        if let transaction = Transaction._current, !transaction.disablesAnimations, let animation = transaction.animation {
            runtime.pendingAnimation = animation
        }
        guard !needsUpdate else { return }
        needsUpdate = true
        runtime.scheduler.schedule(self)
    }

    /// Re-runs this node's update from its stored view. Called by the scheduler.
    package func updateIfNeeded() {
        guard needsUpdate, isMounted else { return }
        performUpdate()
    }

    /// Subclasses re-evaluate from their stored state. Must call `clearNeedsUpdate()`.
    package func performUpdate() {
        clearNeedsUpdate()
    }

    package func clearNeedsUpdate() {
        needsUpdate = false
    }

    /// Starts a new observation session for this node; earlier sessions become stale.
    package func beginObservationSession() {
        observationToken = ObservationToken()
    }

    // MARK: Tree

    /// Children in structural order (for debugging and tree-shape tests).
    package var structuralChildren: [ViewNode] { [] }

    /// The nodes this subtree contributes to the enclosing layout container (invariant 2).
    /// Lists (`TupleView`, `Group`, `Optional`, `_ConditionalContent`, environment modifiers)
    /// contribute their children; layout-participating nodes contribute themselves.
    package var layoutChildren: [ViewNode] { [self] }

    /// Where this node's painted content sits relative to its frame (an `offset` effect moves
    /// hit testing with it).
    package var hitTestOffset: CGPoint { .zero }

    /// Whether points outside this node's bounds cannot hit its descendants (scroll views clip;
    /// other containers let offset or transformed children be hit where they paint).
    package var clipsHitTesting: Bool { false }

    /// Short description of the node for tree dumps.
    package var nodeDescription: String {
        String(describing: type(of: self))
    }

    /// Tears the subtree down. Subclasses unmount children first, then call super.
    package func unmount() {
        for child in structuralChildren { child.unmount() }
        isMounted = false
        needsUpdate = false
    }

    // MARK: Layout

    /// Whether this node occupies a slot in its container's layout (as opposed to contributing
    /// its children).
    package var isLayoutNode: Bool { false }

    /// The layout priority a containing stack uses to apportion space.
    package var layoutPriority: Double { 0 }

    /// The `zIndex` trait: a containing node paints its children in ascending order of this
    /// value (declaration order among equals) and hit tests them in the reverse.
    package var zIndex: Double { 0 }

    /// The preferred spacing to neighbours.
    package var layoutSpacing: ViewSpacing { ViewSpacing() }

    /// The value stored for a `LayoutValueKey`, or its default.
    package func layoutValue<K: LayoutValueKey>(for key: K.Type) -> K.Value { K.defaultValue }

    /// The size this node wants for `proposal`, memoised for the duration of one layout pass.
    package final func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let generation = runtime.layoutGeneration
        if sizeCacheGeneration != generation {
            sizeCache.removeAll(keepingCapacity: true)
            sizeCacheGeneration = generation
        }
        if let cached = sizeCache[proposal] { return cached }
        let size = computeSizeThatFits(proposal)
        sizeCache[proposal] = size
        return size
    }

    /// Layout nodes override this.
    package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        fatalError("\(nodeDescription) is not a layout node")
    }

    /// Size plus alignment guides for `proposal`. Default: no explicit guides.
    package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        ViewDimensions(size: sizeThatFits(proposal))
    }

    /// Positions this node: computes its size for `proposal`, records the frame relative to
    /// `placer`, then lays out its own contents.
    package final func place(at position: CGPoint, anchor: UnitPoint, proposal: ProposedViewSize, by placer: ViewNode) {
        let size = sizeThatFits(proposal)
        let previous = hasBeenPlaced ? presentedFrame : nil
        let oldTarget = frame
        layoutParent = placer
        frame = CGRect(x: position.x - size.width * anchor.x, y: position.y - size.height * anchor.y,
                       width: size.width, height: size.height)
        if let previous, frame != oldTarget {
            if let animation = runtime.effectiveLayoutAnimation(for: self) {
                beginFrameTween(from: previous, animation: animation)
            } else {
                presentation?.frame = nil
            }
        }
        hasBeenPlaced = true
        layoutContents(proposal: proposal)
    }

    /// Lays out children inside `CGRect(origin: .zero, size: frame.size)`. Layout nodes with
    /// children override this.
    package func layoutContents(proposal: ProposedViewSize) {}

    /// This node's frame in the root's coordinate space, following the chain of placers.
    package var frameInRoot: CGRect {
        var origin = frame.origin
        var ancestor = layoutParent
        while let node = ancestor, node.parent != nil || node.layoutParent != nil {
            origin.x += node.frame.origin.x
            origin.y += node.frame.origin.y
            ancestor = node.layoutParent
        }
        return CGRect(origin: origin, size: frame.size)
    }

    // MARK: Preferences

    /// The subtree's value for `key`, or `nil` if nothing in it writes the key.
    package func preferenceValue<K: PreferenceKey>(for key: K.Type) -> K.Value? {
        var result: K.Value?
        for child in structuralChildren {
            guard let value = child.preferenceValue(for: key) else { continue }
            if result == nil {
                result = value
            } else {
                K.reduce(value: &result!, nextValue: { value })
            }
        }
        return transformPreference(key, result)
    }

    /// Hook for nodes that write or transform a preference. Default: pass through.
    package func transformPreference<K: PreferenceKey>(_ key: K.Type, _ value: K.Value?) -> K.Value? {
        value
    }

    // MARK: Painting

    /// Emits this node's drawing (self first, then children). Only layout nodes are painted; a
    /// placer paints the nodes it placed at their frames.
    package func paint(into list: inout DisplayList, context: PaintContext) {
        let opacity = presentedTransitionOpacity
        guard opacity > 0 else { return }
        if opacity < 1 { list.append(.beginGroup(opacity: opacity)) }
        let scale = presentedTransitionScale
        if scale != 1 {
            let size = presentedFrame.size
            let centre = CGPoint(x: context.origin.x + size.width / 2, y: context.origin.y + size.height / 2)
            list.append(.save)
            list.append(.concat(CGAffineTransform(translationX: -centre.x, y: -centre.y).concatenating(CGAffineTransform(scaleX: scale, y: scale))
                                    .concatenating(CGAffineTransform(translationX: centre.x, y: centre.y))))
        }
        if context.effects.isEmpty {
            paintSelf(into: &list, context: context)
        } else {
            context.withEffects(absoluteBounds(context), into: &list) { paintSelf(into: &$0, context: context) }
        }
        paintChildren(into: &list, context: context)
        paintExiting(into: &list, context: context)
        if scale != 1 { list.append(.restore) }
        if opacity < 1 { list.append(.endGroup) }
    }

    /// Ghosts of removed subtrees still animating out, at the frames they last had.
    package func paintExiting(into list: inout DisplayList, context: PaintContext) {
        for ghost in collectExiting() {
            ghost.paint(into: &list, context: context.child(at: ghost.presentedFrame))
        }
    }

    /// This node's own drawing, before its children.
    package func paintSelf(into list: inout DisplayList, context: PaintContext) {}

    /// The layout nodes this node placed, painted at their frames. Default: none.
    package var paintedChildren: [ViewNode] { [] }

    /// `paintedChildren` in painting order: stable-sorted by `zIndex`.
    package var paintOrderedChildren: [ViewNode] {
        let children = paintedChildren
        guard children.contains(where: { $0.zIndex != 0 }) else { return children }
        return children.enumerated().sorted { a, b in
            a.element.zIndex != b.element.zIndex ? a.element.zIndex < b.element.zIndex : a.offset < b.offset
        }.map(\.element)
    }

    package func paintChildren(into list: inout DisplayList, context: PaintContext) {
        for child in paintOrderedChildren {
            let frame = child.presentedFrame
            if let visible = context.visibleRect, !child.paintsOutsideFrame, frame.width > 0, frame.height > 0,
               !frame.offsetBy(dx: context.origin.x, dy: context.origin.y).intersects(visible) {
                continue
            }
            child.paint(into: &list, context: context.child(at: frame))
        }
    }

    /// Whether this node's painting can reach beyond its frame (offsets, transforms): such
    /// nodes are never culled by a scroll view's viewport.
    package var paintsOutsideFrame: Bool { false }

    /// Whether this node takes hits before its children (`highPriorityGesture`).
    package var capturesHitTesting: Bool { false }

    /// Whether this node is a `Spacer`: stacks size it after every other child, from the leftover
    /// (Layout/StackLayout.swift).
    package var isSpacer: Bool { false }

    // MARK: Safe area

    /// Whether this node keeps the full bounds under a safe-area modifier and insets its own
    /// content instead (scroll views, `ignoresSafeArea`). Wrapper nodes forward their child's.
    package var extendsIntoSafeArea: Bool { false }

    /// Whether a safe area passes through this node to its child: true for nodes that do not
    /// change their child's size (non-layout wrappers, painting modifiers); false for layout
    /// modifiers such as frames and padding, whose child gets a fresh safe area.
    package var forwardsSafeArea: Bool { !isLayoutNode }

    /// The safe-area insets the nearest providing ancestor gives this node (through forwarding
    /// wrappers), or none.
    package var inheritedSafeAreaInsets: EdgeInsets {
        var node: ViewNode = self
        while let parent = node.parent {
            if let provider = parent as? _SafeAreaProvider { return provider.safeAreaInsets(for: node) }
            guard parent.forwardsSafeArea else { break }
            node = parent
        }
        return EdgeInsets()
    }

    /// Whether this node reads its own geometry during layout (GeometryReader, probes): a scroll
    /// view holding one lays its content out on every scroll frame instead of moving it.
    package var readsGeometry: Bool { false }

    /// Moves a placed node without laying it out again (a scroll frame whose content is unchanged).
    package final func moveFrame(toOrigin origin: CGPoint) {
        frame.origin = origin
    }

    /// This node's own bounds (the presented size while animating), pixel aligned, in absolute
    /// coordinates.
    package func absoluteBounds(_ context: PaintContext) -> CGRect {
        context.absoluteRect(CGRect(origin: .zero, size: presentedFrame.size))
    }

    /// Indented dump of the subtree, one node per line, for tests and debugging.
    package func dump(indent: Int = 0) -> String {
        var lines = [String(repeating: "  ", count: indent) + nodeDescription]
        for child in structuralChildren {
            lines.append(child.dump(indent: indent + 1))
        }
        return lines.joined(separator: "\n")
    }
}

/// A node whose view type is known statically. `View._makeNode` returns one of these so parents
/// can push new view values to their children without casts.
@MainActor
open class TypedNode<V: View>: ViewNode {
    /// The most recent view value.
    package var view: V

    package init(view: V, parent: ViewNode?, runtime: Runtime, environment: EnvironmentValues) {
        self.view = view
        super.init(parent: parent, runtime: runtime, environment: environment)
    }

    /// Receives a new view value from the parent. `force` is set when the parent knows the
    /// subtree must be re-evaluated regardless of equality (for example after `invalidate()`).
    package func update(view: V, environment: EnvironmentValues, force: Bool = false) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
    }

    override package func performUpdate() {
        update(view: view, environment: environment, force: true)
    }

    override package var nodeDescription: String {
        _shortTypeName(type(of: self))
    }
}

/// The information `View._makeNode` receives to build a node.
public struct _NodeContext<V: View> {
    package let view: V
    package let parent: ViewNode
    package let environment: EnvironmentValues

    package init(view: V, parent: ViewNode, environment: EnvironmentValues) {
        self.view = view
        self.parent = parent
        self.environment = environment
    }

    package var runtime: Runtime { parent.runtime }
}

extension View {
    /// Hidden hook: builds the runtime node for a view value and performs its first update.
    /// Composite views get a `CompositeNode`; primitive views override this.
    public static func _makeNode(_ context: _NodeContext<Self>) -> TypedNode<Self> {
        CompositeNode(context)
    }
}

extension Never {
    public static func _makeNode(_ context: _NodeContext<Never>) -> TypedNode<Never> {
        switch context.view {}
    }
}

/// Node for a view with a `body`: evaluates it and keeps one child for `V.Body`.
@MainActor
package final class CompositeNode<V: View>: TypedNode<V> {
    package private(set) var child: TypedNode<V.Body>?

    /// Number of body evaluations, for tests.
    package private(set) var bodyEvaluations = 0

    /// Storage for the view's dynamic properties (`@State` boxes and the like).
    package private(set) var propertyStorage: AnyObject?

    package init(_ context: _NodeContext<V>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        evaluateBody()
    }

    override package func update(view: V, environment: EnvironmentValues, force: Bool) {
        let changed = force || needsUpdate
            || _valuesDiffer(self.view, view)
            || self.environment.generation != environment.generation
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if changed { evaluateBody() }
    }

    private func evaluateBody() {
        bodyEvaluations += 1
        _DynamicPropertyFields<V>.installAll(into: &view, node: self, slot: &propertyStorage)
        let body = _trackingObservation(for: self) { view.body }
        if let child {
            child.update(view: body, environment: environment)
        } else {
            child = V.Body._makeNode(_NodeContext(view: body, parent: self, environment: environment))
        }
    }

    override package var structuralChildren: [ViewNode] { child.map { [$0] } ?? [] }
    override package var layoutChildren: [ViewNode] { child?.layoutChildren ?? [] }
}

// MARK: - Observation

/// Evaluates `body` while recording every `@Observable` property it reads; the first later
/// mutation of any of them invalidates `node`. Tracking is re-armed by the next evaluation, so
/// a node only ever depends on what its most recent body actually read.
@MainActor
package func _trackingObservation<Result>(for node: ViewNode, _ body: () -> Result) -> Result {
    node.beginObservationSession()
    let token = node.observationToken
    return withObservationTracking(body) { [weak node] in
        // Observation calls this from the property's `willSet`, on the mutating thread. State
        // mutation is main-actor only in SwiftUI and here, so hop synchronously. The node is held
        // weakly: a task finishing after its tree was torn down must not revive a dead node (whose
        // runtime is unowned).
        MainActor.assumeIsolated {
            guard let node, token.isCurrent(for: node) else { return }
            node.invalidate()
        }
    }
}

/// A fresh identity per observation session.
package final class ObservationToken: Sendable {
    package init() {}

    @MainActor
    package func isCurrent(for node: ViewNode) -> Bool {
        node.observationToken === self && node.isMounted
    }
}

// MARK: - Change detection

/// Whether two view values differ. Equatable types compare with `==`; plain-old-data types
/// compare bitwise; anything else (closures, existentials) is assumed to have changed.
package func _valuesDiffer<T>(_ old: T, _ new: T) -> Bool {
    if let equatable = T.self as? any Equatable.Type {
        return !_openEquatable(equatable, old, new)
    }
    if _isPOD(T.self) {
        return withUnsafeBytes(of: old) { a in
            withUnsafeBytes(of: new) { b in
                !a.elementsEqual(b)
            }
        }
    }
    return true
}

private func _openEquatable<E: Equatable>(_: E.Type, _ a: Any, _ b: Any) -> Bool {
    (a as! E) == (b as! E)
}

/// Strips module and private-context qualifiers from a type description, inside generic
/// arguments too: `Module.(unknown context at $1).Outer.Inner<Module.Arg>` → `Inner<Arg>`.
package func _shortTypeName(_ type: Any.Type) -> String {
    let full = Array(String(describing: type))
    var out = ""
    var token = ""
    var index = 0
    func flushToken() {
        if let dot = token.lastIndex(of: ".") {
            out += token[token.index(after: dot)...]
        } else {
            out += token
        }
        token = ""
    }
    while index < full.count {
        let character = full[index]
        if character == "(" {
            // Drop `(unknown context at $…)` and `(extension in Module)` qualifiers entirely.
            if let close = full[index...].firstIndex(of: ")"),
               String(full[index...close]).hasPrefix("(unknown context") ||
               String(full[index...close]).hasPrefix("(extension in")
            {
                index = close + 1
                continue
            }
        }
        if character.isLetter || character.isNumber || character == "_" || character == "." || character == "$" {
            token.append(character)
        } else {
            flushToken()
            out.append(character)
        }
        index += 1
    }
    flushToken()
    return out
}

/// A node that defines the safe area of its child (`safeAreaInset`, `safeAreaPadding`,
/// `ignoresSafeArea`).
@MainActor
package protocol _SafeAreaProvider: AnyObject {
    func safeAreaInsets(for child: ViewNode) -> EdgeInsets
}
