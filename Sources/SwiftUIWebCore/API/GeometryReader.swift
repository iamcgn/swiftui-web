/// A coordinate space in which to express geometry.
public enum CoordinateSpace: Equatable, Hashable, @unchecked Sendable {
    case global
    case local
    case named(AnyHashable)

    public var isGlobal: Bool { self == .global }
    public var isLocal: Bool { self == .local }
}

/// A frame of reference within the layout system.
public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .global }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    public init() {}
    public var coordinateSpace: CoordinateSpace { .local }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable, Sendable {
    public let coordinateSpace: CoordinateSpace
    package init(_ name: AnyHashable) { coordinateSpace = .named(name) }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}
extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}
extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace { NamedCoordinateSpace(AnyHashable(name)) }
}

/// A proxy for access to the size and coordinate space of a container view.
///
/// Its members are nonisolated, as Apple's are, so a helper in a plain extension of the proxy
/// can read them (BackyardBirds' parallax offset). Geometry is only ever read while the runtime
/// lays out or renders on the main actor, which each member assumes.
public struct GeometryProxy {
    package unowned let node: ViewNode
    /// The size of the container view.
    public let size: CGSize

    package init(node: ViewNode, size: CGSize) {
        self.node = node
        self.size = size
    }

    /// The safe area inset of the container view: how much of the reader's frame lies under a
    /// bar or a `safeAreaInset`; none inside `ignoresSafeArea` (`position/safe-area-geometry`).
    public var safeAreaInsets: EdgeInsets {
        let node = self.node
        return MainActor.assumeIsolated { node.safeAreaOverlap }
    }

    /// Returns the container view's bounds rectangle, converted to a defined coordinate space.
    public func frame(in coordinateSpace: CoordinateSpace) -> CGRect {
        let node = self.node
        return MainActor.assumeIsolated { node.frame(in: coordinateSpace) }
    }

    /// Returns the container view's bounds rectangle, converted to a defined coordinate space.
    public func frame(in coordinateSpace: some CoordinateSpaceProtocol) -> CGRect {
        frame(in: coordinateSpace.coordinateSpace)
    }

    /// Returns the given coordinate space's bounds rectangle, converted to the local space.
    public func bounds(of coordinateSpace: NamedCoordinateSpace) -> CGRect? {
        let node = self.node, space = coordinateSpace.coordinateSpace
        return MainActor.assumeIsolated {
            guard let named = node.ancestorCoordinateSpace(space) else { return nil }
            let mine = node.frameInRoot, theirs = named.frameInRoot
            return CGRect(x: theirs.minX - mine.minX, y: theirs.minY - mine.minY, width: theirs.width, height: theirs.height)
        }
    }

    /// This container's origin in the root's coordinates, which anchors resolve against.
    package var _originInRoot: CGPoint {
        let node = self.node
        return MainActor.assumeIsolated { node.frameInRoot.origin }
    }
}

/// A container view that defines its content as a function of its own size and coordinate space.
@frozen
public struct GeometryReader<Content: View> {
    public var content: (GeometryProxy) -> Content

    @inlinable
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {
        self.content = content
    }
}

extension GeometryReader: View {
    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<GeometryReader<Content>>) -> TypedNode<GeometryReader<Content>> {
        GeometryReaderNode(context)
    }
}

/// Names the content's coordinate space.
public struct _CoordinateSpaceModifier<Name: Hashable> {
    public var name: Name
    public init(name: Name) { self.name = name }
}

extension _CoordinateSpaceModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        CoordinateSpaceNode(context)
    }
}

extension View {
    /// Assigns a name to the view's coordinate space, so other code can operate on dimensions
    /// like points and sizes relative to the named space.
    nonisolated public func coordinateSpace<T: Hashable>(name: T) -> some View {
        modifier(_CoordinateSpaceModifier(name: name))
    }

    /// Assigns a name to the view's coordinate space.
    nonisolated public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View {
        modifier(_CoordinateSpaceModifier(name: name.coordinateSpace))
    }
}
