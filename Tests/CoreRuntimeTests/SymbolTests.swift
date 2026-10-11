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

    /// The fidelity tests load the full catalog into the shared table; these expect the built-in
    /// set alone (they reload it when they next run).
    init() { SystemSymbolMetricsTable.load(text: "") }

    @Test func measuredSizes() {
        // 13 pt regular is measured exactly, as are the text-style sizes, 13 pt weights and scales
        // (macOS 27: the title and 10 pt stars are 1 pt taller than on OS 26, `legacySizes`).
        #expect(size(Image(systemName: "star")) == CGSize(width: 16.5, height: 16))
        #expect(size(Image(systemName: "star").font(.title)) == CGSize(width: 28.5, height: 27))
        #expect(size(Image(systemName: "star").font(.system(size: 10))) == CGSize(width: 13, height: 12.5))
        #expect(size(Image(systemName: "star").bold()) == CGSize(width: 17, height: 16.5))
        #expect(size(Image(systemName: "star").fontWeight(.semibold)) == CGSize(width: 17, height: 16))
        #expect(size(Image(systemName: "star").imageScale(.small)) == CGSize(width: 13.5, height: 13))
        #expect(size(Image(systemName: "star").imageScale(.large)) == CGSize(width: 21.5, height: 20.5))
        #expect(size(Image(systemName: "ellipsis")) == CGSize(width: 14, height: 4.5))
        #expect(size(Image(systemName: "chevron.right")) == CGSize(width: 10, height: 13.5))
        // Unmeasured sizes scale the nearest measured size at or below, to the half point.
        #expect(size(Image(systemName: "star").font(.system(size: 24))) == CGSize(width: 31, height: 29.5))
        // A symbol with a glyph but no built-in measurement takes the star's size until the full
        // table is loaded; an unknown name has none.
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
        #expect(title.maxY - 5 == star.maxY - 3)   // the title star's descent is 5 on macOS 27 (4.5 on 26)
    }

    /// The full catalog (sw-symbols): a host loads `symbol-metrics.txt` on the first symbol outside
    /// the built-in table and the runtime lays out again; a catalog symbol without a stand-in
    /// glyph draws the dashed square; the iOS profile keeps the OS 26 generation's sizes.
    @Test func fullCatalogLoadsOnDemand() throws {
        let r = Runtime()
        var requests = 0
        r.onNeedsSymbolMetrics = { requests += 1 }
        r.mount(HStack(spacing: 0) {
            Image(systemName: "tortoise")._probe("rain")   // a stand-in glyph, no built-in size
            Image(systemName: "figure.archery")._probe("archery")   // no stand-in glyph
            Image(systemName: "star")._probe("star")
        })
        r.layout(in: CGSize(width: 300, height: 100))
        #expect(requests == 1 && r.probeFrames["rain"]?.size == CGSize(width: 16.5, height: 16), "\(requests) \(r.probeFrames["rain"] as Any)")
        #expect(r.probeFrames["archery"]?.size == CGSize(width: 16.5, height: 16))   // pending: the star's size
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Goldens/symbol/metrics-full.txt")
        SystemSymbolMetricsTable.load(text: try String(contentsOf: file, encoding: .utf8))
        defer { SystemSymbolMetricsTable.load(text: "") }
        #expect(SystemSymbolMetricsTable.isExtended && SystemSymbolMetricsTable.extended.count > 9000)
        r.symbolMetricsDidLoad()
        r.layout(in: CGSize(width: 300, height: 100))
        #expect(r.probeFrames["rain"]?.size == CGSize(width: 24.5, height: 13), "\(r.probeFrames["rain"] as Any)")
        #expect(r.probeFrames["archery"]?.size == CGSize(width: 16, height: 17.5), "\(r.probeFrames["archery"] as Any)")
        let painted = r.render(scale: 2).commands.map(\.description)
        #expect(painted.count >= 3)   // the archery figure draws the dashed square
        // The iOS profile keeps the OS 26 sizes for the built-in symbols.
        var environment = EnvironmentValues()
        environment.platformProfile = .iOS
        let ios = Runtime(environment: environment)
        ios.textEngine = RecordedTextEngine(entries: [:])
        ios.mount(Image(systemName: "star").font(.system(size: 10))._probe("s"))
        ios.layout(in: CGSize(width: 100, height: 100))
        #expect(ios.probeFrames["s"]?.size == CGSize(width: 13, height: 11.5))
        // A variable value dims the stand-in to 30 % and lights its leading fraction.
        let variable = Runtime()
        variable.mount(Image(systemName: "star", variableValue: 0.5))
        variable.layout(in: CGSize(width: 100, height: 100))
        let commands = variable.render(scale: 2).commands.map(\.description)
        #expect(commands.first == "beginGroup(opacity: 0.3)" && commands.contains { $0.hasPrefix("clipRect(") }, "\(commands)")
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
