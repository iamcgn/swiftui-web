/// A type that you use to create custom alignment guides.
public protocol AlignmentID {
    /// Calculates a default value for a custom alignment guide.
    static func defaultValue(in context: ViewDimensions) -> CGFloat

    /// Updates `value` with the next value in a merge of explicit guides. The default keeps the
    /// first value.
    static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?)
}

extension AlignmentID {
    public static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?) {
        if parentValue == nil { parentValue = childValue }
    }
}

/// Identity of an alignment guide: the `AlignmentID` type plus the axis it applies to.
package struct AlignmentKey: Hashable, @unchecked Sendable {
    package let id: ObjectIdentifier
    package let axis: Axis
    package let type: any AlignmentID.Type

    package init(_ type: any AlignmentID.Type, axis: Axis) {
        self.id = ObjectIdentifier(type)
        self.axis = axis
        self.type = type
    }

    package static func == (lhs: AlignmentKey, rhs: AlignmentKey) -> Bool { lhs.id == rhs.id && lhs.axis == rhs.axis }
    package func hash(into hasher: inout Hasher) { hasher.combine(id); hasher.combine(axis) }
}

/// An alignment position along the horizontal axis.
public struct HorizontalAlignment: Equatable, Hashable, Sendable {
    package let key: AlignmentKey

    /// Creates a custom horizontal alignment of the specified type.
    public init(_ id: AlignmentID.Type) {
        key = AlignmentKey(id, axis: .horizontal)
    }

    public static let leading = HorizontalAlignment(_Leading.self)
    public static let center = HorizontalAlignment(_HCenter.self)
    public static let trailing = HorizontalAlignment(_Trailing.self)
    public static let listRowSeparatorLeading = HorizontalAlignment(_Leading.self)
    public static let listRowSeparatorTrailing = HorizontalAlignment(_Trailing.self)

    package enum _Leading: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
    }
    package enum _HCenter: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width / 2 }
    }
    package enum _Trailing: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width }
    }
}

/// An alignment position along the vertical axis.
public struct VerticalAlignment: Equatable, Hashable, Sendable {
    package let key: AlignmentKey

    /// Creates a custom vertical alignment of the specified type.
    public init(_ id: AlignmentID.Type) {
        key = AlignmentKey(id, axis: .vertical)
    }

    public static let top = VerticalAlignment(_Top.self)
    public static let center = VerticalAlignment(_VCenter.self)
    public static let bottom = VerticalAlignment(_Bottom.self)
    public static let firstTextBaseline = VerticalAlignment(_FirstTextBaseline.self)
    public static let lastTextBaseline = VerticalAlignment(_LastTextBaseline.self)

    package enum _Top: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
    }
    package enum _VCenter: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height / 2 }
    }
    package enum _Bottom: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height }
    }
    /// Views without text report their bottom edge, as SwiftUI does.
    package enum _FirstTextBaseline: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height }
    }
    package enum _LastTextBaseline: AlignmentID {
        public static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height }
    }
}

/// An alignment in both axes.
@frozen
public struct Alignment: Equatable, Hashable, Sendable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    @inlinable
    public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)
    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)
    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)
    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
    public static let centerFirstTextBaseline = Alignment(horizontal: .center, vertical: .firstTextBaseline)
    public static let centerLastTextBaseline = Alignment(horizontal: .center, vertical: .lastTextBaseline)
    public static let leadingFirstTextBaseline = Alignment(horizontal: .leading, vertical: .firstTextBaseline)
    public static let leadingLastTextBaseline = Alignment(horizontal: .leading, vertical: .lastTextBaseline)
    public static let trailingFirstTextBaseline = Alignment(horizontal: .trailing, vertical: .firstTextBaseline)
    public static let trailingLastTextBaseline = Alignment(horizontal: .trailing, vertical: .lastTextBaseline)
}
