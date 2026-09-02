/// A view's size and its alignment guides in its own coordinate space.
public struct ViewDimensions {
    /// The view's width.
    public let width: CGFloat

    /// The view's height.
    public let height: CGFloat

    /// Explicit alignment guides set with `alignmentGuide(_:computeValue:)`.
    package var explicit: [AlignmentKey: CGFloat]

    /// Explicit guides a `Layout` reports through `explicitAlignment`, resolved on demand
    /// (there is no way to enumerate every guide a layout might answer).
    package var resolver: ((AlignmentKey) -> CGFloat?)?

    package init(size: CGSize, explicit: [AlignmentKey: CGFloat] = [:],
                 resolver: ((AlignmentKey) -> CGFloat?)? = nil) {
        width = size.width
        height = size.height
        self.explicit = explicit
        self.resolver = resolver
    }

    package var size: CGSize { CGSize(width: width, height: height) }

    package func explicitValue(_ key: AlignmentKey) -> CGFloat? {
        explicit[key] ?? resolver?(key)
    }

    /// Gets the value of the given horizontal guide.
    public subscript(guide: HorizontalAlignment) -> CGFloat { self[guide.key] }

    /// Gets the value of the given vertical guide.
    public subscript(guide: VerticalAlignment) -> CGFloat { self[guide.key] }

    /// Gets the explicit value of the given horizontal alignment guide.
    public subscript(explicit guide: HorizontalAlignment) -> CGFloat? { explicitValue(guide.key) }

    /// Gets the explicit value of the given vertical alignment guide.
    public subscript(explicit guide: VerticalAlignment) -> CGFloat? { explicitValue(guide.key) }

    package subscript(key: AlignmentKey) -> CGFloat {
        explicitValue(key) ?? key.type.defaultValue(in: self)
    }

    /// The same guides, expressed in a coordinate space where this view sits at `offset`.
    package func offset(by offset: CGPoint, size newSize: CGSize) -> ViewDimensions {
        let shifted = explicit.reduce(into: [AlignmentKey: CGFloat]()) { result, entry in
            result[entry.key] = entry.value + offset[entry.key.axis]
        }
        let inner = resolver
        return ViewDimensions(size: newSize, explicit: shifted, resolver: inner.map { resolve in
            { key in resolve(key).map { $0 + offset[key.axis] } }
        })
    }
}

extension ViewDimensions: Equatable {
    public static func == (lhs: ViewDimensions, rhs: ViewDimensions) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.explicit == rhs.explicit
    }
}
