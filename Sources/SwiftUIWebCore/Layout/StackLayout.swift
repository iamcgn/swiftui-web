// The stack algorithm SwiftUI documents and that black-box measurements confirm: along the
// stack axis, children are sized from least to most flexible (flexibility = size at an infinite
// proposal minus size at a zero proposal), each proposed an equal share of the remaining space;
// higher `layoutPriority` groups are sized first, with lower groups guaranteed their minimum.
// Spacers stand aside: their minimum lengths are reserved while the other children are sized,
// and they share what is left (`pressure/spacer-*`, 2026-09-05: a text next to a default Spacer
// in a 130 pt column is proposed 50 − 8, next to `Spacer(minLength: 30)` 50 − 30).
// Across the axis, children align on the requested guide and the stack spans their union.

package struct StackChildMeasurement {
    package let index: Int
    package let minimum: CGFloat
    package let maximum: CGFloat
    package let priority: Double
    package var flexibility: CGFloat { maximum - minimum }
}

@MainActor
package enum StackLayoutEngine {
    /// Distances between adjacent children (count - 1 entries).
    package static func spacings(_ subviews: LayoutSubviews, axis: Axis, explicit: CGFloat?) -> [CGFloat] {
        guard subviews.count > 1 else { return [] }
        if let explicit { return Array(repeating: explicit, count: subviews.count - 1) }
        return (1..<subviews.count).map { subviews[$0 - 1].spacing.distance(to: subviews[$0].spacing, along: axis) }
    }

    /// Sizes for every child along `axis`, distributing `available` (already net of spacing).
    package static func distribute(_ subviews: LayoutSubviews, axis: Axis, available: CGFloat,
                                   crossProposal: CGFloat?) -> [CGSize] {
        var sizes = Array(repeating: CGSize.zero, count: subviews.count)
        var zero = ProposedViewSize.unspecified, infinite = ProposedViewSize.unspecified
        zero[axis] = 0
        infinite[axis] = .infinity
        zero[axis.perpendicular] = crossProposal
        infinite[axis.perpendicular] = crossProposal
        // Spacers stand aside: their minimums are reserved while the others are sized.
        var spacers: [(position: Int, minimum: CGFloat)] = []
        var measurements: [StackChildMeasurement] = []
        for (position, subview) in subviews.enumerated() {
            if subview.isSpacer {
                spacers.append((position, subview.sizeThatFits(zero)[axis]))
            } else {
                measurements.append(StackChildMeasurement(
                    index: position,
                    minimum: subview.sizeThatFits(zero)[axis],
                    maximum: subview.sizeThatFits(infinite)[axis],
                    priority: subview.priority))
            }
        }
        let reserved = spacers.reduce(0) { $0 + $1.minimum }
        // Priority groups, highest first.
        let priorities = Set(measurements.map(\.priority)).sorted(by: >)
        var remaining = max(0, available - reserved)
        for (groupIndex, priority) in priorities.enumerated() {
            let group = measurements.filter { $0.priority == priority }
            let lowerMinimum = priorities[(groupIndex + 1)...].reduce(CGFloat(0)) { sum, p in
                sum + measurements.filter { $0.priority == p }.reduce(0) { $0 + $1.minimum }
            }
            var groupAvailable = max(0, remaining - lowerMinimum)
            let ordered = group.enumerated().sorted { a, b in
                a.element.flexibility == b.element.flexibility ? a.offset < b.offset : a.element.flexibility < b.element.flexibility
            }.map(\.element)
            for (k, measurement) in ordered.enumerated() {
                var proposal = ProposedViewSize.unspecified
                proposal[axis] = groupAvailable / CGFloat(ordered.count - k)
                proposal[axis.perpendicular] = crossProposal
                let size = subviews[measurement.index].sizeThatFits(proposal)
                sizes[measurement.index] = size
                groupAvailable = max(0, groupAvailable - size[axis])
            }
            remaining = groupAvailable + lowerMinimum
        }
        // The spacers share what the others left.
        if !spacers.isEmpty {
            let used = measurements.reduce(CGFloat(0)) { $0 + sizes[$1.index][axis] }
            var leftover = max(0, available - used)
            for (k, spacer) in spacers.enumerated() {
                var proposal = ProposedViewSize.unspecified
                proposal[axis] = leftover / CGFloat(spacers.count - k)
                proposal[axis.perpendicular] = crossProposal
                let size = subviews[spacer.position].sizeThatFits(proposal)
                sizes[spacer.position] = size
                leftover = max(0, leftover - size[axis])
            }
        }
        return sizes
    }

    /// Ideal sizes (unspecified proposal along the axis).
    package static func idealSizes(_ subviews: LayoutSubviews, axis: Axis, crossProposal: CGFloat?) -> [CGSize] {
        subviews.map { subview in
            var proposal = ProposedViewSize.unspecified
            proposal[axis.perpendicular] = crossProposal
            return subview.sizeThatFits(proposal)
        }
    }

    package struct CrossExtent {
        package let size: CGFloat
        /// Position of the alignment guide within the stack's cross extent.
        package let guide: CGFloat
    }

    /// Cross-axis extent so that every child's `guide` lines up.
    package static func crossExtent(_ dimensions: [ViewDimensions], guide key: AlignmentKey, axis: Axis) -> CrossExtent {
        var before: CGFloat = 0, after: CGFloat = 0
        for dims in dimensions {
            let g = dims[key]
            before = max(before, g)
            after = max(after, dims.size[axis.perpendicular] - g)
        }
        return CrossExtent(size: before + after, guide: before)
    }
}

/// A horizontal container that you can use in conditional layouts.
@frozen
public struct HStackLayout: Sendable {
    public var alignment: VerticalAlignment
    public var spacing: CGFloat?

    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension HStackLayout: Layout {

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        _StackAxisLayout.sizeThatFits(axis: .horizontal, guide: alignment.key, spacing: spacing,
                                      proposal: proposal, subviews: subviews)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        _StackAxisLayout.placeSubviews(axis: .horizontal, guide: alignment.key, spacing: spacing,
                                       in: bounds, proposal: proposal, subviews: subviews)
    }

    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Subviews, cache: inout Void) -> CGFloat? {
        _StackAxisLayout.explicitCrossAlignment(axis: .horizontal, stackGuide: alignment.key, guide: guide.key,
                                                spacing: spacing, proposal: proposal, subviews: subviews)
    }

    public typealias AnimatableData = EmptyAnimatableData
}

/// A vertical container that you can use in conditional layouts.
@frozen
public struct VStackLayout: Sendable {
    public var alignment: HorizontalAlignment
    public var spacing: CGFloat?

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension VStackLayout: Layout {

    public static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .vertical
        return properties
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        _StackAxisLayout.sizeThatFits(axis: .vertical, guide: alignment.key, spacing: spacing,
                                      proposal: proposal, subviews: subviews)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        _StackAxisLayout.placeSubviews(axis: .vertical, guide: alignment.key, spacing: spacing,
                                       in: bounds, proposal: proposal, subviews: subviews)
    }

    public func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Subviews, cache: inout Void) -> CGFloat? {
        _StackAxisLayout.explicitCrossAlignment(axis: .vertical, stackGuide: alignment.key, guide: guide.key,
                                                spacing: spacing, proposal: proposal, subviews: subviews)
    }

    public func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                                  subviews: Subviews, cache: inout Void) -> CGFloat? {
        _StackAxisLayout.explicitAxisBaseline(axis: .vertical, stackGuide: alignment.key, guide: guide.key,
                                              spacing: spacing, in: bounds, proposal: proposal, subviews: subviews)
    }

    public typealias AnimatableData = EmptyAnimatableData
}

/// An overlaying container that you can use in conditional layouts.
@frozen
public struct ZStackLayout: Sendable {
    public var alignment: Alignment

    public init(alignment: Alignment = .center) {
        self.alignment = alignment
    }
}

extension ZStackLayout: Layout {

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let dimensions = subviews.map { $0.dimensions(in: proposal) }
        let horizontal = StackLayoutEngine.crossExtent(dimensions, guide: alignment.horizontal.key, axis: .vertical)
        let vertical = StackLayoutEngine.crossExtent(dimensions, guide: alignment.vertical.key, axis: .horizontal)
        return CGSize(width: horizontal.size, height: vertical.size)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let dimensions = subviews.map { $0.dimensions(in: proposal) }
        let horizontal = StackLayoutEngine.crossExtent(dimensions, guide: alignment.horizontal.key, axis: .vertical)
        let vertical = StackLayoutEngine.crossExtent(dimensions, guide: alignment.vertical.key, axis: .horizontal)
        let originX = bounds.minX
        let originY = bounds.minY
        for (subview, dims) in zip(subviews, dimensions) {
            let x = originX + horizontal.guide - dims[alignment.horizontal.key]
            let y = originY + vertical.guide - dims[alignment.vertical.key]
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: proposal)
        }
    }

    public typealias AnimatableData = EmptyAnimatableData
}

@MainActor
package enum _StackAxisLayout {
    package struct Plan {
        package let sizes: [CGSize]
        package let proposals: [ProposedViewSize]
        package let dimensions: [ViewDimensions]
        package let gaps: [CGFloat]
        package let extent: StackLayoutEngine.CrossExtent
        package var length: CGFloat { sizes.reduce(0) { $0 + $1.width } }
    }

    package static func plan(axis: Axis, guide: AlignmentKey, spacing: CGFloat?,
                             proposal: ProposedViewSize, subviews: LayoutSubviews) -> Plan {
        let gaps = StackLayoutEngine.spacings(subviews, axis: axis, explicit: spacing)
        let totalSpacing = gaps.reduce(0, +)
        let cross = proposal[axis.perpendicular]
        let sizes: [CGSize]
        if let length = proposal[axis] {
            sizes = StackLayoutEngine.distribute(subviews, axis: axis, available: length - totalSpacing, crossProposal: cross)
        } else {
            sizes = StackLayoutEngine.idealSizes(subviews, axis: axis, crossProposal: cross)
        }
        var proposals: [ProposedViewSize] = []
        let dimensions = zip(subviews, sizes).map { subview, size -> ViewDimensions in
            var p = ProposedViewSize.unspecified
            p[axis] = size[axis]
            p[axis.perpendicular] = cross
            proposals.append(p)
            return subview.dimensions(in: p)
        }
        let extent = StackLayoutEngine.crossExtent(dimensions, guide: guide, axis: axis)
        return Plan(sizes: sizes, proposals: proposals, dimensions: dimensions, gaps: gaps, extent: extent)
    }

    package static func sizeThatFits(axis: Axis, guide: AlignmentKey, spacing: CGFloat?,
                                     proposal: ProposedViewSize, subviews: LayoutSubviews) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let plan = plan(axis: axis, guide: guide, spacing: spacing, proposal: proposal, subviews: subviews)
        var result = CGSize.zero
        result[axis] = plan.sizes.reduce(0) { $0 + $1[axis] } + plan.gaps.reduce(0, +)
        result[axis.perpendicular] = plan.extent.size
        return result
    }

    package static func placeSubviews(axis: Axis, guide: AlignmentKey, spacing: CGFloat?,
                                      in bounds: CGRect, proposal: ProposedViewSize, subviews: LayoutSubviews) {
        guard !subviews.isEmpty else { return }
        let plan = plan(axis: axis, guide: guide, spacing: spacing, proposal: proposal, subviews: subviews)
        let used = plan.sizes.reduce(0) { $0 + $1[axis] } + plan.gaps.reduce(0, +)
        // Children are centred along the axis when the bounds exceed what they use; across the
        // axis the union is positioned by the stack's guide within the bounds.
        var cursor = bounds.origin[axis] + (bounds.size[axis] - used) / 2
        let crossOrigin = bounds.origin[axis.perpendicular]
        for (index, subview) in subviews.enumerated() {
            var origin = CGPoint.zero
            origin[axis] = cursor
            origin[axis.perpendicular] = crossOrigin + plan.extent.guide - plan.dimensions[index][guide]
            subview.place(at: origin, anchor: .topLeading, proposal: plan.proposals[index])
            cursor += plan.sizes[index][axis] + (index < plan.gaps.count ? plan.gaps[index] : 0)
        }
    }

    /// A stack reports an explicit cross-axis guide when asked for the guide it aligns on: the
    /// position where its children's guides meet. An `HStack` also reports text baselines across
    /// its axis: the topmost first baseline and the bottommost last baseline of its children
    /// (a `Label` in a baseline-aligned row sits on its title's baseline, `label/basic` `row`).
    package static func explicitCrossAlignment(axis: Axis, stackGuide: AlignmentKey, guide: AlignmentKey,
                                               spacing: CGFloat?, proposal: ProposedViewSize,
                                               subviews: LayoutSubviews) -> CGFloat? {
        guard !subviews.isEmpty else { return nil }
        let plan = plan(axis: axis, guide: stackGuide, spacing: spacing, proposal: proposal, subviews: subviews)
        if guide == stackGuide {
            // The aligned line is the stack's guide only when a child's value for it is explicit
            // (SwiftUI's rule); a plain edge or centre stays implicit, so `padding` and an outer
            // aligning frame keep a stack's inset (`VStack(alignment: .leading).padding()`).
            return plan.dimensions.contains { $0.explicitValue(guide) != nil } ? plan.extent.guide : nil
        }
        let first = VerticalAlignment.firstTextBaseline.key, last = VerticalAlignment.lastTextBaseline.key
        guard axis == .horizontal, guide == first || guide == last else { return nil }
        let values = plan.dimensions.map { dims in plan.extent.guide - dims[stackGuide] + dims[guide] }
        return guide == first ? values.min() : values.max()
    }

    /// A `VStack`'s text baselines run along its axis: the first child's first baseline and the
    /// last child's last baseline, where the children sit when the stack is placed in `bounds`.
    package static func explicitAxisBaseline(axis: Axis, stackGuide: AlignmentKey, guide: AlignmentKey,
                                             spacing: CGFloat?, in bounds: CGRect, proposal: ProposedViewSize,
                                             subviews: LayoutSubviews) -> CGFloat? {
        let first = VerticalAlignment.firstTextBaseline.key, last = VerticalAlignment.lastTextBaseline.key
        guard axis == .vertical, guide == first || guide == last, !subviews.isEmpty else { return nil }
        let plan = plan(axis: axis, guide: stackGuide, spacing: spacing, proposal: proposal, subviews: subviews)
        let used = plan.sizes.reduce(0) { $0 + $1[axis] } + plan.gaps.reduce(0, +)
        var cursor = (bounds.size[axis] - used) / 2
        if guide == first { return cursor + plan.dimensions[0][guide] }
        for index in 0..<(subviews.count - 1) { cursor += plan.sizes[index][axis] + plan.gaps[index] }
        return cursor + plan.dimensions[subviews.count - 1][guide]
    }
}
