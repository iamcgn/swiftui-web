/// Anchors: a geometry value (a rectangle, a point) captured in one view and read back in
/// another's coordinates through `GeometryProxy`'s subscript (`g[proxy.plotAreaFrame]`). The
/// anchor holds its value in the root view's coordinates; the subscript moves it into the
/// reader's.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An opaque value derived from a view's geometry, resolved in another view's coordinate
/// space by `GeometryProxy`.
public struct Anchor<Value> {
    /// The value in the root view's coordinates.
    package let rootValue: Value
    /// The value moved by an offset.
    package let translate: @Sendable (Value, CGSize) -> Value

    package init(rootValue: Value, translate: @escaping @Sendable (Value, CGSize) -> Value) {
        self.rootValue = rootValue
        self.translate = translate
    }

    /// The value in coordinates whose origin is at `origin` (in the root's).
    package func value(relativeTo origin: CGPoint) -> Value {
        translate(rootValue, CGSize(width: -origin.x, height: -origin.y))
    }
}

extension Anchor where Value == CGRect {
    /// An anchor for a rectangle in the root view's coordinates.
    package init(rootRect: CGRect) {
        self.init(rootValue: rootRect) { rect, offset in rect.offsetBy(dx: offset.width, dy: offset.height) }
    }
}

extension Anchor where Value == CGPoint {
    /// An anchor for a point in the root view's coordinates.
    package init(rootPoint: CGPoint) {
        self.init(rootValue: rootPoint) { point, offset in CGPoint(x: point.x + offset.width, y: point.y + offset.height) }
    }
}

extension Anchor: @unchecked Sendable where Value: Sendable {}

extension Anchor: Equatable where Value: Equatable {
    public static func == (lhs: Anchor, rhs: Anchor) -> Bool { lhs.rootValue == rhs.rootValue }
}

extension Anchor: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(rootValue) }
}

extension GeometryProxy {
    /// The anchor's value in this container's coordinate space.
    @MainActor public subscript<T>(anchor: Anchor<T>) -> T {
        anchor.value(relativeTo: node.frameInRoot.origin)
    }
}
