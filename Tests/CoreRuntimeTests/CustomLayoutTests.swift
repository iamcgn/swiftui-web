// Custom Layout (Phase 2): AnyLayout switches layouts without recreating the subviews (their
// state survives), a layout's cache is remade for a new erased type, and LayoutSubview
// proxies expose priority, spacing and layout values.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct CustomLayoutTests {
    @Observable final class Model: @unchecked Sendable { var horizontal = true }

    struct Counter: View {
        @State private var count = 0
        var body: some View {
            Button("+") { count += 1 }
            Text("Count: \(count)")
        }
    }

    struct Switching: View {
        let model: Model
        var body: some View {
            let layout = model.horizontal ? AnyLayout(HStackLayout(spacing: 8)) : AnyLayout(VStackLayout(spacing: 4))
            layout {
                Counter()
                Color.red.frame(width: 30, height: 20)._probe("box")
            }
        }
    }

    @Test func anyLayoutSwitchesWithoutLosingState() {
        let model = Model()
        let r = Runtime()
        r.mount(Switching(model: model))
        r.layout(in: CGSize(width: 240, height: 120))
        let plus = r.semanticsTree().first { $0.label == "+" }!
        r.activate(semanticsIdentifier: plus.identifier)
        r.layout(in: CGSize(width: 240, height: 120))
        let horizontalBox = r.probeFrames["box"]!
        model.horizontal = false
        r.layout(in: CGSize(width: 240, height: 120))
        // The layout changed (the box moved below), the button still has its identity and count.
        #expect(r.probeFrames["box"] != horizontalBox)
        let again = r.semanticsTree().first { $0.label == "+" }!
        #expect(again.identifier == plus.identifier)
        r.activate(semanticsIdentifier: again.identifier)
        r.layout(in: CGSize(width: 240, height: 120))
        #expect(r.semanticsTree().contains { $0.label == "+" })
    }

    struct Ranked: LayoutValueKey { static let defaultValue = 0 }

    struct Probe: Layout {
        let record: (Double, Int, CGFloat) -> Void
        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            for subview in subviews { record(subview.priority, subview[Ranked.self], subview.spacing.distance(to: subviews[0].spacing, along: .vertical)) }
            return CGSize(width: 10, height: 10)
        }
        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {}
    }

    @Test func subviewProxiesExposeValues() {
        var seen: [(Double, Int, CGFloat)] = []
        let r = Runtime()
        r.mount(Probe(record: { seen.append(($0, $1, $2)) }) {
            Color.red.frame(width: 10, height: 10).layoutPriority(2).layoutValue(key: Ranked.self, value: 7)
            Color.blue.frame(width: 10, height: 10)
        })
        r.layout(in: CGSize(width: 100, height: 100))
        #expect(seen.first?.0 == 2 && seen.first?.1 == 7 && seen.first?.2 == 8)
        #expect(seen.last?.0 == 0 && seen.last?.1 == 0)
    }

    /// A Swift 6 layout written the way SwiftUI allows: nonisolated methods, and a nonisolated
    /// protocol that `LayoutSubview` satisfies (SwiftUI-Flow does both).
    struct Column: Layout {
        nonisolated func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            subviews.reduce(CGSize.zero) { total, subview in
                let size = (subview as any Measured).measure(.unspecified)
                return CGSize(width: max(total.width, size.width), height: total.height + size.height)
            }
        }
        nonisolated func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var y = bounds.minY
            for subview in subviews {
                subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: .unspecified)
                y += subview.sizeThatFits(.unspecified).height
            }
        }
    }

    @Test func nonisolatedLayoutMeasuresSubviews() {
        let r = Runtime()
        r.mount(Column {
            Color.red.frame(width: 30, height: 10)._probe("a")
            Color.blue.frame(width: 20, height: 15)._probe("b")
        }._probe("column"))
        r.layout(in: CGSize(width: 100, height: 100))
        let f = r.probeFrames
        #expect(f["column"]?.size == CGSize(width: 30, height: 25))
        #expect(f["b"].map { $0.minY - f["a"]!.minY } == 10)
    }
}

protocol Measured { func measure(_ proposal: ProposedViewSize) -> CGSize }
extension LayoutSubview: Measured {
    func measure(_ proposal: ProposedViewSize) -> CGSize { let d = dimensions(in: proposal); return CGSize(width: d.width, height: d.height) }
}
#endif
