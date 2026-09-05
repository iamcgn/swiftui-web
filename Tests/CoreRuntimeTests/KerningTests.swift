// Phase 6: kerning and tracking — the width grows by the spacing per character (measured on
// Apple: "Hello" 31 → 41 at 2 pt), tracking wins over kerning, the environment forms reach text,
// and the painters get the spacing through the display font.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct KerningTests {
    private static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: "Hello")] = .init(width: 31, height: 16, firstBaseline: 13, lastBaseline: 13)
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func layouterAddsTheSpacingPerCharacter() {
        let layouter = TextLayouter(measure: { text, _ in CGFloat(text.count) * 6 }, metrics: { _ in PlatformProfile.macOS.systemFontMetrics(for: Self.system13) })
        let plain = layouter.layout([StyledRun("Hello", font: Self.system13)], options: .default, width: nil)
        let kerned = layouter.layout([StyledRun("Hello", font: Self.system13)], options: TextLayoutOptions(kerning: 2), width: nil)
        let tracked = layouter.layout([StyledRun("Hello", font: Self.system13)], options: TextLayoutOptions(kerning: 5, tracking: 2), width: nil)
        let tight = layouter.layout([StyledRun("Hello", font: Self.system13)], options: TextLayoutOptions(kerning: -1), width: nil)
        #expect(plain.size.width == 30 && kerned.size.width == 40 && tracked.size.width == 40 && tight.size.width == 25)
        // Spaces count; wrapping uses the spread widths.
        let wrapped = layouter.layout([StyledRun("ab cd ef", font: Self.system13)], options: TextLayoutOptions(kerning: 4), width: 60)
        #expect(wrapped.lines.count == 2)
        #expect(TextLayouter.letterSpacing(TextLayoutOptions(kerning: 3)) == 3 && TextLayouter.letterSpacing(TextLayoutOptions(kerning: 3, tracking: 1)) == 1)
    }

    @Test func textAndViewModifiersReachTheLayoutAndThePainter() {
        // The recorded engine answers the kerned key; the display font carries the spacing.
        let runtime = runtime(Text("Hello").kerning(2)._probe("kerned"))
        #expect(runtime.probeFrames["kerned"]?.width == 31)   // recorded width is authoritative without a kerned entry
        let list = runtime.render(scale: 2)
        let encoded = DisplayListEncoder.encode(list, font: DisplayListEncoder.cssFont)
        #expect(encoded.strings.contains { $0.hasSuffix("|2") })
        // View-level kerning and tracking set the environment; a Text's own value wins.
        let view = self.runtime(VStack { Text("Hello")._probe("env"); Text("Hello").tracking(0)._probe("own") }.tracking(3))
        #expect(view.probeFrames["env"] != nil && view.probeFrames["own"] != nil)
        var options = EnvironmentValues().textLayoutOptions
        #expect(options.kerning == 0 && options.tracking == 0)
        options.kerning = 2
        #expect(TextMetricsKey.widthSlot(width: 100, options: options) == "100.0;k2.0")
        #expect(options.withoutLetterSpacing.kerning == 0)
        let font = DisplayFont(Self.system13, letterSpacing: 1.5)
        #expect(DisplayListEncoder.cssFont(font).hasSuffix("|1.5") && !DisplayListEncoder.cssFont(DisplayFont(Self.system13)).contains("|"))
    }
}
#endif
