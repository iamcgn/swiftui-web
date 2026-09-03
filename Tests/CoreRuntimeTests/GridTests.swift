// Grid (Phase 2): column sizing from rigid cells, flexible columns sharing a proposal, spanning
// cells spreading extra width, anchors and column alignment, vertical spacing from cells.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct GridTests {
    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 300, height: 200)) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func rigidColumnsAndSpans() {
        let r = runtime(Grid(horizontalSpacing: 10, verticalSpacing: 5) {
            GridRow {
                Color.red.frame(width: 20, height: 10)._probe("a")
                Color.red.frame(width: 40, height: 20)._probe("b")
            }
            GridRow {
                Color.blue.frame(width: 90, height: 10).gridCellColumns(2)._probe("wide")
            }
            GridRow {
                Color.green.frame(width: 10, height: 10).gridCellAnchor(.topTrailing)._probe("anchored")
                Color.green.frame(width: 10, height: 10).gridColumnAlignment(.trailing)._probe("trailing")
            }
        }._probe("grid"))
        // Columns 20 and 40 plus the 10 gap = 70; the 90-wide span adds 10 to each column: 30 + 10 + 50.
        #expect(r.probeFrames["grid"]?.size == CGSize(width: 90, height: 50))
        let grid = r.probeFrames["grid"]!
        #expect(r.probeFrames["a"] == CGRect(x: grid.minX + 5, y: grid.minY + 5, width: 20, height: 10))   // centred in 30 × 20
        #expect(r.probeFrames["wide"] == CGRect(x: grid.minX, y: grid.minY + 25, width: 90, height: 10))
        #expect(r.probeFrames["anchored"] == CGRect(x: grid.minX + 20, y: grid.minY + 40, width: 10, height: 10))
        #expect(r.probeFrames["trailing"] == CGRect(x: grid.minX + 80, y: grid.minY + 40, width: 10, height: 10))
    }

    @Test func flexibleColumnsShareTheProposal() {
        let r = runtime(Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.red.frame(height: 10)._probe("flex1")
                Color.blue.frame(width: 50, height: 10)._probe("rigid")
                Color.green.frame(height: 10)._probe("flex2")
            }
        }.frame(width: 250)._probe("grid"))
        #expect(r.probeFrames["flex1"]?.width == 100 && r.probeFrames["flex2"]?.width == 100 && r.probeFrames["rigid"]?.width == 50)
        // A flexible spanning child fills the row and spreads the extra over its columns.
        let s = runtime(Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.red.frame(width: 20, height: 10)._probe("a")
                Color.blue.frame(width: 40, height: 10)._probe("b")
            }
            Color.green.frame(height: 4)._probe("divider")
        }.frame(width: 200)._probe("grid"))
        #expect(s.probeFrames["divider"]?.width == 200)
        #expect(s.probeFrames["b"]?.minX == s.probeFrames["grid"]!.minX + 20 + 70)   // column 1 grew by 70
    }
}
#endif
