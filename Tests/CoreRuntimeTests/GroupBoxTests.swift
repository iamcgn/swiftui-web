// GroupBox: the card around the content, the label above it, widths from the wider of the
// two, nesting and styles. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct GroupBoxTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let subheadline = ResolvedFont(family: "system", size: 11, weight: .regular, italic: false, textStyle: .subheadline)

    private func runtime<V: View>(_ view: V) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Settings", 52.0), ("Inside", 36.5), ("Long title here", 90.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.subheadline, width: nil, string: word)] = .init(width: width * 11 / 13, height: 16, firstBaseline: 12, lastBaseline: 12)
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func cardAndLabel() {
        // Untitled: the content padded 5 in a 12 pt rounded card at black 8/255.
        let plain = runtime(GroupBox { Text("Inside")._probe("content") }._probe("box"))
        #expect(plain.probeFrames["box"] == CGRect(x: 76.75, y: 37, width: 46.5, height: 26))
        #expect(plain.probeFrames["content"] == CGRect(x: 81.75, y: 42, width: 36.5, height: 16))
        let commands = plain.render(scale: 2).commands.map(\.description)
        // The continuous-corner card is a path; it fills at black 8/255.
        #expect(commands.first?.hasPrefix("fillPath(") == true && commands.first?.hasSuffix("#000000@\(8.0 / 255)") == true)
        // Titled: the subheadline label 10 pt in, 3 above the card; the box is as wide as the
        // wider of the label (+10) and the card.
        let titled = runtime(GroupBox("Settings") { Text("Inside")._probe("content") }._probe("box"))
        #expect(titled.probeFrames["box"]?.size == CGSize(width: 54, height: 16 + 3 + 26))
        #expect(titled.probeFrames["content"]?.minY == (titled.probeFrames["box"]?.minY ?? 0) + 19 + 5)
        #expect(titled.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("drawText(\"Settings\" system 11") })
        let wideLabel = runtime(GroupBox("Long title here") { Text("Inside") }._probe("box"))
        #expect(abs((wideLabel.probeFrames["box"]?.width ?? 0) - (90.0 * 11 / 13 + 10)) < 1e-9)
        // Nested boxes add their padding; a custom label view is any view.
        let nested = runtime(GroupBox { GroupBox { Text("Inside") }._probe("inner") }._probe("outer"))
        #expect(nested.probeFrames["outer"]?.size == CGSize(width: 56.5, height: 36))
        let custom = runtime(GroupBox { Text("Inside") } label: { Color.red.frame(width: 30, height: 30)._probe("label") }._probe("box"))
        #expect(custom.probeFrames["label"]?.size == CGSize(width: 30, height: 30))
        #expect(abs((custom.probeFrames["box"]?.height ?? 0) - 59) < 1e-9)
    }

    struct FlatStyle: GroupBoxStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack { configuration.label; configuration.content }
        }
    }

    @Test func customStyle() {
        let r = runtime(GroupBox("Settings") { Text("Inside")._probe("content") }.groupBoxStyle(FlatStyle())._probe("box"))
        #expect(r.probeFrames["box"]?.height == 16)
        #expect(r.render(scale: 2).commands.map(\.description).allSatisfy { !$0.hasPrefix("fillRRect") })
    }
}
#endif
