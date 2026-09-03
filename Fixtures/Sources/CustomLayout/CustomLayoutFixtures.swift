// Custom Layout fixtures: layouts written against the public Layout API (a wrapping flow, a
// radial ring, one reading layout values, priorities and spacing) and AnyLayout switching.
import SwiftUI
import FixtureKit

/// Wraps subviews into rows of at most `width`, 8 pt apart, rows 6 pt apart; caches the rows.
struct FlowLayout: Layout {
    struct Cache { var rows: [[Int]] = []; var width: CGFloat = 0 }

    func makeCache(subviews: Subviews) -> Cache { Cache() }

    private func rows(for width: CGFloat, subviews: Subviews, cache: inout Cache) -> [[Int]] {
        if cache.width == width, !cache.rows.isEmpty { return cache.rows }
        var rows: [[Int]] = [[]]
        var x: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { rows.append([]); x = 0 }
            rows[rows.count - 1].append(index)
            x += size.width + 8
        }
        cache.rows = rows
        cache.width = width
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 300
        var height: CGFloat = 0
        for (i, row) in rows(for: width, subviews: subviews, cache: &cache).enumerated() {
            if i > 0 { height += 6 }
            height += row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        var y = bounds.minY
        for (i, row) in rows(for: bounds.width, subviews: subviews, cache: &cache).enumerated() {
            if i > 0 { y += 6 }
            var x = bounds.minX
            var rowHeight: CGFloat = 0
            for index in row {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + 8
                rowHeight = max(rowHeight, size.height)
            }
            y += rowHeight
        }
    }
}

/// Places subviews by their centres on a circle inscribed in the bounds.
struct RadialLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let side = min(proposal.width ?? 200, proposal.height ?? 200)
        return CGSize(width: side, height: side)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let radius = min(bounds.width, bounds.height) / 2 - 12
        for (index, subview) in subviews.enumerated() {
            // Quarter turns only, so no trigonometry: 0°, 90°, 180°, 270° and back.
            let offsets: [(CGFloat, CGFloat)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
            let (dx, dy) = offsets[index % offsets.count]
            let scale: CGFloat = index < offsets.count ? 1 : 0.5
            subview.place(at: CGPoint(x: bounds.midX + dx * radius * scale, y: bounds.midY + dy * radius * scale), anchor: .center, proposal: .unspecified)
        }
    }
}

/// A layout value: how many extra points of leading space a subview gets.
struct IndentKey: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    func indent(_ value: CGFloat) -> some View { layoutValue(key: IndentKey.self, value: value) }
}

/// A vertical stack that indents by the layout value, orders by priority (higher first) and
/// spaces rows by their spacing preferences.
struct ValueLayout: Layout {
    private func order(_ subviews: Subviews) -> [Int] {
        subviews.indices.sorted { subviews[$0].priority > subviews[$1].priority || (subviews[$0].priority == subviews[$1].priority && $0 < $1) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        var height: CGFloat = 0, width: CGFloat = 0
        let indices = order(subviews)
        for (n, index) in indices.enumerated() {
            let size = subviews[index].sizeThatFits(.unspecified)
            if n > 0 { height += subviews[indices[n - 1]].spacing.distance(to: subviews[index].spacing, along: .vertical) }
            height += size.height
            width = max(width, size.width + subviews[index][IndentKey.self])
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        let indices = order(subviews)
        for (n, index) in indices.enumerated() {
            let size = subviews[index].sizeThatFits(.unspecified)
            if n > 0 { y += subviews[indices[n - 1]].spacing.distance(to: subviews[index].spacing, along: .vertical) }
            subviews[index].place(at: CGPoint(x: bounds.minX + subviews[index][IndentKey.self], y: y), proposal: ProposedViewSize(size))
            y += size.height
        }
    }
}

/// Drives `customlayout/any`.
@Observable
public final class CustomLayoutModel {
    public var horizontal = true
    public init() {}
}

public enum CustomLayoutFixtures {
    public static let flow = Fixture("customlayout/flow", size: CGSize(width: 320, height: 160)) {
        FlowLayout {
            Text("One").probe("one")
            Text("Two").probe("two")
            Text("Three").probe("three")
            Text("Four").probe("four")
            Text("Five").probe("five")
            Color.red.frame(width: 60, height: 30).probe("box")
            Text("Six").probe("six")
        }
        .frame(width: 160)
        .probe("flow")
    }

    public static let radial = Fixture("customlayout/radial", size: CGSize(width: 240, height: 240)) {
        RadialLayout {
            Text("A").probe("a")
            Text("B").probe("b")
            Color.blue.frame(width: 20, height: 20).probe("c")
            Text("D").probe("d")
            Text("E").probe("e")
        }
        .frame(width: 160, height: 160)
        .probe("radial")
    }

    public static let values = Fixture("customlayout/values", size: CGSize(width: 240, height: 160)) {
        ValueLayout {
            Text("Low").probe("low")
            Text("High").layoutPriority(1).indent(20).probe("high")
            Color.green.frame(width: 40, height: 10).indent(8).probe("bar")
            Text("Last").probe("last")
        }
        .probe("values")
    }

    public static let any = Fixture(
        "customlayout/any", size: CGSize(width: 240, height: 120),
        model: { CustomLayoutModel() },
        steps: [FixtureStep("vertical") { $0.horizontal = false }, FixtureStep("horizontal") { $0.horizontal = true }]
    ) { model in
        let layout = model.horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 4))
        layout {
            Text("One").probe("one")
            Color.red.frame(width: 30, height: 20).probe("box")
            Text("Three").probe("three")
        }
        .probe("stack")
    }

    public static let all: [Fixture] = [flow, radial, values, any]
}
