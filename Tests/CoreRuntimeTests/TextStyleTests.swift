// Phase 6: underline / strikethrough (lines snapped to device pixels, patterns, colours, on the
// text and on the view), textCase, baselineOffset.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct TextStyleTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime() -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.body, width: nil, string: "Hello"): .init(width: 31, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.body, width: nil, string: "HELLO"): .init(width: 36, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.body, width: nil, string: "hello"): .init(width: 28, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
        return runtime
    }

    private func render<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> [String] {
        let runtime = runtime()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime.render(scale: 2).commands.map(\.description)
    }

    @Test func underlineAndStrikethroughSnapToPixels() {
        // 13 pt: underline centre 1.97 below the baseline, thickness 0.76 → one 2-pixel row whose
        // top rounds to 14.5 pt; the strikethrough centres on half the x-height (6.84).
        let text = render(Text("Hello").underline())
        #expect(text == ["drawText(\"Hello\" system 13 w400 at 84.5,55 #000000@0.85)", "fillRect(84.5, 56.5, 31, 1) #000000@0.85"])
        let struck = render(Text("Hello").strikethrough(true, color: .red))
        #expect(struck.last == "fillRect(84.5, 51, 31, 1) #FF383C")
        // Patterns stroke a dashed line in multiples of the thickness; the view modifier reaches
        // every text and a text-level `false` opts out.
        let dotted = render(Text("Hello").underline(true, pattern: .dot))
        #expect(dotted.last == "strokePath(2 elements) w=1 dash=[3,3] #000000@0.85")
        let viewLevel = render(VStack { Text("Hello"); Text("Hello").underline(false) }.underline())
        #expect(viewLevel.filter { $0.hasPrefix("fillRect") }.count == 1)
    }

    @Test func textCaseTransformsTheLaidOutString() {
        #expect(render(Text("Hello").textCase(.uppercase)).first?.contains("\"HELLO\"") == true)
        #expect(render(Text("Hello").textCase(.lowercase)).first?.contains("\"hello\"") == true)
        let runtime = runtime()
        runtime.mount(Text("Hello").textCase(.uppercase))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(runtime.root.layoutChildren.first?.frame.width == 36)
    }

    @Test func baselineOffsetGrowsTheTextAndMovesTheGlyphs() {
        // A raise adds space below the baseline guide; a drop adds space below the glyphs.
        let runtime = runtime()
        runtime.mount(HStack(alignment: .firstTextBaseline, spacing: 0) { Text("Hello"); Text("Hello").baselineOffset(6); Text("Hello").baselineOffset(-4) })
        runtime.layout(in: CGSize(width: 200, height: 100))
        let frames = runtime.root.layoutChildren.first!.paintedChildren.map(\.frame)
        #expect(frames.map(\.height) == [16, 22, 20])
        // The row is 26 high (the raised text's guide sits 19 from its top), centred at 37.
        #expect(frames.map(\.minY) == [6, 0, 6])
        let commands = runtime.render(scale: 2).commands.map(\.description)
        #expect(commands == ["drawText(\"Hello\" system 13 w400 at 53.5,56 #000000@0.85)",
                             "drawText(\"Hello\" system 13 w400 at 84.5,50 #000000@0.85)",
                             "drawText(\"Hello\" system 13 w400 at 115.5,60 #000000@0.85)"])
    }
}
#endif
