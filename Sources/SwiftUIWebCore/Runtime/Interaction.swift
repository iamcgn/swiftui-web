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
    /// Whether the element's descendants are exposed as their own elements (containers).
    var exposesChildren: Bool { get }
    /// The axes along which a press that starts moving stays with this node instead of becoming
    /// a pan of the scroll views around it (a slider keeps a sideways finger). Empty for most.
    var dragAxes: Axis.Set { get }
}

extension _Interactive {
    package func pressBegan(at point: CGPoint) { pressBegan() }
    package func pressMoved(to point: CGPoint) {}
    package func pressEnded(inside: Bool, at point: CGPoint) { pressEnded(inside: inside) }
    package var exposesChildren: Bool { false }
    package var dragAxes: Axis.Set { [] }
}

/// A node that is an accessibility element without being interactive (text, images).
@MainActor
package protocol _SemanticsProviding: AnyObject {
    var staticSemantics: SemanticsNode? { get }
}

/// A node whose value assistive technology can adjust or set (sliders, steppers).
@MainActor
package protocol _Adjustable: AnyObject {
    func adjust(increment: Bool)
    func setValue(_ value: Double)
}

/// One element of the accessibility tree hosts expose (DOM overlay in the browser).
public struct SemanticsNode: Equatable, Sendable {
    public enum Role: String, Sendable {
        case button, checkbox, textField
        case text, heading, image, group, link
        case `switch`, slider, stepper, popUpButton, radioGroup, segmented
        /// A list with a selection: a focusable listbox whose rows are their own elements.
        case list
    }
    public var role: Role
    public var label: String
    public var frame: CGRect
    public var identifier: Int
    /// The state of a checkbox or switch.
    public var isOn: Bool?
    /// What a text field's input element shows and where.
    public var textInput: TextInputInfo?
    /// A description of the element's value (`accessibilityValue`, a slider's percentage).
    public var value: String?
    /// What happens on activation (`accessibilityHint`).
    public var hint: String?
    /// The developer identifier (`accessibilityIdentifier`).
    public var accessibilityIdentifier: String?
    /// A slider's range and current value, for `<input type=range>`.
    public var range: SemanticsRange?
    /// Whether the element can be incremented and decremented (steppers, sliders).
    public var isAdjustable = false
    /// Whether a static-looking element takes keyboard focus (`focusable` views, lists).
    public var isFocusable = false

    public init(role: Role, label: String, frame: CGRect, identifier: Int, isOn: Bool? = nil, textInput: TextInputInfo? = nil) {
        self.role = role
        self.label = label
        self.frame = frame
        self.identifier = identifier
        self.isOn = isOn
        self.textInput = textInput
    }
}

public struct SemanticsRange: Equatable, Sendable {
    public var minimum: Double, maximum: Double, value: Double, step: Double?
    public init(minimum: Double, maximum: Double, value: Double, step: Double? = nil) {
        self.minimum = minimum; self.maximum = maximum; self.value = value; self.step = step
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
        if capturesHitTesting, predicate(self), contains(point) { return self }
        for child in paintOrderedChildren.reversed() {
            let shift = child.hitTestOffset
            let local = CGPoint(x: point.x - child.frame.minX - shift.x, y: point.y - child.frame.minY - shift.y)
            if child.clipsHitTesting, !child.contains(local) { continue }
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
        let presented = presentationHit(at: point)
        if presented.handled { return presented.node }
        if let toolbar, toolbar.frame.contains(point) { return toolbar.interactiveNode(at: point) }
        for node in root.layoutChildren.reversed() {
            let shift = node.hitTestOffset
            let local = CGPoint(x: point.x - node.frame.minX - shift.x, y: point.y - node.frame.minY - shift.y)
            if node.clipsHitTesting, !node.contains(local) { continue }
            if let hit = node.hitTest(local, where: { $0 is _Interactive }) { return hit as? (ViewNode & _Interactive) }
        }
        return nil
    }

    /// Pointer went down at `point` (points, window coordinates). A touch also starts tracking a
    /// pan of the scroll views under it; `time` is in seconds (any monotonic clock).
    public func pointerDown(at point: CGPoint, type: PointerType = .mouse, time: Double = 0) {
        lastPointerTime = time
        if type == .touch { beginPan(at: point, time: time) }
        // A touch that stopped a decelerating scroll view belongs to it, not to a control.
        if pan?.active == true { return }
        pendingDrag = dragSource(at: point).map { ($0, point) }
        guard let node = interactiveNode(at: point) else { return }
        pressedNode = node
        node.pressBegan(at: local(point, in: node))
    }

    /// Pointer moved (pressed or not): drives presses, pans and hovering.
    public func pointerMoved(to point: CGPoint, time: Double = 0) {
        lastPointerTime = time
        pointerPosition = point
        continuePan(to: point, time: time)
        if dragSession != nil {
            updateDrag(to: point)
            return
        }
        // A press on a drag source that travels 4 pt lifts the payload.
        if let pending = pendingDrag, abs(point.x - pending.start.x) + abs(point.y - pending.start.y) >= 4 {
            pendingDrag = nil
            beginDrag(from: pending.source, pressedAt: pending.start, at: point)
            return
        }
        if let node = pressedNode { node.pressMoved(to: local(point, in: node)) }
        updateHover(at: point)
    }

    /// The pointer left the window: every hover ends.
    public func pointerLeft() {
        pointerPosition = CGPoint(x: -1, y: -1)
        updateHover(at: nil)
    }

    private func local(_ point: CGPoint, in node: ViewNode) -> CGPoint {
        let origin = node.frameInRoot.origin
        return CGPoint(x: point.x - origin.x, y: point.y - origin.y)
    }

    /// Pointer released at `point`. Activates the pressed node if the pointer is still over it
    /// and no pan took the touch.
    public func pointerUp(at point: CGPoint, time: Double = 0) {
        lastPointerTime = time
        pendingDrag = nil
        if dragSession != nil {
            endDrag(at: point)
            return
        }
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
        (toolbar?.interactiveNodes ?? [])
            + root.layoutChildren.flatMap { $0.collectNodes(where: { $0 is _Interactive }) }.compactMap { $0 as? (ViewNode & _Interactive) }
            + presentations.flatMap(\.interactiveNodes)
    }

    /// The accessibility tree after the last layout, in window coordinates: interactive nodes,
    /// static text and images, in paint order, with accessibility modifiers applied
    /// (Runtime/AccessibilityNodes.swift). After a frame that only moved scrolled content the
    /// tree is the last full walk with its frames refreshed: nothing else can have changed
    /// without a state update, which forces a full layout (`semanticsCacheIsValid`).
    public func semanticsTree() -> [SemanticsNode] {
        if semanticsCacheIsValid {
            return semanticsCache.map { entry in
                var element = entry.element
                let frame = entry.node.frameInRoot
                if var input = element.textInput {
                    input.textRect = input.textRect.offsetBy(dx: frame.minX - element.frame.minX, dy: frame.minY - element.frame.minY)
                    element.textInput = input
                }
                element.frame = frame
                return element
            }
        }
        var entries: [SemanticsEntry] = []
        for node in toolbar?.layoutChildren ?? [] { collectSemantics(node, attributes: nil, into: &entries) }
        for node in root.layoutChildren { collectSemantics(node, attributes: nil, into: &entries) }
        for presentation in presentations {
            for node in presentation.semanticsRoots { collectSemantics(node, attributes: nil, into: &entries) }
        }
        semanticsCache = entries
        semanticsCacheLayout = fullLayoutCount
        return entries.map(\.element)
    }

    /// Increments or decrements an adjustable element (arrow keys on a stepper or slider).
    public func adjust(semanticsIdentifier: Int, increment: Bool) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _Adjustable else { return }
        node.adjust(increment: increment)
    }

    /// Sets a slider's value from its range input.
    public func setValue(semanticsIdentifier: Int, value: Double) {
        guard let node = interactiveNodes.first(where: { $0.semantics.identifier == semanticsIdentifier }) as? any _Adjustable else { return }
        node.setValue(value)
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
        if inside, environment.isEnabled {
            view.action.run()
            if environment._dismissesOnActivation {
                if environment._inMenu { runtime.dismissMenus() } else { environment.dismiss() }
            }
        }
    }

    package var semantics: SemanticsNode {
        let label = child.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString }.joined(separator: " ")
        return SemanticsNode(role: .button, label: label, frame: frameInRoot, identifier: identifier)
    }
}

@MainActor
private var nextTapIdentifier = 1_000_000

/// A fresh semantics identifier for a gesture node (tap and other gestures share the range).
@MainActor package func _nextGestureIdentifier() -> Int {
    nextTapIdentifier += 1
    return nextTapIdentifier
}

@MainActor
package final class TapGestureNode<Content: View>: UnaryLayoutModifierNode<Content, _TapGestureModifier>, _Interactive {
    private let identifier: Int
    /// Counts taps for `count` > 1 (Runtime/GestureNodes.swift).
    private lazy var recognizer: TapRecognizer = {
        let recognizer = TapRecognizer(count: modifier.count)
        recognizer.endedHandlers.append { [weak self] in self?.modifier.action.run() }
        return recognizer
    }()

    override package init(_ context: _NodeContext<ModifiedContent<Content, _TapGestureModifier>>) {
        nextTapIdentifier += 1
        identifier = nextTapIdentifier
        super.init(context)
    }

    private func event(_ point: CGPoint) -> GestureEvent {
        GestureEvent(location: point, time: runtime.lastPointerTime, clock: runtime.animationClock, windowOrigin: frameInRoot.origin)
    }

    package func pressBegan() {}
    package func pressBegan(at point: CGPoint) { if modifier.count > 1 { recognizer.began(event(point)) } }
    package func pressEnded(inside: Bool) {}
    package func pressEnded(inside: Bool, at point: CGPoint) {
        if modifier.count > 1 { recognizer.ended(event(point), inside: inside) } else if inside { modifier.action.run() }
    }
    package var semantics: SemanticsNode { SemanticsNode(role: .button, label: "", frame: frameInRoot, identifier: identifier) }
}
