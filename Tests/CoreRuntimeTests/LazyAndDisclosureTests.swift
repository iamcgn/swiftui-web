// Lazy stacks and grids (track resolution, flow, cross-axis filling) and DisclosureGroup
// (toggling by press, own state, chevron, styles). Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct LazyLayoutTests {
    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 300, height: 200)) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func gridTracks() {
        let layout = _LazyGridLayout(axis: .vertical, tracks: [GridItem(.fixed(60)), GridItem(.flexible()), GridItem(.flexible(minimum: 20, maximum: 80))],
                                     alignment: .center, spacing: nil)
        // Fixed first, the rest shared equally, each clamped (the remainder is not redistributed).
        #expect(layout.resolvedTracks(in: 280).map(\.size) == [60, 102, 80])
        #expect(layout.resolvedTracks(in: 280).map(\.spacingAfter) == [8, 8, 0])
        // Adaptive: as many tracks of the shared width as fit.
        let adaptive = _LazyGridLayout(axis: .vertical, tracks: [GridItem(.adaptive(minimum: 50), spacing: 10)], alignment: .center, spacing: nil)
        #expect(adaptive.resolvedTracks(in: 240).map(\.size) == [52.5, 52.5, 52.5, 52.5])
        #expect(adaptive.resolvedTracks(in: 240).map(\.spacingAfter) == [10, 10, 10, 0])
        // Without a proposal flexible tracks take their minimum.
        #expect(layout.resolvedTracks(in: nil).map(\.size) == [60, 10, 20])
    }

    @Test func gridsFlowAndStacksFill() {
        // Cells flow row by row; the grid takes the frame's width and centres its tracks in it.
        let grid = runtime(LazyVGrid(columns: [GridItem(.fixed(40)), GridItem(.fixed(40))], spacing: 4) {
            ForEach(0..<3, id: \.self) { index in Color.red.frame(height: 10)._probe("c\(index)") }
        }.frame(width: 120)._probe("grid"))
        #expect(grid.probeFrames["grid"] == CGRect(x: 90, y: 88, width: 120, height: 24))
        #expect(grid.probeFrames["c0"] == CGRect(x: 106, y: 88, width: 40, height: 10))
        #expect(grid.probeFrames["c1"] == CGRect(x: 154, y: 88, width: 40, height: 10))
        #expect(grid.probeFrames["c2"] == CGRect(x: 106, y: 102, width: 40, height: 10))
        // A horizontal grid flows column by column.
        let rows = runtime(LazyHGrid(rows: [GridItem(.fixed(30)), GridItem(.fixed(30))], spacing: 6) {
            ForEach(0..<3, id: \.self) { index in Color.green.frame(width: 40)._probe("h\(index)") }
        }.frame(height: 70)._probe("hgrid"))
        #expect(rows.probeFrames["hgrid"]?.size == CGSize(width: 86, height: 70))
        #expect(rows.probeFrames["h1"]?.origin.y == (rows.probeFrames["h0"]?.origin.y ?? 0) + 38)
        #expect(rows.probeFrames["h2"]?.origin.x == (rows.probeFrames["h0"]?.origin.x ?? 0) + 46)
        // Lazy stacks fill their cross axis.
        let stacks = runtime(HStack(spacing: 0) {
            LazyVStack(alignment: .leading) { Color.red.frame(width: 20, height: 20)._probe("red") }._probe("v")
            LazyHStack(alignment: .bottom) { Color.blue.frame(width: 20, height: 20)._probe("blue") }._probe("h")
        })
        #expect(stacks.probeFrames["v"]?.size == CGSize(width: 280, height: 20))
        #expect(stacks.probeFrames["h"]?.size == CGSize(width: 20, height: 200))
        #expect(stacks.probeFrames["blue"]?.maxY == 200)
    }
}

@Suite @MainActor struct DisclosureGroupTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Details"): .init(width: 44, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Inside"): .init(width: 36.5, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Observable final class ExpandModel: @unchecked Sendable { var expanded = false }

    @Test func rowsAndToggling() {
        let box = ExpandModel()
        let r = runtime(DisclosureGroup("Details", isExpanded: Binding(get: { box.expanded }, set: { box.expanded = $0 })) {
            Text("Inside")._probe("inside")
        }._probe("group"))
        // Collapsed: a 24 pt full-width row, the label 11.5 in; the chevron is a grey stroke.
        #expect(r.probeFrames["group"] == CGRect(x: 0, y: 38, width: 200, height: 24))
        #expect(r.probeFrames["inside"] == nil)
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("strokePath(3 elements) w=1.5 cap=round join=round #000000@\(64.0 / 255)") })
        #expect(commands.contains { $0.hasPrefix("drawText(\"Details\" system 13 w400 at 11.5,") })
        // A press on the row expands; the content is centred under it.
        r.pointerDown(at: CGPoint(x: 30, y: 50)); r.pointerUp(at: CGPoint(x: 30, y: 50))
        #expect(box.expanded)
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.probeFrames["group"]?.height == 40)
        #expect(r.probeFrames["inside"] == CGRect(x: (200 - 36.5) / 2, y: 30 + 24, width: 36.5, height: 16))
        // Without a binding the group keeps its own state.
        let own = runtime(DisclosureGroup("Details") { Text("Inside")._probe("inside") }._probe("group"))
        #expect(own.probeFrames["inside"] == nil)
        own.pointerDown(at: CGPoint(x: 30, y: 50)); own.pointerUp(at: CGPoint(x: 30, y: 50))
        own.layout(in: CGSize(width: 200, height: 100))
        #expect(own.probeFrames["inside"] != nil)
    }

    struct BareStyle: DisclosureGroupStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack { configuration.label; if configuration.isExpanded { configuration.content } }
        }
    }

    @Test func customStyle() {
        let r = runtime(DisclosureGroup("Details", isExpanded: .constant(true)) { Text("Inside") }.disclosureGroupStyle(BareStyle())._probe("group"))
        #expect(r.probeFrames["group"]?.size == CGSize(width: 44 + 8 + 36.5, height: 16))
    }
}

#endif
