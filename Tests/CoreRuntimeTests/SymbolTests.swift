// Image(systemName:): measured layout sizes (font sizes, weights, image scales), the glyph's
// baseline, scaling for unmeasured sizes, and the stand-in glyph's painting. Layout against
// goldens is in GoldenFrameTests (symbol/basic, symbol/catalog-*).
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct SymbolTests {
    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    private func size<V: View>(_ view: V) -> CGSize? { runtime(view._probe("s")).probeFrames["s"]?.size }

    @Test func measuredSizes() {
        // 13 pt regular is measured exactly, as are the text-style sizes, 13 pt weights and scales.
        #expect(size(Image(systemName: "star")) == CGSize(width: 16.5, height: 16))
        #expect(size(Image(systemName: "star").font(.title)) == CGSize(width: 28.5, height: 26))
        #expect(size(Image(systemName: "star").font(.system(size: 10))) == CGSize(width: 13, height: 11.5))
        #expect(size(Image(systemName: "star").bold()) == CGSize(width: 17, height: 16.5))
        #expect(size(Image(systemName: "star").fontWeight(.semibold)) == CGSize(width: 17, height: 16))
        #expect(size(Image(systemName: "star").imageScale(.small)) == CGSize(width: 13.5, height: 13))
        #expect(size(Image(systemName: "star").imageScale(.large)) == CGSize(width: 21.5, height: 20.5))
        #expect(size(Image(systemName: "ellipsis")) == CGSize(width: 14, height: 4.5))
        #expect(size(Image(systemName: "chevron.right")) == CGSize(width: 10, height: 13.5))
        // Unmeasured sizes scale the nearest measured size at or below, to the half point.
        #expect(size(Image(systemName: "star").font(.system(size: 24))) == CGSize(width: 31, height: 28.5))
        // A symbol with a glyph but no measurement takes the star's size; an unknown name has none.
        #expect(size(Image(systemName: "cloud.rain")) == CGSize(width: 16.5, height: 16))
        #expect(size(Image(systemName: "not.a.symbol")) == .zero)
        // Resizable symbols fill their frame.
        #expect(size(Image(systemName: "star").resizable().frame(width: 40, height: 20)) == CGSize(width: 40, height: 20))
    }

    @Test func baselines() {
        // The frame sits 3 pt below the baseline at 13 pt; the ellipsis floats 2.5 above it.
        let r = runtime(HStack(alignment: .firstTextBaseline, spacing: 0) {
            Image(systemName: "star")._probe("star")
            Image(systemName: "ellipsis")._probe("dots")
            Image(systemName: "star").font(.title)._probe("title")
        })
        let star = r.probeFrames["star"]!, dots = r.probeFrames["dots"]!, title = r.probeFrames["title"]!
        #expect(star.maxY - 3 == dots.maxY + 2.5)
        #expect(title.maxY - 4.5 == star.maxY - 3)
    }

    @Test func glyphPainting() {
        let r = runtime(Image(systemName: "star")._probe("s"))
        var commands = r.render(scale: 2).commands.map(\.description)
        // One stroked path in the primary colour, round caps and joins, the weight's stroke.
        #expect(commands.count == 1)
        #expect(commands[0].hasPrefix("strokePath(") && commands[0].contains("cap=round join=round #000000@0.85"))
        // Filled symbols fill then stroke; a colour applies.
        commands = runtime(Image(systemName: "star.fill").foregroundColor(.red)._probe("s")).render(scale: 2).commands.map(\.description)
        #expect(commands.count == 2 && commands[0].hasPrefix("fillPath(") && commands[1].hasPrefix("strokePath("))
        #expect(commands[0].hasSuffix("#FF383C"))
        // Circle-fill symbols fill the circle and knock the mark out in white.
        commands = runtime(Image(systemName: "checkmark.circle.fill")._probe("s")).render(scale: 2).commands.map(\.description)
        #expect(commands.count == 3 && commands[2].hasPrefix("strokePath(") && commands[2].hasSuffix("#FFFFFF"))
        // Bold strokes wider than regular; nothing is drawn for an unknown name.
        let regular = r.render(scale: 2).commands.first!.description
        let bold = runtime(Image(systemName: "star").bold()._probe("s")).render(scale: 2).commands.first!.description
        func width(_ s: String) -> Double { Double(s.split(separator: " ").first { $0.hasPrefix("w=") }!.dropFirst(2))! }
        #expect(width(bold) > width(regular))
        #expect(runtime(Image(systemName: "not.a.symbol")._probe("s")).render(scale: 2).commands.isEmpty)
    }
}
#endif
