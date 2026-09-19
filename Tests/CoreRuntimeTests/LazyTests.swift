// Phase 8 step 6, sw-lazy: elements created as they scroll into view, pinned section headers
// and footers, sections in grids (Docs/elements/Lazy.md).
import Testing
import SwiftUI

@Observable
private final class Target {
    var id: Int? = nil
}

private struct LazyRows: View {
    let target: Target
    var count = 200
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        Color.blue.frame(width: 100, height: 20)._probe("row\(index)").id(index)
                    }
                }
            }
            .onChange(of: target.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
}

private struct Pinned: View {
    var pinned: PinnedScrollableViews
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: pinned) {
                ForEach(0..<3, id: \.self) { section in
                    Section {
                        ForEach(0..<8, id: \.self) { row in
                            Color.blue.frame(width: 100, height: 20)._probe("s\(section)r\(row)")
                        }
                    } header: {
                        Color.gray.frame(width: 100, height: 24)._probe("h\(section)")
                    } footer: {
                        Color.black.frame(width: 100, height: 16)._probe("f\(section)")
                    }
                }
            }
        }
    }
}

@Suite @MainActor struct LazyTests {
    private let size = CGSize(width: 300, height: 200)

    @Test func createsRowsAsTheyScrollIntoView() {
        let target = Target()
        let runtime = Runtime()
        runtime.mount(LazyRows(target: target))
        runtime.layout(in: size)
        // The rows within a viewport beyond the visible ones exist; the far ones do not.
        #expect(runtime.probeFrames["row19"] != nil)
        #expect(runtime.probeFrames["row20"] == nil)
        #expect(runtime.probeFrames["row199"] == nil)
        // Placeholders keep the content's full height: the scroll reaches the last row.
        runtime.scrollWheel(by: CGSize(width: 0, height: 10_000), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row199"]?.minY == 180)
        #expect(runtime.probeFrames["row100"] == nil)
        // A reader scroll to a row not yet created creates it where its placeholder sat.
        target.id = 100
        runtime.layout(in: size)
        #expect(runtime.probeFrames["row100"]?.minY == 0)
        #expect(runtime.probeFrames["row109"]?.minY == 180)
    }

    @Test func scrollingByWheelCreatesAheadWithoutLayingOutEveryFrame() {
        let runtime = Runtime()
        runtime.mount(LazyRows(target: Target()))
        runtime.layout(in: size)
        let layouts = runtime.fullLayoutCount
        runtime.scrollWheel(by: CGSize(width: 0, height: 20), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        // Probes read geometry, so a fixture scroll always lays out; the rows ahead are created.
        #expect(runtime.fullLayoutCount > layouts)
        #expect(runtime.probeFrames["row20"] != nil)
    }

    @Test func pinsHeadersAndFooters() {
        let runtime = Runtime()
        runtime.mount(Pinned(pinned: [.sectionHeaders, .sectionFooters]))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["h0"]?.minY == 0)
        #expect(runtime.probeFrames["f0"]?.minY == 184)
        // Section 1 (200–400) scrolled 84 up: its header sticks at the top, section 2's footer
        // (natural 584) at the bottom.
        runtime.scrollWheel(by: CGSize(width: 0, height: 284), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["h1"]?.minY == 0)
        #expect(runtime.probeFrames["s1r3"]?.minY == 0)
        #expect(runtime.probeFrames["f1"]?.minY == 100)
        #expect(runtime.probeFrames["h2"]?.minY == 116)
        #expect(runtime.probeFrames["f2"]?.minY == 184)
        // Approaching section 2's header pushes section 1's header up.
        runtime.scrollWheel(by: CGSize(width: 0, height: 100), at: CGPoint(x: 150, y: 100))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["h2"]?.minY == 16)
        #expect(runtime.probeFrames["h1"]?.minY == -8)
        // The pinned header (at −8) paints after the rows it covers (the last row of its
        // section sits at −20).
        let commands = runtime.render(scale: 2).commands.map(\.description)
        let header = commands.lastIndex { $0.hasPrefix("fillRect(100, -8, 100, 24)") }
        let row = commands.lastIndex { $0.hasPrefix("fillRect(100, -20, 100, 20)") }
        #expect(header != nil && row != nil && header! > row!)
    }

    @Test func gridSectionsTakeTheirOwnLines() {
        let runtime = Runtime()
        runtime.mount(ScrollView {
            LazyVGrid(columns: [GridItem(.fixed(60)), GridItem(.fixed(60))], spacing: 4) {
                Section {
                    ForEach(0..<3, id: \.self) { index in Color.red.frame(height: 20)._probe("a\(index)") }
                } header: {
                    Color.gray.frame(height: 24)._probe("aH")
                } footer: {
                    Color.black.frame(height: 16)._probe("aF")
                }
            }._probe("grid")
        }.frame(width: 200))
        runtime.layout(in: size)
        #expect(runtime.probeFrames["aH"] == CGRect(x: 50, y: 0, width: 200, height: 24))
        #expect(runtime.probeFrames["a0"] == CGRect(x: 86, y: 28, width: 60, height: 20))
        #expect(runtime.probeFrames["a2"] == CGRect(x: 86, y: 52, width: 60, height: 20))
        #expect(runtime.probeFrames["aF"] == CGRect(x: 50, y: 76, width: 200, height: 16))
        #expect(runtime.probeFrames["grid"]?.height == 92)
    }
}
