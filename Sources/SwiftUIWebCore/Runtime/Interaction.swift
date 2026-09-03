// Hit testing and pointer handling live entirely in Swift (decision 0002): hosts forward raw
// pointer events in points; the runtime finds the deepest interactive node under the point.

/// A layout node that reacts to pointer input.
@MainActor
package protocol _Interactive: AnyObject {
    /// Called when a press starts inside the node.
    func pressBegan()
    /// Like `pressBegan()`, with the press point in the node's coordinate space (sliders jump to
    /// it). The default forwards to `pressBegan()`.
    func pressBegan(at point: CGPoint)
    /// The pointer moved while pressed, in the node's coordinate space. The default ignores it.
    func pressMoved(to point: CGPoint)
    /// Called when the press ends; `inside` tells whether the pointer is still over the node.
    func pressEnded(inside: Bool)
    /// Like `pressEnded(inside:)`, with the release point in the node's coordinate space (lists
    /// pick the row from it). The default forwards to `pressEnded(inside:)`.
    func pressEnded(inside: Bool, at point: CGPoint)
    /// Accessibility role and label for the semantics overlay.
    var semantics: SemanticsNode { get }
}

extension _Interactive {
    package func pressBegan(at point: CGPoint) { pressBegan() }
    package func pressMoved(to point: CGPoint) {}
    package func pressEnded(inside: Bool, at point: CGPoint) { pressEnded(inside: inside) }
}

/// One element of the accessibility tree hosts expose (DOM overlay in the browser).
public struct SemanticsNode: Equatable, Sendable {
    public enum Role: String, Sendable { case button, checkbox, textField }
    public var role: Role
    public var label: String
    public var frame: CGRect
    public var identifier: Int
    /// The state of a checkbox.
    public var isOn: Bool?
    /// What a text field's input element shows and where.
    public var textInput: TextInputInfo?

    public init(role: Role, label: String, frame: CGRect, identifier: Int, isOn: Bool? = nil, textInput: TextInputInfo? = nil) {
        self.role = role
        self.label = label
        self.frame = frame
        self.identifier = identifier
        self.isOn = isOn
        self.textInput = textInput
    }
}

extension ViewNode {
    /// Whether `point` (in this node's coordinate space) is inside the node's bounds.
    package func contains(_ point: CGPoint) -> Bool {
        CGRect(origin: .zero, size: frame.size).contains(point)
    }

    /// The deepest node containing `point` (in this node's space) that satisfies `predicate`,
    /// searching later-painted children first.
    package func hitTest(_ point: CGPoint, where predicate: (ViewNode) -> Bool) -> ViewNode? {
        for child in paintedChildren.reversed() {
            let local = CGPoint(x: point.x - child.frame.minX, y: point.y - child.frame.minY)
            guard child.contains(local) else { continue }
            if let hit = child.hitTest(local, where: predicate) { return hit }
        }
        return predicate(self) && contains(point) ? self : nil
    }

    /// All nodes in paint order that satisfy `predicate`.
    package func collectNodes(where predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var result: [ViewNode] = []
        if predicate(self) { result.append(self) }
        for child in paintedChildren { result += child.collectNodes(where: predicate) }
        return result
    }

    /// All nodes in structural order that satisfy `predicate`.
    package func descendants(where predicate: (ViewNode) -> Bool) -> [ViewNode] {
        var result: [ViewNode] = []
        if predicate(self) { result.append(self) }
        for child in structuralChildren { result += child.descendants(where: predicate) }
        return result
    }
}

extension Runtime {
    /// The interactive node under `point` (window coordinates), if any.
    package func interactiveNode(at point: CGPoint) -> (ViewNode & _Interactive)? {
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            guard node.contains(local) else { continue }
            if let hit = node.hitTest(local, where: { $0 is _Interactive }) { return hit as? (ViewNode & _Interactive) }
        }
        return nil
    }

    /// Pointer went down at `point` (points, window coordinates). A touch also starts tracking a
    /// pan of the scroll views under it; `time` is in seconds (any monotonic clock).
    public func pointerDown(at point: CGPoint, type: PointerType = .mouse, time: Double = 0) {
        if type == .touch { beginPan(at: point, time: time) }
        guard let node = interactiveNode(at: point) else { return }
        pressedNode = node
        node.pressBegan(at: local(point, in: node))
    }

    /// Pointer moved while down.
    public func pointerMoved(to point: CGPoint, time: Double = 0) {
        pointerPosition = point
        continuePan(to: point, time: time)
        if let node = pressedNode { node.pressMoved(to: local(point, in: node)) }
    }

    private func local(_ point: CGPoint, in node: ViewNode) -> CGPoint {
        let origin = node.frameInRoot.origin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// Pointer released at `point`. Activates the pressed node if the pointer is still over it
    /// and no pan took the touch.
    public func pointerUp(at point: CGPoint, time: Double = 0) {
        let panned = endPan(time: time)
        guard let node = pressedNode else { return }
        pressedNode = nil
        let inside = !panned && interactiveNode(at: point) === node
        node.pressEnded(inside: inside, at: local(point, in: node))
    }

    /// A click delivered by the accessibility overlay, by semantics identifier.
    public func activate(semanticsIdentifier: Int) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) else { return }
        node.pressBegan()
        node.pressEnded(inside: true)
    }

    package var interactiveNodes: [ViewNode & _Interactive] {
        root.layoutChildren.flatMap { $0.collectNodes(where: { $0 is _Interactive }) }.compactMap { $0 as? (ViewNode & _Interactive) }
    }

    /// The accessibility tree after the last layout, in window coordinates.
    public func semanticsTree() -> [SemanticsNode] {
        interactiveNodes.map { node in
            var semantics = node.semantics
            semantics.frame = node.frameInRoot
            return semantics
        }
    }
}

/// Transparent modifier node: the button's press state and activation.
@MainActor
package final class ButtonHostNode: LayoutNode<_ButtonHost>, _Interactive {
    package private(set) var child: TypedNode<AnyView>!
    private static var nextIdentifier = 0
    private let identifier: Int

    package init(_ context: _NodeContext<_ButtonHost>) {
        Self.nextIdentifier += 1
        identifier = Self.nextIdentifier
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = AnyView._makeNode(_NodeContext(view: context.view.label, parent: self, environment: context.environment))
    }

    override package func update(view: _ButtonHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.label, environment: environment, force: force)
    }

    private var target: ViewNode? { child.layoutChildren.first }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        target?.sizeThatFits(proposal) ?? .zero
    }
    override package func dimensions(in proposal: ProposedViewSize) -> ViewDimensions {
        target?.dimensions(in: proposal) ?? ViewDimensions(size: .zero)
    }
    override package func layoutContents(proposal: ProposedViewSize) {
        target?.place(at: .zero, anchor: .topLeading, proposal: proposal, by: self)
    }
    /// A button spaces like a plain view (8 to controls, the text's distance next to text:
    /// form/basic `button` sits 8.15 under a stepper and 4.74 over a text).
    override package var layoutSpacing: ViewSpacing { ViewSpacing() }
    override package var paintedChildren: [ViewNode] { target.map { [$0] } ?? [] }
    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "Button" }

    package func pressBegan() { if environment.isEnabled { view.isPressed.wrappedValue = true } }
    package func pressEnded(inside: Bool) {
        view.isPressed.wrappedValue = false
        if inside, environment.isEnabled { view.action.run() }
    }

    package var semantics: SemanticsNode {
        let label = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .button, label: label, frame: frameInRoot, identifier: identifier)
    }
}

@MainActor
private var nextTapIdentifier = 1_000_000

@MainActor
package final class TapGestureNode<Content: View>: UnaryLayoutModifierNode<Content, _TapGestureModifier>, _Interactive {
    private let identifier: Int

    override package init(_ context: _NodeContext<ModifiedContent<Content, _TapGestureModifier>>) {
        nextTapIdentifier += 1
        identifier = nextTapIdentifier
        super.init(context)
    }

    package func pressBegan() {}
    package func pressEnded(inside: Bool) { if inside { modifier.action.run() } }
    package var semantics: SemanticsNode { SemanticsNode(role: .button, label: "", frame: frameInRoot, identifier: identifier) }
}
