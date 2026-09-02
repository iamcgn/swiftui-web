/// The horizontal or vertical dimension in a 2D coordinate system.
@frozen
public enum Axis: Int8, CaseIterable, Sendable, Hashable {
    case horizontal
    case vertical

    /// An efficient set of axes.
    @frozen
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1 << 0)
        public static let vertical = Set(rawValue: 1 << 1)
    }

    package var perpendicular: Axis { self == .horizontal ? .vertical : .horizontal }
}

extension Axis: CustomStringConvertible {
    public var description: String { self == .horizontal ? "horizontal" : "vertical" }
}

/// An enumeration to indicate one edge of a rectangle.
@frozen
public enum Edge: Int8, CaseIterable, Sendable, Hashable {
    case top, leading, bottom, trailing

    /// An efficient set of edges.
    @frozen
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public init(_ e: Edge) { self.init(rawValue: 1 << e.rawValue) }

        public static let top = Set(.top)
        public static let leading = Set(.leading)
        public static let bottom = Set(.bottom)
        public static let trailing = Set(.trailing)
        public static let all: Set = [.top, .leading, .bottom, .trailing]
        public static let horizontal: Set = [.leading, .trailing]
        public static let vertical: Set = [.top, .bottom]

        package func contains(_ edge: Edge) -> Bool { contains(Set(edge)) }
    }
}

/// The inset distances for the sides of a rectangle.
@frozen
public struct EdgeInsets: Equatable, Hashable, Sendable {
    public var top: CGFloat
    public var leading: CGFloat
    public var bottom: CGFloat
    public var trailing: CGFloat

    @inlinable
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }

    @inlinable
    public init() {
        self.init(top: 0, leading: 0, bottom: 0, trailing: 0)
    }

    package init(_ edges: Edge.Set, _ length: CGFloat) {
        self.init(
            top: edges.contains(.top) ? length : 0,
            leading: edges.contains(.leading) ? length : 0,
            bottom: edges.contains(.bottom) ? length : 0,
            trailing: edges.contains(.trailing) ? length : 0)
    }

    package var horizontal: CGFloat { leading + trailing }
    package var vertical: CGFloat { top + bottom }
}

extension EdgeInsets: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>>
    public var animatableData: AnimatableData {
        get { .init(top, .init(leading, .init(bottom, trailing))) }
        set {
            top = newValue.first
            leading = newValue.second.first
            bottom = newValue.second.second.first
            trailing = newValue.second.second.second
        }
    }
}

/// A normalized 2D point in a view's coordinate space.
@frozen
public struct UnitPoint: Hashable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    @inlinable public init() { x = 0; y = 0 }
    @inlinable public init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }

    public static let zero = UnitPoint(x: 0, y: 0)
    public static let center = UnitPoint(x: 0.5, y: 0.5)
    public static let leading = UnitPoint(x: 0, y: 0.5)
    public static let trailing = UnitPoint(x: 1, y: 0.5)
    public static let top = UnitPoint(x: 0.5, y: 0)
    public static let bottom = UnitPoint(x: 0.5, y: 1)
    public static let topLeading = UnitPoint(x: 0, y: 0)
    public static let topTrailing = UnitPoint(x: 1, y: 0)
    public static let bottomLeading = UnitPoint(x: 0, y: 1)
    public static let bottomTrailing = UnitPoint(x: 1, y: 1)
}

extension UnitPoint: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        get { .init(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}

extension CGSize: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        get { .init(width, height) }
        set { width = newValue.first; height = newValue.second }
    }
}

extension CGPoint: Animatable {
    public typealias AnimatableData = AnimatablePair<CGFloat, CGFloat>
    public var animatableData: AnimatableData {
        get { .init(x, y) }
        set { x = newValue.first; y = newValue.second }
    }
}

extension CGRect: Animatable {
    public typealias AnimatableData = AnimatablePair<CGPoint.AnimatableData, CGSize.AnimatableData>
    public var animatableData: AnimatableData {
        get { .init(origin.animatableData, size.animatableData) }
        set { origin.animatableData = newValue.first; size.animatableData = newValue.second }
    }
}
