/// A proposal for the size of a view. `nil` in a dimension means "your ideal size".
@frozen
public struct ProposedViewSize: Equatable, Hashable, Sendable {
    public var width: CGFloat?
    public var height: CGFloat?

    /// A size proposal that contains zero in both dimensions.
    public static let zero = ProposedViewSize(width: 0, height: 0)

    /// The proposed size with both dimensions left unspecified.
    public static let unspecified = ProposedViewSize(width: nil, height: nil)

    /// A size proposal that contains infinity in both dimensions.
    public static let infinity = ProposedViewSize(width: .infinity, height: .infinity)

    @inlinable
    public init(width: CGFloat?, height: CGFloat?) {
        self.width = width
        self.height = height
    }

    @inlinable
    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    /// Creates a new proposal that replaces unspecified dimensions in this proposal with the
    /// corresponding dimension of the specified size.
    @inlinable
    public func replacingUnspecifiedDimensions(by size: CGSize = CGSize(width: 10, height: 10)) -> CGSize {
        CGSize(width: width ?? size.width, height: height ?? size.height)
    }
}

extension ProposedViewSize {
    package subscript(axis: Axis) -> CGFloat? {
        get { axis == .horizontal ? width : height }
        set { if axis == .horizontal { width = newValue } else { height = newValue } }
    }
}

extension CGSize {
    package subscript(axis: Axis) -> CGFloat {
        get { axis == .horizontal ? width : height }
        set { if axis == .horizontal { width = newValue } else { height = newValue } }
    }
}

extension CGPoint {
    package subscript(axis: Axis) -> CGFloat {
        get { axis == .horizontal ? x : y }
        set { if axis == .horizontal { x = newValue } else { y = newValue } }
    }
}
