// `contentShape` (sw-shape-shortcuts, decision 0021): the shape a view answers hit tests in. A
// gesture or control above the view asks the content shape beneath it (through the modifiers
// between, which share the frame) whether the point is inside; a view without one answers for
// its whole frame, as it did before. The other kinds (`dragPreview`, `contextMenuPreview`,
// `hoverEffect`, `accessibility`) are accepted and kept. Also the static shape shortcuts
// (`.rect`, `.rect(cornerRadius:)`, `.circle`, `.capsule`, `.ellipse`, `.containerRelative`,
// `.buttonBorder`) and `ButtonBorderShape` as a shape.
import WebFoundation
import WebGraphics

/// A kind of content shape.
public struct ContentShapeKinds: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// The kind for hit-testing and accessibility.
    public static let interaction = ContentShapeKinds(rawValue: 1 << 0)
    /// The kind for the drag preview of a draggable view.
    public static let dragPreview = ContentShapeKinds(rawValue: 1 << 1)
    /// The kind for the preview of a context menu.
    public static let contextMenuPreview = ContentShapeKinds(rawValue: 1 << 2)
    /// The kind for the hover effect.
    public static let hoverEffect = ContentShapeKinds(rawValue: 1 << 3)
    /// The kind for accessibility.
    public static let accessibility = ContentShapeKinds(rawValue: 1 << 4)
}

extension View {
    /// Defines the content shape for hit testing.
    nonisolated public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        modifier(_ContentShapeModifier(kinds: .interaction, shape: AnyShape(shape), eoFill: eoFill))
    }

    /// Sets the content shape for this view for the given kinds.
    nonisolated public func contentShape<S: Shape>(_ kind: ContentShapeKinds, _ shape: S, eoFill: Bool = false) -> some View {
        modifier(_ContentShapeModifier(kinds: kind, shape: AnyShape(shape), eoFill: eoFill))
    }
}

public struct _ContentShapeModifier {
    package let kinds: ContentShapeKinds
    package let shape: AnyShape
    package let eoFill: Bool
    package init(kinds: ContentShapeKinds, shape: AnyShape, eoFill: Bool) {
        self.kinds = kinds
        self.shape = shape
        self.eoFill = eoFill
    }
}

extension _ContentShapeModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ContentShapeNode(context)
    }
}

/// A node that answers hit tests inside its content shape.
@MainActor
package protocol _ContentShapeProviding: AnyObject {
    /// Whether `point` (in the node's space) is inside the interaction shape; nil when the node
    /// keeps no interaction shape.
    func _interactionShapeContains(_ point: CGPoint) -> Bool?
}

@MainActor
package final class ContentShapeNode<Content: View>: UnaryLayoutModifierNode<Content, _ContentShapeModifier>, _ContentShapeProviding {
    package func _interactionShapeContains(_ point: CGPoint) -> Bool? {
        guard modifier.kinds.contains(.interaction) else { return nil }
        return modifier.shape.path(in: CGRect(origin: .zero, size: frame.size)).contains(point, eoFill: modifier.eoFill)
    }

    override package func contains(_ point: CGPoint) -> Bool {
        _interactionShapeContains(point) ?? super.contains(point)
    }

    /// Children outside the shape are not hit.
    override package var clipsHitTesting: Bool { modifier.kinds.contains(.interaction) }

    override package var nodeDescription: String { "ContentShape" }
}

extension UnaryLayoutModifierNode {
    /// The answer of a content shape directly beneath this modifier (through the modifiers
    /// between, which lay out at the same frame), for a gesture or control that asks whether
    /// `point` hits its content.
    package func _contentShapeContains(_ point: CGPoint) -> Bool? {
        var node: ViewNode = child
        var local = CGPoint(x: point.x - child.frame.minX, y: point.y - child.frame.minY)
        while true {
            if let shaped = node as? any _ContentShapeProviding { return shaped._interactionShapeContains(local) }
            guard let unary = node as? any _UnaryLayoutModifier, node.frame.size == frame.size else { return nil }
            let next = unary.modifiedContent
            local = CGPoint(x: local.x - next.frame.minX, y: local.y - next.frame.minY)
            node = next
        }
    }
}

// MARK: - Shape shortcuts

extension Shape where Self == Rectangle {
    /// A rectangle.
    public static var rect: Rectangle { Rectangle() }
}

extension Shape where Self == RoundedRectangle {
    /// A rounded rectangle with the given corner radius.
    public static func rect(cornerRadius: CGFloat, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: style)
    }
    /// A rounded rectangle with the given corner size.
    public static func rect(cornerSize: CGSize, style: RoundedCornerStyle = .continuous) -> RoundedRectangle {
        RoundedRectangle(cornerSize: cornerSize, style: style)
    }
}

extension Shape where Self == UnevenRoundedRectangle {
    /// A rectangle with the given corner radii.
    public static func rect(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(cornerRadii: cornerRadii, style: style)
    }
    /// A rectangle with the given corner radii.
    public static func rect(topLeadingRadius: CGFloat = 0, bottomLeadingRadius: CGFloat = 0, bottomTrailingRadius: CGFloat = 0,
                            topTrailingRadius: CGFloat = 0, style: RoundedCornerStyle = .continuous) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: topLeadingRadius, bottomLeadingRadius: bottomLeadingRadius,
                               bottomTrailingRadius: bottomTrailingRadius, topTrailingRadius: topTrailingRadius, style: style)
    }
}

extension Shape where Self == Circle {
    /// A circle.
    public static var circle: Circle { Circle() }
}

extension Shape where Self == Ellipse {
    /// An ellipse.
    public static var ellipse: Ellipse { Ellipse() }
}

extension Shape where Self == Capsule {
    /// A capsule.
    public static var capsule: Capsule { Capsule() }
    /// A capsule with the given corner style.
    public static func capsule(style: RoundedCornerStyle) -> Capsule { Capsule(style: style) }
}

extension Shape where Self == ContainerRelativeShape {
    /// The container's shape, inset by the view's distance from it.
    public static var containerRelative: ContainerRelativeShape { ContainerRelativeShape() }
}

extension Shape where Self == ButtonBorderShape {
    /// The shape of a bordered button in the current context.
    public static var buttonBorder: ButtonBorderShape { ButtonBorderShape.automatic }
}

/// A shape used to draw a button's border.
public struct ButtonBorderShape: Sendable, Equatable {
    package enum Kind: Equatable, Sendable { case automatic, capsule, roundedRectangle(CGFloat?), circle }
    package let kind: Kind

    public static let automatic = ButtonBorderShape(kind: .automatic)
    public static let capsule = ButtonBorderShape(kind: .capsule)
    public static let roundedRectangle = ButtonBorderShape(kind: .roundedRectangle(nil))
    public static func roundedRectangle(radius: CGFloat) -> ButtonBorderShape { ButtonBorderShape(kind: .roundedRectangle(radius)) }
    public static let circle = ButtonBorderShape(kind: .circle)
}

extension ButtonBorderShape: InsettableShape {
    /// The automatic shape is the bordered button's rounded rectangle (radius 8, decision 0021:
    /// unmeasured; iOS 26's bordered buttons are capsules).
    nonisolated public func path(in rect: CGRect) -> Path {
        switch kind {
        case .automatic, .roundedRectangle(nil): return RoundedRectangle(cornerRadius: 8).path(in: rect)
        case .roundedRectangle(let radius?): return RoundedRectangle(cornerRadius: radius).path(in: rect)
        case .capsule: return Capsule().path(in: rect)
        case .circle: return Circle().path(in: rect)
        }
    }
    nonisolated public func inset(by amount: CGFloat) -> _InsetShape<ButtonBorderShape> { _InsetShape(shape: self, amount: amount) }
    public typealias AnimatableData = EmptyAnimatableData
}

extension ButtonBorderShape: _InsetPathProviding {
    nonisolated public func _insetPath(in rect: CGRect, by amount: CGFloat) -> Path { path(in: rect.insetBy(dx: amount, dy: amount)) }
}

extension View {
    /// Sets the border shape for bordered buttons (kept in the environment; the styles draw their
    /// measured shapes).
    nonisolated public func buttonBorderShape(_ shape: ButtonBorderShape) -> some View {
        environment(\.buttonBorderShape, shape)
    }
}

extension EnvironmentValues {
    /// The border shape bordered buttons take.
    public var buttonBorderShape: ButtonBorderShape {
        get { self[ButtonBorderShapeKey.self] }
        set { self[ButtonBorderShapeKey.self] = newValue }
    }
}

private struct ButtonBorderShapeKey: EnvironmentKey {
    static let defaultValue = ButtonBorderShape.automatic
}
