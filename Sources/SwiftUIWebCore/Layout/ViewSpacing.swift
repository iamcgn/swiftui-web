/// A collection of the geometric spacing preferences of a view.
///
/// Modelled on SwiftUI's internal `Spacing`: each edge carries minima per *category*. The
/// distance between two neighbours is the largest minimum over the categories both declare
/// for the facing edges; with no category in common the distance is 0 (which is how `Spacer`
/// hugs its neighbours). Plain views declare the default category at 8 points; text views add
/// font-derived categories (measured per platform from goldens, step 6).
public struct ViewSpacing: Sendable, Equatable {
    package enum Category: Hashable, Sendable {
        case textToText
        case textBaseline
        case edgeBelowText
        case edgeAboveText
    }

    package struct Key: Hashable, Sendable {
        package let category: Category?
        package let edge: Edge

        package init(category: Category?, edge: Edge) {
            self.category = category
            self.edge = edge
        }
    }

    package var minima: [Key: CGFloat]

    /// The default spacing between sibling views on this platform.
    package static let defaultDistance: CGFloat = 8

    /// A view spacing instance that contains zero on all edges.
    public static let zero = ViewSpacing(uniform: 0)

    /// Initializes an instance with default spacing values.
    public init() {
        self.init(uniform: Self.defaultDistance)
    }

    package init(minima: [Key: CGFloat]) {
        self.minima = minima
    }

    package init(uniform value: CGFloat) {
        minima = [:]
        for edge in Edge.allCases { minima[Key(category: nil, edge: edge)] = value }
    }

    package subscript(category: Category?, edge: Edge) -> CGFloat? {
        get { minima[Key(category: category, edge: edge)] }
        set { minima[Key(category: category, edge: edge)] = newValue }
    }

    /// Gets the preferred spacing distance along the specified axis to the view that returns a
    /// specified spacing preference.
    public func distance(to next: ViewSpacing, along axis: Axis) -> CGFloat {
        let (selfEdge, nextEdge): (Edge, Edge) = axis == .horizontal ? (.trailing, .leading) : (.bottom, .top)
        var result: CGFloat?
        for (key, value) in minima where key.edge == selfEdge {
            guard let other = next.minima[Key(category: key.category, edge: nextEdge)] else { continue }
            let candidate = max(value, other)
            result = result.map { max($0, candidate) } ?? candidate
        }
        return result ?? 0
    }

    /// Merges the spacing preferences of another spacing instance with this instance for a
    /// specified set of edges.
    public mutating func formUnion(_ other: ViewSpacing, edges: Edge.Set = .all) {
        for (key, value) in other.minima where edges.contains(key.edge) {
            minima[key] = minima[key].map { max($0, value) } ?? value
        }
    }

    /// Gets a new value that merges the spacing preferences of another spacing instance with
    /// this instance for a specified set of edges.
    public func union(_ other: ViewSpacing, edges: Edge.Set = .all) -> ViewSpacing {
        var copy = self
        copy.formUnion(other, edges: edges)
        return copy
    }
}
